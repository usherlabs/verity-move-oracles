import { log } from "@/logger";
import type { IRequestAdded } from "@/types";
import { run as jqRun } from "node-jq";

import { xInstance } from "@/request/twitter";
import axios, { type AxiosResponse } from "axios";

// TODO: We'll eventually need to framework our this orchestrator and indexer to allow Oracle Operators to create their own connections to various hosts.
const ALLOWED_HOST = ["x.com", "api.x.com", "twitter.com", "api.twitter.com"];

function isValidJson(jsonString: string): boolean {
  if (jsonString.trim().length === 0) {
    return true;
  }
  try {
    JSON.parse(jsonString);
    return true;
  } catch {
    return false;
  }
}

// Abstract base class
export abstract class Indexer {
  constructor(private oracleAddress: string) {
    log.info(`Oracle Contract Address: ${this.oracleAddress}`);
  }

  // Abstract: Implementation To fetch Data
  abstract fetchData(): IRequestAdded[];

  // Abstract:Implementation To fetch Orchestrator Address
  abstract getOrchestrator(): string;

  // Abstract: Implementation to send Fulfillment  blockchain fulfillment Request
  abstract sendFulfillment(data: IRequestAdded, status: number, result: string): void;

  // Abstract: Implementation to get chain identifier. its usually a concat between blockchain and network e.g ("ROOCH-testnet","APTOS-mainnet")
  abstract getChainId(): string;

  // Abstract: Runs indexer
  // TODO: implement run in base
  abstract run(): void;

  async processRequestAddedEvent(data: IRequestAdded) {
    log.debug("processing request:", data.request_id);
    const token = xInstance.getAccessToken();

    if (data.oracle.toLowerCase() !== this.getOrchestrator().toLowerCase()) {
      return null;
    }
    const url = data.params.value.url?.includes("http") ? data.params.value.url : `https://${data.params.value.url}`;
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
      if (isValidJson(data.params.value.headers)) {
        // TODO: Replace direct requests via axios with requests via VerityClient TS module
        request = await axios({
          method: data.params.value.method,
          data: data.params.value.body,
          url: url,
          headers: {
            ...JSON.parse(data.params.value.headers),
            Authorization: `Bearer ${token}`,
          },
        });
        // return { status: request.status, message: request.data };
      } else {
        request = await axios({
          method: data.params.value.method,
          data: data.params.value.body,
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
