import { log } from "@/logger";
import type { AptosBlockMetadataTransaction, AptosTransactionData, ProcessedRequestAdded } from "@/types";
import { decodeNotifyValue } from "@/util";
import { Network } from "@aptos-labs/ts-sdk";
import axios from "axios";
import { GraphQLClient, gql } from "graphql-request";
import prismaClient from "../../prisma";

// TODO: Complete Function for to inherit Base Indexer
export default class AptosIndexer {
  constructor(
    private privateKey: string,
    private chainId: Network,
    private oracleAddress: string,
  ) {
    log.info(`Aptos Indexer initialized`);
    log.info(`Chain ID: ${this.chainId}`);
    log.info(`Oracle Contract Address: ${this.oracleAddress}`);
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
        fullData: { hash: elem.data.hash, event_id: elem.guid },
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
  }

  async run() {
    log.info("Aptos indexer running...", Date.now());

    const latestCommit = await prismaClient.events.findFirst({
      where: {
        // @ts-ignore
        chain: this.getChainId(),
      },
      orderBy: {
        eventSeq: "desc",
        // indexedAt: "desc", // Order by date in descending order
      },
    });

    // Fetch the latest events from the Aptos Oracles Contract
    const newRequestsEvents = await this.fetchRequestAddedEvents(latestCommit?.eventSeq ?? null);

    console.log({ newRequestsEvents });

    // TODO: Add Transaction write to DB and send transaction
  }
}
