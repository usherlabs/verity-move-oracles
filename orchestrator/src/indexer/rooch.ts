import env from "@/env";
import { log } from "@/logger";
import { type IRequestAdded, type JsonRpcResponse, RequestStatus, type RoochNetwork } from "@/types";
import { getRoochNodeUrl } from "@roochnetwork/rooch-sdk";
import axios from "axios";
import prismaClient from "../../prisma";

export default class RoochIndexer {
  constructor(
    private privateKey: string,
    private chainId: RoochNetwork,
    private oracleAddress: string,
  ) {
    log.info(`Rooch Indexer initialized`);
    log.info(`Chain ID: ${this.chainId}`);
    log.info(`Oracle Address: ${this.oracleAddress}`);
  }

  async fetchEvents<T>(
    eventName: "RequestAdded" | "FulfilmentAdded",
    last_processed: null | number = null,
  ): Promise<JsonRpcResponse<T> | null> {
    try {
      const response = await axios.post(
        getRoochNodeUrl(this.chainId),
        {
          id: 101,
          jsonrpc: "2.0",
          method: "rooch_getEventsByEventHandle",
          params: [
            `${this.oracleAddress}::oracles::${eventName}`,
            last_processed,
            `${env.batchSize}`,
            false,
            { decode: true },
          ],
        },
        {
          headers: {
            "Content-Type": "application/json",
          },
        },
      );

      log.info("Events fetched successfully", response.data);

      return response.data;
    } catch (error) {
      log.error("Error fetching events", error);
      return null;
    }
  }

  async run() {
    log.info("Rooch indexer running...", Date.now());

    const latestCommit = await prismaClient.events.findFirst({
      orderBy: {
        eventSeq: "desc",
        // indexedAt: "desc", // Order by date in descending order
      },
    });

    // Fetch the latest events from the Rooch Oracles Contract
    const newRequestsEvents = await this.fetchEvents<IRequestAdded>("RequestAdded", latestCommit?.eventSeq ?? null);

    if (!newRequestsEvents || "data" in newRequestsEvents) {
      //TODO: HANDLE ERROR
      return;
    }

    await prismaClient.events.createMany({
      data: newRequestsEvents?.result.data.map((request) => ({
        eventHandleId: request.event_id.event_handle_id,
        eventSeq: +request.event_id.event_seq,
        eventData: request.event_data,
        eventType: request.event_type,
        eventIndex: request.event_index,
        decoded_event_data: JSON.stringify(request.decoded_event_data),
        retries: 0,
        status: RequestStatus.INDEXED,
      })),
    });

    // const newFulfilmentEvents = await this.fetchEvents("FulfilmentAdded");

    // Filter the events to if they're only relevant to this Oracle (Orchestrator)
    // Cache the events to local cache for retry in case of downtime.
    // A separate concurrency process will listen for new events from cache and perform the request -- marking each event as completed when the request is made.
  }
}
