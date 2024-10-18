import env from "@/env";
import { log } from "@/logger";
import type { AptosBlockMetadataTransaction, AptosTransactionData, ProcessedRequestAdded } from "@/types";
import { decodeNotifyValue } from "@/util";
import { Account, Aptos, AptosConfig, Ed25519PrivateKey, Network } from "@aptos-labs/ts-sdk";
import axios from "axios";
import { GraphQLClient, gql } from "graphql-request";
import prismaClient from "../../prisma";
import { Indexer } from "./base";

export default class AptosIndexer extends Indexer {
  private lastTxVersion: number;
  private account: Account;

  constructor(
    private privateKey: string,
    private chainId: Network,
    protected oracleAddress: string,
  ) {
    if (!privateKey || !/^0x[0-9a-fA-F]+$/.test(privateKey)) {
      throw new Error("Invalid private key format. It must be a non-empty hex string.");
    }
    const key = new Ed25519PrivateKey(privateKey);
    const account = Account.fromPrivateKey({ privateKey: key });
    super(oracleAddress, account.accountAddress.toString());
    this.account = account;
    this.lastTxVersion = 0;
    log.info(`Aptos Indexer initialized`);
    log.info(`Chain ID: ${this.getChainId()} \n\t\tOrchestrator Oracle Node Address: ${this.orchestrator}`);
  }

  getChainId(): string {
    return `APTOS-${this.chainId}`;
  }

  getRpcUrl(): string {
    return `https://aptos-${this.chainId === Network.TESTNET ? "testnet" : "mainnet"}.nodit.io`;
  }

  /**
   * Fetches a list of transactions based on the provided transaction IDs.
   *
   * This asynchronous function takes an array of transaction IDs, makes API calls
   * to retrieve the corresponding Aptos block metadata transactions, and returns
   * the collected data.
   *
   * @param {number[]} transactionIDs - An array of transaction IDs to fetch.
   * @returns {Promise<AptosBlockMetadataTransaction[]>} A promise that resolves to an array of Aptos block metadata transactions.
   */
  async fetchTransactionList(transactionIDs: number[]): Promise<AptosBlockMetadataTransaction[]> {
    // Could be optimized by using Promise.settled preventing a single failed request to fail the entire operation
    return await Promise.all(
      transactionIDs.map(async (transaction) => {
        const response: AptosBlockMetadataTransaction = (
          await axios.get(`${this.getRpcUrl()}/v1/transactions/by_version/${transaction}`, {
            headers: {
              "X-API-KEY": env.aptos.noditKey,
            },
          })
        ).data;
        return response;
      }),
    );
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
      const endpoint = `${this.getRpcUrl()}/${env.aptos.noditKey}/v1/graphql`;

      const document = gql`
          query Account_transactions ($version: bigint!,$address: String!) {
              account_transactions(
                  limit: 100
                  where: { transaction_version: { _gt: $version },
                  account_address:{
                      _eq: $address
                  }
                  }
              ) {
                  account_address
                  transaction_version
              }
          }
      `;

      let internalCursor = 0;
      if (Number(cursor) > this.lastTxVersion) {
        internalCursor = Number(cursor);
      } else {
        internalCursor = this.lastTxVersion;
      }

      const client = new GraphQLClient(endpoint);
      const gqlData: AptosTransactionData = await client.request({
        document,
        variables: {
          version: internalCursor,
          address: this.oracleAddress.toLowerCase(),
        },
      });

      if (gqlData.account_transactions.length === 0) {
        return [];
      }

      // Set in memory the last transaction version to prevent re-fetching the same events
      this.lastTxVersion = gqlData.account_transactions[gqlData.account_transactions.length - 1].transaction_version;

      const fetchedTransactionList = await this.fetchTransactionList(
        gqlData.account_transactions.map((elem) => elem.transaction_version),
      );

      const _temp = fetchedTransactionList
        .filter((elem) => elem.success)
        .map((elem, index) => {
          const matching_events = elem.events.filter(
            (_event) => _event.type === `${this.oracleAddress}::oracles::RequestAdded`,
          );

          if (matching_events.length === 0) {
            return null;
          } else {
            return {
              // TODO: Does not account for transactions that surface multiple request_data events
              ...matching_events[0],
              tx_hash: elem.hash,
              tx_version: gqlData.account_transactions[index].transaction_version,
            };
          }
        })
        .filter((elem) => elem != null);


      const data: any[] = _temp.map((elem) => ({
        ...elem.data,
        notify: decodeNotifyValue(elem.data.notify?.value?.vec?.at(0) ?? ""),
        fullData: {
          event_id: { event_handle_id: elem.tx_hash, event_seq: elem.tx_version },
          event_index: elem.sequence_number,
          event_data: elem.data,
          event_type: elem.type,
          decoded_event_data: "",
        },
      }));

      return data;
    } catch (error) {
      log.error("Error fetching events", error);
      return [];
    }
  }

  /**
   * Sends a fulfillment transaction to the Aptos Oracles Contract.
   *
   * @param {ProcessedRequestAdded} data - The request data that needs to be fulfilled.
   * @param {number} status - The status of the fulfillment.
   * @param {string} result - The result of the fulfillment.
   * @returns {Promise<any>} - The receipt of the transaction.
   */
  async sendFulfillment(data: ProcessedRequestAdded<any>, status: number, result: string) {
    // Set up the Aptos client
    const aptosConfig = new AptosConfig({ network: Network.TESTNET });
    const aptos = new Aptos(aptosConfig);
    const view_request = await aptos.view({
      payload: {
        function: `${this.oracleAddress}::oracles::get_response_status`,
        functionArguments: [data.request_id],
      },
    });
    if (view_request[0] !== 0) {
      log.debug({ message: `Request: ${data.request_id} as already been processed` });
      return null;
    }
    try {
      // Build the transaction payload
      const payload = await aptos.transaction.build.simple({
        sender: this.account.accountAddress,
        data: {
          function: `${this.oracleAddress}::oracles::fulfil_request`,
          functionArguments: [data.request_id, status, result],
        },
      });

      // Sign and submit the transaction
      const pendingTxn = await aptos.signAndSubmitTransaction({
        signer: this.account,
        transaction: payload,
      });

      // Wait for the transaction to be processed
      const executedTransaction = await aptos.waitForTransaction({ transactionHash: pendingTxn.hash });

      log.debug("Transaction executed:", executedTransaction.hash);
    } catch (error) {
      console.error("Error calling entry function:", error);
    }
  }

  async save(
    event: ProcessedRequestAdded<{
      event_id: {
        event_handle_id: string;
        event_seq: number;
      };
      event_index: number;
      event_data: {
        [key: string]: any;
      };
      event_type: string;
      decoded_event_data: string;
    }>,
    data: any,
    status: number,
  ) {
    const dbEventData = {
      eventHandleId: event.fullData.event_id.event_handle_id,
      eventSeq: +event.fullData.event_id.event_seq,
      eventData: JSON.stringify(event.fullData.event_data),
      eventType: event.fullData.event_type,
      eventIndex: event.fullData.event_index.toString(),
      decoded_event_data: JSON.stringify(event.fullData.decoded_event_data),
      retries: 0,
      response: JSON.stringify(data),
      chain: this.getChainId(),
      status,
    };
    log.debug({ eventHandleId: event.fullData.event_id.event_handle_id, eventSeq: +event.fullData.event_id.event_seq });
    await prismaClient.events.create({
      data: {
        ...dbEventData,
      },
    });
  }
}
