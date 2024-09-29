import env from "@/env";
import { log } from "@/logger";
import { xInstance } from "@/request/twitter";
import { type IRequestAdded, type JsonRpcResponse, RequestStatus, type RoochNetwork } from "@/types";
import { Args, RoochClient, Secp256k1Keypair, Transaction, getRoochNodeUrl } from "@roochnetwork/rooch-sdk";
import axios, { type AxiosResponse } from "axios";
import { run } from "node-jq";
import prismaClient from "../../prisma";

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

function decodeNotifyValue(hex: string): string {
  return `${hex.slice(0, 66)}${Buffer.from(hex.slice(66), "hex").toString()}`;
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
    this.orchestrator = this.keyPair.getRoochAddress().toHexAddress();
    log.info(`Rooch Indexer initialized`);
    log.info(`Chain ID: ${this.chainId}`);
    log.info(`Oracle Contract Address: ${this.oracleAddress}`);
    log.info(`Orchestrator Oracle Node Address: ${this.orchestrator}`);
  }

  async fetchEvents<T>(
    eventName: "RequestAdded" | "Fulfilment",
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

      log.debug(
        response?.data?.result?.data?.length > 0
          ? `fetched ${response?.data?.result?.data?.length ?? 0} events successfully`
          : "No New Event",
      );

      return response.data;
    } catch (error) {
      log.error("Error fetching events", error);
      return null;
    }
  }

  /**
   * Sends a fulfillment transaction to the Rooch Oracles Contract.
   *
   * @param {IRequestAdded} data - The request data that needs to be fulfilled.
   * @param {number} status - The status of the fulfillment.
   * @param {string} result - The result of the fulfillment.
   * @returns {Promise<any>} - The receipt of the transaction.
   */
  async sendFulfillment(data: IRequestAdded, status: number, result: string) {
    const client = new RoochClient({
      url: getRoochNodeUrl(this.chainId),
    });
    log.debug({ notify: data.notify });

    const tx = new Transaction();
    tx.callFunction({
      target: `${this.oracleAddress}::oracles::fulfil_request`,
      args: [Args.objectId(data.request_id), Args.u8(status), Args.string(result)],
    });

    const receipt = await client.signAndExecuteTransaction({
      transaction: tx,
      signer: this.keyPair,
    });

    log.debug({ execution_info: receipt.execution_info });

    return receipt;
  }

  /**
   * Sends a notify transaction to the Rooch Oracles Contract.
   *
   * This function triggers an on-chain method with no parameters. It decodes the notify value from the provided data
   * and sends a transaction to the decoded target address.
   *
   * @param {IRequestAdded} data - The request data that contains the notify value.
   * @returns {Promise<any>} - The receipt of the transaction or null if the notify value is invalid.
   */
  async sendNotify(data: IRequestAdded) {
    const client = new RoochClient({
      url: getRoochNodeUrl(this.chainId),
    });

    if ((data.notify?.value?.vec?.at(0)?.length ?? 0) > 66) {
      const tx = new Transaction();
      tx.callFunction({
        target: decodeNotifyValue(data.notify?.value?.vec?.at(0) ?? ""),
      });

      const receipt = await client.signAndExecuteTransaction({
        transaction: tx,
        signer: this.keyPair,
      });

      log.debug({ execution_info: receipt.execution_info });

      return receipt;
    }

    return null;
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
  async processRequestAddedEvent(data: IRequestAdded) {
    log.debug("processing request:", data.request_id);
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

      log.debug({ responseData: request.data });
      try {
        const result = await run(data.pick, JSON.stringify(request.data), { input: "string" });
        log.debug({ result });
        return { status: request.status, message: result };
      } catch {
        return { status: 409, message: "`Pick` value provided could not be resolved on the returned response" };
      }
      // return { status: request.status, message: result };
    } catch (error: any) {
      log.debug({
        error: error.message,
      });

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

    if (!newRequestsEvents) {
      // Events no relevant for this Oracle Node.
      return;
    }

    if (!newRequestsEvents.result?.data) {
      log.debug("No new events found", newRequestsEvents);
      return;
    }

    await Promise.all(
      newRequestsEvents.result.data.map(async (event) => {
        const data = await this.processRequestAddedEvent(event.decoded_event_data.value);
        if (data) {
          try {
            await this.sendFulfillment(event.decoded_event_data.value, data.status, JSON.stringify(data.message));

            // Send the notify transaction to the contract consuming the oracle request/response data.
            // await this.sendNotify(event.decoded_event_data.value);
            // TODO: Commented the sendNotify function for now, as it's exposed to a bug where the on-chain notify function can consume all gas..

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
            log.error({ err });
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
