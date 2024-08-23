import env from "@/env";
import { log } from "@/logger";
import { xInstance } from "@/request/twitter";
import { type IRequestAdded, type JsonRpcResponse, RequestStatus, type RoochNetwork } from "@/types";
import { Args, RoochClient, Secp256k1Keypair, Transaction, getRoochNodeUrl } from "@roochnetwork/rooch-sdk";
import axios from "axios";
import prismaClient from "../../prisma";

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

export default class RoochIndexer {
  private keyPair: Secp256k1Keypair;
  private orchestrator: string;

  constructor(
    private privateKey: string,
    private chainId: RoochNetwork,
    private oracleAddress: string,
  ) {
    this.keyPair = Secp256k1Keypair.fromSecretKey(this.privateKey);
    this.orchestrator = `0x${this.keyPair.getSchnorrPublicKey()}`.toLowerCase();
    log.info(`Rooch Indexer initialized`);
    log.info(`Chain ID: ${this.chainId}`);
    log.info(`Oracle Address: ${this.oracleAddress}`);
    log.info(`Orchestrator Address: ${this.orchestrator}`);
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

      // log.info("Events fetched successfully", response.data);

      return response.data;
    } catch (error) {
      log.error("Error fetching events", error);
      return null;
    }
  }

  async sendFulfillment(data: IRequestAdded, result: string) {
    const client = new RoochClient({
      url: getRoochNodeUrl(this.chainId),
    });
    const session = await client.createSession({
      sessionArgs: {
        appName: "your app name",
        appUrl: "your app url",
        scopes: [`${this.oracleAddress}::oracles::fulfil_request`],
      },
      signer: this.keyPair,
    });

    const tx = new Transaction();
    tx.callFunction({
      target: `${this.oracleAddress}::oracles::fulfil_request`,
      args: [Args.objectId(data.request_id), Args.string(result)],
    });

    return await client.signAndExecuteTransaction({
      transaction: tx,
      signer: session,
    });
  }

  async processRequestAddedEvent(data: IRequestAdded) {
    const token = xInstance.getAccessToken();

    if (data.oracle.toLowerCase() !== this.orchestrator) {
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
      if (isValidJson(data.params.value.headers)) {
        const request = await axios({
          method: data.params.value.method,
          data: data.params.value.body,
          url: url,
          headers: {
            ...JSON.parse(data.params.value.headers),
            Authorization: `Bearer ${token}`,
          },
        });
        return { status: request.status, message: request.data };
      } else {
        const request = await axios({
          method: data.params.value.method,
          data: data.params.value.body,
          url: url,
          headers: {
            Authorization: `Bearer ${token}`,
          },
        });
        return { status: request.status, message: request.data };
      }
    } catch (error) {
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
      log.error(newRequestsEvents);
      //TODO: HANDLE ERROR
      return;
    }

    await Promise.all(
      newRequestsEvents.result.data.map(async (event) => {
        const data = await this.processRequestAddedEvent(event.decoded_event_data.value);
        if (data) {
          try {
            const temp = await this.sendFulfillment(event.decoded_event_data.value, JSON.stringify(data));
            await prismaClient.events.create({
              data: {
                eventHandleId: event.event_id.event_handle_id,
                eventSeq: +event.event_id.event_seq,
                eventData: event.event_data,
                eventType: event.event_type,
                eventIndex: event.event_index,
                decoded_event_data: JSON.stringify(event.decoded_event_data),
                retries: 0,
                status: RequestStatus.SUCCESS,
                response: JSON.stringify(data),
              },
            });
          } catch (err) {
            await prismaClient.events.create({
              data: {
                eventHandleId: event.event_id.event_handle_id,
                eventSeq: +event.event_id.event_seq,
                eventData: event.event_data,
                eventType: event.event_type,
                eventIndex: event.event_index,
                decoded_event_data: JSON.stringify(event.decoded_event_data),
                retries: 0,
                status: RequestStatus.FAILED,
                response: JSON.stringify(data),
              },
            });
          }
        }
      }),
    );
    // const newFulfilmentEvents = await this.fetchEvents("FulfilmentAdded");

    // Filter the events to if they're only relevant to this Oracle (Orchestrator)
    // Cache the events to local cache for retry in case of downtime.
    // A separate concurrency process will listen for new events from cache and perform the request -- marking each event as completed when the request is made.
  }
}
