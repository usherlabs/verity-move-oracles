import { log } from "@/logger";
import { type ProcessedRequestAdded, RequestStatus } from "@/types";
import { run as jqRun } from "node-jq";

import { instance as xTwitterInstance } from "@/integrations/xtwitter";
import { isValidJson } from "@/util";
import axios, { type AxiosResponse } from "axios";
import prismaClient from "../../prisma";

const ALLOWED_HOST = [...xTwitterInstance.hosts];

// Abstract base class
export abstract class Indexer {
  constructor(
    protected oracleAddress: string,
    protected orchestrator: string,
  ) {
    log.info(`Oracle Contract Address: ${this.oracleAddress}`);
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

  getOrchestratorAddress(): string {
    return this.orchestrator.toLowerCase();
  }

  getOracleAddress(): string {
    return this.oracleAddress;
  }

  applyAuthorizationHeader(hostname: string): string | undefined {
    if (ALLOWED_HOST.includes(hostname)) {
      const token = xTwitterInstance.getAccessToken();
      return `Bearer ${token}`;
    }
    return undefined;
  }

  /**
   * Saves the event and additional metadata to the database.
   *
   * @param {ProcessedRequestAdded<any>} event - The event object containing the request details.
   * @param {any} data - Additional metadata to be saved along with the event.
   * @param {number} status - The status code of the operation.
   * @returns {Promise<void>} A promise that resolves when the saving is complete.
   */
  abstract save(event: ProcessedRequestAdded<any>, data: any, status: number): Promise<any>;

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
      log.debug(
        "skipping request as it's not for this Oracle:",
        data.request_id,
        this.getOrchestratorAddress().toLowerCase(),
        data.oracle.toLowerCase(),
      );
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

      try {
        const result = await jqRun(data.pick, JSON.stringify(request.data), { input: "string" });
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

  async run() {
    log.info(`${this.getChainId()} indexer running...`, Date.now());

    const latestCommit = await prismaClient.events.findFirst({
      where: {
        chain: this.getChainId(),
      },
      orderBy: {
        eventSeq: "desc",
        // indexedAt: "desc", // Order by date in descending order
      },
    });

    // Fetch the latest events from the Aptos Oracles Contract
    const newRequestsEvents = await this.fetchRequestAddedEvents(Number(latestCommit?.eventSeq ?? 0) ?? 0);
    for (let i = 0; i < newRequestsEvents.length; i++) {
      try {
        if (i > 0) await new Promise((resolve) => setTimeout(resolve, xTwitterInstance.getRequestRate));

        const event = newRequestsEvents[i];
        const data = await this.processRequestAddedEvent(event);

        if (data) {
          try {
            await this.sendFulfillment(event, data.status, JSON.stringify(data.message));
            await this.save(event, data, RequestStatus.SUCCESS);
          } catch (err: any) {
            log.error({ err: err.message });
            await this.save(event, data, RequestStatus.FAILED);
          }
        }
      } catch (error) {
        console.error(`Error processing event ${i}:`, error);
      }
    }

    // await Promise.all(
    //   newRequestsEvents.map(async (event) => {
    //     const data = await this.processRequestAddedEvent(event);
    //     if (data) {
    //       try {
    //         await this.sendFulfillment(event, data.status, JSON.stringify(data.message));
    //         // TODO: Use the notify parameter to send transaction to the contract and function to marked in the request event
    //         await this.save(event, data, RequestStatus.SUCCESS);
    //       } catch (err: any) {
    //         log.error({ err: err.message });
    //         await this.save(event, data, RequestStatus.FAILED);
    //       }
    //     }
    //   }),
    // );
  }
}
