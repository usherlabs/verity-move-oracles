import { log } from "@/logger";
import type { ProcessedRequestAdded } from "@/types";
import { run as jqRun } from "node-jq";

import { hosts as xHosts, instance as xTwitterInstance } from "@/integrations/xtwitter";
import { isValidJson } from "@/util";
import axios, { type AxiosResponse } from "axios";

const ALLOWED_HOST = [...xHosts];
// TODO: We'll eventually need to framework our this orchestrator and indexer to allow Oracle Operators to create their own connections to various hosts.

// Abstract base class
export abstract class Indexer {
  constructor(
    protected oracleAddress: string,
    protected orchestrator: string,
  ) {
    log.info(`Oracle Contract Address: ${this.oracleAddress}`);
    log.info(`Orchestrator Oracle Node Address: ${this.orchestrator}`);
  }

  // Abstract: Implementation To fetch Data
  abstract fetchRequestAddedEvents<T>(cursor: null | number | string): Promise<ProcessedRequestAdded<T>[]>;

  // Abstract: Implementation to send Fulfillment  blockchain fulfillment Request
  /**
   * Sends a fulfillment transaction to on-chain Contract.
   *
   * @param {IRequestAdded} data - The request data that needs to be fulfilled.
   * @param {number} status - The status of the fulfillment.
   * @param {string} result - The result of the fulfillment.
   * @returns {Promise<any>} - The receipt of the transaction.
   */
  abstract sendFulfillment<T>(data: ProcessedRequestAdded<T>, status: number, result: string): void;

  // Abstract: Implementation to get chain identifier. its usually a concat between blockchain and network e.g ("ROOCH-testnet","APTOS-mainnet")
  abstract getChainId(): string;

  // Abstract: Runs indexer
  abstract run(): void;

  getOrchestratorAddress(): string {
    return this.orchestrator.toLowerCase();
  }

  getOracleAddress(): string {
    return this.oracleAddress;
  }

  applyAuthorizationHeader(hostname: string): string | undefined {
    if (ALLOWED_HOST.includes(hostname) && xTwitterInstance.isInitialized()) {
      const token = xTwitterInstance.getAccessToken();
      return `Bearer ${token}`;
    }
    return undefined;
  }

  /**
   * Processes the "RequestAdded" event.
   *
   * This function validates the request, makes an HTTP request to the specified URL,
   * and processes the response based on the provided "pick" value.
   *
   * @param {IRequestAdded} data - The request data that needs to be processed.
   * @returns {Promise<{status: number, message: string} | null>} - The status and message of the processed request, or null if the request is not valid.
   */
  async processRequestAddedEvent<T>(data: ProcessedRequestAdded<T>) {
    log.debug("processing request:", data.request_id);
    const token = xTwitterInstance.getAccessToken();

    if (data.oracle.toLowerCase() !== this.getOrchestratorAddress().toLowerCase()) {
      return null;
    }
    const url = data.params.url?.includes("http") ? data.params.url : `https://${data.params.url}`;
    try {
      const _url = new URL(url);

      if (!ALLOWED_HOST.includes(_url.hostname.toLowerCase())) {
        return { status: 406, message: `${_url.hostname} is supposed by this orchestrator` };
      }
    } catch (err) {
      return { status: 406, message: `Invalid Domain Name` };
    }

    try {
      let request: AxiosResponse<any, any>;
      if (isValidJson(data.params.headers)) {
        // TODO: Replace direct requests via axios with requests via VerityClient TS module
        request = await axios({
          method: data.params.method,
          data: data.params.body,
          url: url,
          headers: {
            ...JSON.parse(data.params.headers),
            Authorization: `Bearer ${token}`,
          },
        });
        // return { status: request.status, message: request.data };
      } else {
        request = await axios({
          method: data.params.method,
          data: data.params.body,
          url: url,
          headers: {
            Authorization: `Bearer ${token}`,
          },
        });
      }

      log.debug(JSON.stringify({ responseData: request.data }));
      try {
        const result = await jqRun(data.pick, JSON.stringify(request.data), { input: "string" });
        log.debug(JSON.stringify({ result }));
        return { status: request.status, message: result };
      } catch {
        return { status: 409, message: "`Pick` value provided could not be resolved on the returned response" };
      }
      // return { status: request.status, message: result };
    } catch (error: any) {
      log.debug(
        JSON.stringify({
          error: error.message,
        }),
      );

      if (axios.isAxiosError(error)) {
        // Handle Axios-specific errors
        if (error.response) {
          // Server responded with a status other than 2xx
          return { status: error.response.status, message: error.response.data };
        } else if (error.request) {
          // No response received
          return { status: 504, message: "No response received" };
        }
      } else {
        // Handle non-Axios errors
        return { status: 500, message: "Unexpected error" };
      }
    }
  }
}
