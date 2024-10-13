import env from "@/env";
import { log } from "@/logger";
import {
  type IEvent,
  type IRequestAdded,
  type JsonRpcResponse,
  type ProcessedRequestAdded,
  RequestStatus,
  type RoochNetwork,
} from "@/types";
import { decodeNotifyValue } from "@/util";
import { Args, RoochClient, Secp256k1Keypair, Transaction, getRoochNodeUrl } from "@roochnetwork/rooch-sdk";
import axios from "axios";
import prismaClient from "../../prisma";
import { Indexer } from "./base";

export default class RoochIndexer extends Indexer {
  private keyPair: Secp256k1Keypair;

  constructor(
    private privateKey: string,
    private chainId: RoochNetwork,
    protected oracleAddress: string,
  ) {
    super(oracleAddress, Secp256k1Keypair.fromSecretKey(privateKey).getRoochAddress().toHexAddress());
    this.keyPair = Secp256k1Keypair.fromSecretKey(this.privateKey);
    log.info(`Rooch Indexer initialized`);
    log.info(`Chain ID: ${this.chainId}`);
  }

  getChainId(): string {
    return `ROOCH-${this.chainId}`;
  }

  /**
   * Fetches a list of RequestAdded events based on the provided cursor.
   *
   * This asynchronous function retrieves RequestAdded events from an API endpoint,
   * using pagination to handle large datasets efficiently. It supports both
   * forward and backward pagination.
   *
   * @param {null | number | string} [cursor] - Optional cursor for pagination.
   *     Can be null (for initial fetch), a timestamp number, or a string ID.
   * @returns {Promise<ProcessedRequestAdded<any>[]>} A promise that resolves to
   *     an array of ProcessedRequestAdded objects, representing the fetched events.
   */
  async fetchRequestAddedEvents(cursor: null | number | string = null): Promise<ProcessedRequestAdded<any>[]> {
    try {
      const response = await axios.post(
        getRoochNodeUrl(this.chainId),
        {
          id: 101,
          jsonrpc: "2.0",
          method: "rooch_getEventsByEventHandle",
          params: [`${this.oracleAddress}::oracles::RequestAdded`, cursor, `${env.batchSize}`, false, { decode: true }],
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

      const newRequestsEvents: JsonRpcResponse<IRequestAdded> = response.data;

      if (!newRequestsEvents) {
        // Events no relevant for this Oracle Node.
        return [];
      }

      if (!newRequestsEvents.result?.data) {
        log.debug("No new events found", newRequestsEvents);
        return [];
      }

      return newRequestsEvents.result.data.map((_data) => {
        const values = _data.decoded_event_data.value;
        const data: ProcessedRequestAdded<IEvent<IRequestAdded>> = {
          params: values.params.value,
          fullData: _data,
          oracle: values.oracle,
          pick: values.pick,
          request_id: values.request_id,
          notify: decodeNotifyValue(values.notify?.value?.vec?.at(0) ?? ""),
        };
        return data;
      });
    } catch (error) {
      log.error("Error fetching events", error);
      return [];
    }
  }

  /**
   * Sends a fulfillment transaction to the Rooch Oracles Contract.
   *
   * @param {ProcessedRequestAdded} data - The request data that needs to be fulfilled.
   * @param {number} status - The status of the fulfillment.
   * @param {string} result - The result of the fulfillment.
   * @returns {Promise<any>} - The receipt of the transaction.
   */
  async sendFulfillment(data: ProcessedRequestAdded<any>, status: number, result: string) {
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

    try {
      if ((data.notify?.length ?? 0) > 66) {
        const tx = new Transaction();
        tx.callFunction({
          target: data.notify ?? "",
        });

        const receipt = await client.signAndExecuteTransaction({
          transaction: tx,
          signer: this.keyPair,
        });

        log.debug(JSON.stringify(receipt));
      }
    } catch (err) {
      log.error(err);
    }
    return receipt;
  }

  async run() {
    log.info("Rooch indexer running...", Date.now());

    const latestCommit = await prismaClient.events.findFirst({
      where: {
        chain: this.getChainId(),
      },
      orderBy: {
        eventSeq: "desc",
        // indexedAt: "desc", // Order by date in descending order
      },
    });

    // Fetch the latest events from the Rooch Oracles Contract
    const newRequestsEvents: ProcessedRequestAdded<IEvent<IRequestAdded>>[] = await this.fetchRequestAddedEvents(
      latestCommit?.eventSeq ?? null,
    );

    await Promise.all(
      newRequestsEvents.map(async (event) => {
        const data = await this.processRequestAddedEvent(event);
        if (data) {
          const dbEventData = {
            eventHandleId: event.fullData.event_id.event_handle_id,
            eventSeq: +event.fullData.event_id.event_seq,
            eventData: event.fullData.event_data,
            eventType: event.fullData.event_type,
            eventIndex: event.fullData.event_index,
            decoded_event_data: JSON.stringify(event.fullData.decoded_event_data),
            retries: 0,
            response: JSON.stringify(data),
            chain: this.getChainId(),
          };
          try {
            await this.sendFulfillment(event, data.status, JSON.stringify(data.message));
            // TODO: Use the notify parameter to send transaction to the contract and function to marked in the request event
            await prismaClient.events.create({
              data: {
                ...dbEventData,
                status: RequestStatus.SUCCESS,
              },
            });
          } catch (err) {
            log.error({ err });
            await prismaClient.events.create({
              data: {
                ...dbEventData,
                status: RequestStatus.FAILED,
              },
            });
          }
        }
      }),
    );
  }
}
