import { log } from "@/logger";
import type { RoochNetwork } from "@/types";
import { getRoochNodeUrl } from "@roochnetwork/rooch-sdk";
import axios from "axios";

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

  async fetchEvents(eventName: string) {
    try {
      const response = await axios.post(
        getRoochNodeUrl(this.chainId),
        {
          id: 101,
          jsonrpc: "2.0",
          method: "rooch_getEventsByEventHandle",
          params: [`${this.oracleAddress}::oracles::${eventName}`, null, "1000", false, { decode: true }],
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
    }

    return [];
  }

  async run() {
    log.info("Rooch indexer running...", Date.now());

    // Fetch the latest events from the Rooch Oracles Contract
    const newRequestsEvents = await this.fetchEvents("RequestAdded");
    // const newFulfilmentEvents = await this.fetchEvents("FulfilmentAdded");

    // Filter the events to if they're only relevant to this Oracle (Orchestrator)
    // Cache the events to local cache for retry in case of downtime.
    // A separate concurrency process will listen for new events from cache and perform the request -- marking each event as completed when the request is made.
  }
}
