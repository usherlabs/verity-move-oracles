import { log } from "@/logger";
import { type ProcessedRequestAdded, RequestStatus } from "@/types";

import { instance as openAIInstance } from "@/integrations/openAI";
import { instance as xTwitterInstance } from "@/integrations/xtwitter";

import type { BasicBearerAPIHandler } from "@/integrations/base";
import prismaClient from "../../prisma";

type ChainEventData = {
  id?: { txDigest: string };
  event_id?: { event_handle_id: string };
};

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

  abstract isPreviouslyExecuted<T>(data: ProcessedRequestAdded<T>): Promise<boolean>;

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
    log.debug(`processing request: ${data.request_id}`);

    const eventOracle = data.oracle.toLowerCase();
    const oracleAddress = this.getOracleAddress().toLowerCase();

    if (eventOracle !== oracleAddress) {
      log.debug(`skipping request as it's not for this Oracle: ${data.request_id} ${eventOracle} ${oracleAddress}`);
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
    } catch (error: any) {
      return { status: 406, message: "Invalid URL" };
    }
  }

  async run() {
    const latestSuccessfulEvent = await prismaClient.events.findFirst({
      where: {
        chain: this.getChainId(),
        status: RequestStatus.SUCCESS,
      },
      orderBy: {
        eventSeq: "desc",
      },
    });

    const cursor = latestSuccessfulEvent?.eventHandleId || null;
    const newRequestsEvents = await this.fetchRequestAddedEvents(cursor);

    for (const event of newRequestsEvents) {
      try {
        // First check if request is already executed on-chain
        if (await this.isPreviouslyExecuted(event)) {
          log.debug(`Skipping already executed request: ${event.request_id}`);
          continue;
        }

        // Then check our database for any previous processing attempts
        const existingEvent = await prismaClient.events.findFirst({
          where: {
            AND: [
              { chain: this.getChainId() },
              {
                OR: [
                  { eventHandleId: event.request_id },
                  { eventHandleId: (event.fullData as ChainEventData)?.id?.txDigest },
                ],
              },
            ],
          },
        });

        if (existingEvent) {
          log.debug(`Skipping previously processed event: ${event.request_id}`);
          continue;
        }

        const data = await this.processRequestAddedEvent(event);
        if (data && data.status === 200) {
          await this.sendFulfillment(event, data.status, JSON.stringify(data.message));
          await this.save(event, data, RequestStatus.SUCCESS);
        }
        // Don't save failed events at all
      } catch (error: any) {
        log.error(`Error processing event ${event.request_id}:`, {
          error: error instanceof Error ? error.message : String(error),
        });
        // Don't save error events
      }
    }
  }
}
