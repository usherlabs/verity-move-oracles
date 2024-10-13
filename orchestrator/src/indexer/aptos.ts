import { log } from "@/logger";
import type { AptosBlockMetadataTransaction, AptosTransactionData, ProcessedRequestAdded } from "@/types";
import { RequestStatus } from "@/types";
import { decodeNotifyValue } from "@/util";
import { Account, Network, Secp256k1PrivateKey } from "@aptos-labs/ts-sdk";
import axios from "axios";
import { GraphQLClient, gql } from "graphql-request";
import prismaClient from "../../prisma";
import { Indexer } from "./base";

// TODO: Complete Function for to inherit Base Indexer
export default class AptosIndexer extends Indexer {
  private keyPair: Secp256k1PrivateKey;
  private account: Account;

  constructor(
    private privateKey: string,
    private chainId: Network,
    protected oracleAddress: string,
  ) {
    super(oracleAddress, new Secp256k1PrivateKey(privateKey).publicKey().toString());
    this.keyPair = new Secp256k1PrivateKey(privateKey);
    this.account = Account.fromPrivateKey({ privateKey: this.keyPair });
    log.info(`Aptos Indexer initialized`);
    log.info(`Chain ID: ${this.chainId}`);
  }

  getChainId(): string {
    return `APTOS-${this.chainId}`;
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
    return await Promise.all(
      transactionIDs.map(async (transaction) => {
        const response: AptosBlockMetadataTransaction = (
          await axios.get(`https://aptos-testnet.nodit.io/v1/transactions/by_version/${transaction}`, {
            headers: {
              "X-API-KEY": process.env.APTOS_RPC_KEY,
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
      const endpoint = `https://aptos-${this.chainId === Network.TESTNET ? "testnet" : "mainnet"}.nodit.io/${process.env.APTOS_RPC_KEY}/v1/graphql`;

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

      const client = new GraphQLClient(endpoint);
      const gqlData: AptosTransactionData = await client.request({
        document,
        variables: {
          version: cursor ?? 0,
          address: this.oracleAddress.toLowerCase(),
        },
      });

      if (gqlData.account_transactions.length === 0) {
        return [];
      }

      const fetchedTransactionList = await this.fetchTransactionList(
        gqlData.account_transactions.map((elem) => elem.transaction_version),
      );

      const _temp = fetchedTransactionList
        .filter((elem) => elem.success)
        .map((elem) => {
          const matching_events = elem.events.filter(
            (_event) => _event.type === `${this.oracleAddress}::oracles::RequestAdded`,
          );

          if (matching_events.length === 0) {
            return null;
          } else {
            return { ...matching_events[0], hash: elem.hash };
          }
        })
        .filter((elem) => elem != null);

      const data: any[] = _temp.map((elem) => ({
        ...elem.data,
        notify: decodeNotifyValue(elem.data.notify?.value?.vec?.at(0) ?? ""),
        fullData: {
          hash: elem.data.hash,
          event_id: { event_handle_id: elem.guid.account_address, event_seq: elem.guid.creation_number },
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
    //TODO:
    log.debug("Send fulfillment", { data, status, result });
  }

  async run() {
    log.info("Aptos indexer running...", Date.now());

    const latestCommit = await prismaClient.events.findFirst({
      where: {
        chain: this.getChainId(),
      },
      orderBy: {
        eventSeq: "desc",
        // indexedAt: "desc", // Order by date in descending order
      },
    });

    // Fetch the latest events from the Aptos Oracles Contract
    const newRequestsEvents = await this.fetchRequestAddedEvents(latestCommit?.eventSeq ?? null);

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
