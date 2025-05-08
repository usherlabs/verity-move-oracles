import env from "@/env";
import { xTwitterInstance } from "@/integrations/xtwitter";
import { log } from "@/logger";
import type { IEvent, IRequestAdded, JsonRpcResponse, ProcessedRequestAdded, RoochNetwork } from "@/types";
import { decodeNotifyValueFull } from "@/util";
import {
  Args,
  RoochClient,
  RoochWebSocketTransport,
  Secp256k1Keypair,
  Transaction,
  getRoochNodeUrl,
} from "@roochnetwork/rooch-sdk";
import axios from "axios";
import prismaClient from "../../prisma";
import { Indexer } from "./base";

export default class RoochIndexer extends Indexer {
  private keyPair: Secp256k1Keypair;
  private client: RoochClient;

  constructor(
    private privateKey: string,
    private chainId: RoochNetwork,
    protected oracleAddress: string,
  ) {
    super(oracleAddress, Secp256k1Keypair.fromSecretKey(privateKey).getRoochAddress().toHexAddress());
    this.keyPair = Secp256k1Keypair.fromSecretKey(this.privateKey);
    const wsTransport = new RoochWebSocketTransport({
      url: getRoochNodeUrl(this.chainId),
      reconnectDelay: 1000, // Delay between reconnection attempts (default: 1000ms)
      maxReconnectAttempts: 5, // Maximum number of reconnection attempts (default: 5)
      requestTimeout: 30000, // Request timeout (default: 30000ms)
      connectionReadyTimeout: 5000, // Connection ready timeout (default: 5000ms)
    });

    // Create client with WebSocket transport
    this.client = new RoochClient({
      transport: wsTransport,
    });
    log.info(`Rooch Indexer initialized`);
    log.info(`Chain ID: ${this.getChainId()} \n\t\tOrchestrator Oracle Node Address: ${this.orchestrator}`);
  }

  getChainId(): string {
    return `ROOCH-${this.chainId}`;
  }

  /**
   * Sends unfulfilled Requests by querying for Request objects and processing them.
   * This method iterates through paginated results, identifies unfulfilled requests,
   * and sends fulfillment responses for each.
   *
   * @returns {Promise<any[]>} An array of fulfilled request data.
   */
  async sendUnfulfilledRequests() {
    // Initialize the Rooch client with the current node URL
    // const _client = new RoochClient({ url: this.getRoochNodeUrl() });

    // Initialize cursor object for pagination
    const cursor = {
      isNextPage: true,
      data: {
        tx_order: "",
        state_index: "",
      },
    };

    // Array to store skipped requests (those with response_status === 0)
    let skippedRequests = [];

    // Continue fetching pages until there are no more items
    while (cursor.isNextPage) {
      try {
        // Query for object states with pagination
        const query = await this.client.queryObjectStates({
          filter: {
            object_type: `${this.oracleAddress}::oracles::Request`,
          },
          limit: "100",
          cursor: cursor.data.state_index.length === 0 ? null : cursor.data,
          queryOption: {
            decode: true,
          },
        });

        if (query.data.length === 0) {
          break; // No more items, exit the loop
        }

        // Extract and filter skipped requests (those with response_status === 0)
        const _skippedRequests = query.data
          .map((elem) => {
            return {
              ...elem.decoded_value?.value,
              request_id: elem.id,
              fullData: "",
            } as any;
          })
          .filter((elem) => elem.response_status === 0);

        // Combine new skipped requests with existing ones
        skippedRequests = _skippedRequests.concat(_skippedRequests);

        // Update cursor for next page
        cursor.data = query.next_cursor ?? {
          tx_order: "",
          state_index: "",
        };

        // Check if there's more data to fetch
        cursor.isNextPage = query.has_next_page;
      } catch (error) {
        log.error({ error });
        break; // Exit the loop on any error
      }
    }

    // // Process all skipped requests concurrently
    // await Promise.all(
    //   skippedRequests.map(async (event) => {
    //     const data = await this.processRequestAddedEvent(event);
    //     if (data) {
    //       try {
    //         // Send fulfillment response
    //         const response = await this.sendFulfillment(event, data.status, JSON.stringify(data.message));
    //         log.debug({ response }); // Log the response
    //       } catch (err) {
    //         log.error({ err }); // Log any errors during fulfillment
    //       }
    //     }
    //   }),
    // );

    for (let i = 0; i < skippedRequests.length; i++) {
      try {
        await new Promise((resolve) => setTimeout(resolve, xTwitterInstance.getRequestRate));
        const event = skippedRequests[i];
        const data = await this.processRequestAddedEvent(event);
        if (data) {
          try {
            // Send fulfillment response
            const response = await this.sendFulfillment(event, data.status, JSON.stringify(data.message));
            log.debug({ response }); // Log the response
          } catch (err) {
            log.error({ err }); // Log any errors during fulfillment
          }
        }
      } catch (err) {
        log.error({ err }); // Log any errors during fulfillment
      }
    }

    return skippedRequests; // Return the list of processed requests
  }

  getRoochNodeUrl() {
    return getRoochNodeUrl(this.chainId);
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
        this.getRoochNodeUrl(),
        {
          id: 101,
          jsonrpc: "2.0",
          method: "rooch_getEventsByEventHandle",
          params: [
            `${this.oracleAddress}::oracles::RequestAdded`,
            cursor === 0 ? null : cursor,

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

      const newRequestsEvents: JsonRpcResponse<IRequestAdded> = response.data;

      if (!newRequestsEvents) {
        // Events no relevant for this Oracle Node.
        return [];
      }

      if (!newRequestsEvents.result?.data) {
        log.debug("No new events found", newRequestsEvents, {
          id: 101,
          jsonrpc: "2.0",
          method: "rooch_getEventsByEventHandle",
          params: [`${this.oracleAddress}::oracles::RequestAdded`, cursor, `${env.batchSize}`, false, { decode: true }],
        });
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
          notify: decodeNotifyValueFull(values.notify?.value?.vec?.value?.at(0).at(0) ?? ""),
        };
        return data;
      });
    } catch (error: any) {
      log.error("Error fetching events", { error: error?.message });
      return [];
    }
  }

  async isPreviouslyExecuted(data: ProcessedRequestAdded<any>) {
    const view = await this.client.executeViewFunction({
      target: `${this.oracleAddress}::oracles::get_response_status`,
      args: [Args.objectId(data.request_id)],
    });

    if (view.vm_status === "Executed" && view.return_values && view.return_values[0].decoded_value !== 0) {
      log.debug({ message: `isPreviouslyExecuted Request: ${data.request_id} as already been processed` });
      return true;
    }
    return false;
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
    const view = await this.client.executeViewFunction({
      target: `${this.oracleAddress}::oracles::get_response_status`,
      args: [Args.objectId(data.request_id)],
    });

    if (view.vm_status === "Executed" && view.return_values && view.return_values[0].decoded_value !== 0) {
      log.debug({ message: `sendFulfillment Request: ${data.request_id} as already been processed` });
      return null;
    }

    const keeper_key = await prismaClient.keeper.upsert({
      where: {
        chain_module: {
          module: data.notify ?? "",
          chain: this.chainId,
        },
      },
      create: {
        module: data.notify ?? "",
        chain: this.chainId,
        privateKey: Secp256k1Keypair.generate().getSecretKey(),
      },
      update: {},
    });

    const tx = new Transaction();
    tx.callFunction({
      target: `${this.oracleAddress}::oracles::fulfil_request`,
      args: [
        Args.objectId(data.request_id),
        Args.u16(status),
        Args.string(result),
        Args.address(Secp256k1Keypair.fromSecretKey(keeper_key.privateKey).getRoochAddress().toHexAddress()),
      ],
    });

    tx.setMaxGas(1000000000);

    const receipt = await this.client.signAndExecuteTransaction({
      transaction: tx,
      signer: this.keyPair,
    });

    const notify_module = data.notify?.split("::") ?? [];

    log.info({
      address: Secp256k1Keypair.fromSecretKey(keeper_key.privateKey).getRoochAddress().toHexAddress(),
      target: data.notify ?? "",
      oracleAddress: this.oracleAddress,
      receipt: receipt.execution_info,
      notify_module: data.notify?.split("::"),
    });
    try {
      if ((data.notify?.length ?? 0) > 66) {
        const module_abi = await this.client.getModuleAbi({
          moduleAddr: notify_module[0] ?? "",
          moduleName: notify_module[1] ?? "",
        });
        const function_abi = module_abi.functions.find(
          (func) => func.name === notify_module[2] && !func.params.includes("&signer"),
        );
        if (function_abi) {
          const tx = new Transaction();
          tx.callFunction({
            target: data.notify ?? "",
            args: function_abi?.params?.length === 0 ? [] : [Args.objectId(data.request_id)],
          });
          tx.setMaxGas(2_0000_0000);
          const notification_receipt = await this.client.signAndExecuteTransaction({
            transaction: tx,
            signer: Secp256k1Keypair.fromSecretKey(keeper_key.privateKey),
          });
          log.info({ notification_receipt });
        }
      }
    } catch (err) {
      log.error({
        request_id: data.request_id,
        notifier: Secp256k1Keypair.fromSecretKey(keeper_key.privateKey).getRoochAddress().toHexAddress(),
        err: err,
      });
    }
    return receipt;
  }

  async save(event: ProcessedRequestAdded<IEvent<IRequestAdded>>, data: any, status: number) {
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
      status,
    };

    await prismaClient.events.create({
      data: {
        ...dbEventData,
      },
    });
  }
}
