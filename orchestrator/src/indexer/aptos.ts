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

    console.log({ newRequestsEvents });

    // TODO: Add Transaction write to DB and send transaction
  }
}
