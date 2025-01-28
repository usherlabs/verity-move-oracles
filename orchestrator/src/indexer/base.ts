import { log } from "@/logger";
import { type ProcessedRequestAdded, RequestStatus } from "@/types";

import { instance as openAIInstance } from "@/integrations/openAI";
import { instance as xTwitterInstance } from "@/integrations/xtwitter";

import type { BasicBearerAPIHandler } from "@/integrations/base";
import prismaClient from "../../prisma";

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

  requestHandlerSelector(url: URL): BasicBearerAPIHandler | null {
    if (xTwitterInstance.isApprovedPath(url)) {
      return xTwitterInstance;
    }
    if (openAIInstance.isApprovedPath(url)) {
      return openAIInstance;
    }
    return null;
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
  async processRequestAddedEvent<T>(
    data: ProcessedRequestAdded<T>,
  ): Promise<{ status: number; message: string } | null> {
    log.debug("processing request:", data.request_id);

    if (data.oracle.toLowerCase() !== this.getOrchestratorAddress().toLowerCase()) {
      log.debug(
        "skipping request as it's not for this Oracle:",
        data.request_id,
        this.getOrchestratorAddress().toLowerCase(),
        data.oracle.toLowerCase(),
      );
      return null;
    }
    try {
      const url = data.params.url?.includes("http") ? data.params.url : `https://${data.params.url}`;
      const url_object = new URL(url);

      const handler = this.requestHandlerSelector(url_object);
      if (handler) {
        return handler.submitRequest(data);
      }
      return { status: 406, message: "URL Not supported" };
    } catch {
      return { status: 406, message: "Invalid URL" };
    }
  }

  async run() {
    log.info(`${this.getChainId()} indexer running...`, Date.now());

    const latestCommit = await prismaClient.events.findFirst({
      where: {
        chain: this.getChainId(),
        oracleAddress: this.oracleAddress,
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
        const event = newRequestsEvents[i];
        const data = await this.processRequestAddedEvent(event);

        log.info({ data });

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
