import env from "@/env";
import { log } from "@/logger";
import { fetchTwitterData } from "@/services/twitter";
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
    log.info(
      `Chain ID: ${this.getChainId()} \n\t\tOracle Address: ${this.oracleAddress}\n\t\tAccount Address: ${account.accountAddress.toString()}`,
    );
  }

  getChainId(): string {
    return `APTOS-${this.chainId}`;
  }

  /**
   * Returns the RPC URL for the Aptos network.
   * Using official Aptos Labs endpoint for better reliability.
   */
  getRpcUrl(): string {
    return `https://fullnode.testnet.aptoslabs.com/v1`;
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
          await axios.get(`${this.getRpcUrl()}/transactions/by_version/${transaction}`)
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
      const client = new GraphQLClient("https://indexer-testnet.staging.gcp.aptosdev.com/v1/graphql", {
        headers: {
          "Content-Type": "application/json",
        },
      });

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

      const gqlData: AptosTransactionData = await client.request(document, {
        version: internalCursor,
        address: this.oracleAddress.toLowerCase(),
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
    } catch (error: any) {
      log.error("Error fetching events", { error: error?.message });
      return [];
    }
  }

  async isPreviouslyExecuted(data: ProcessedRequestAdded<any>) {
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
      return true;
    }
    return false;
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
    try {
      const client = new Aptos(
        new AptosConfig({
          network: this.chainId,
        }),
      );

      try {
        const accountInfo = await client.account.getAccountInfo({ accountAddress: this.account.accountAddress });
        log.debug(`Account verified: ${this.account.accountAddress.toString()}`);
      } catch (e) {
        log.error(`Account not found or not funded: ${this.account.accountAddress.toString()}`);
        throw new Error(
          `Account not initialized on chain. Please fund account: ${this.account.accountAddress.toString()}`,
        );
      }

      try {
        const transaction = await client.transaction.build.simple({
          sender: this.account.accountAddress,
          data: {
            function: `${this.oracleAddress}::oracles::fulfil_request` as const,
            typeArguments: [],
            functionArguments: [data.request_id, status, result],
          },
        });

        const signedTx = await client.signAndSubmitTransaction({
          signer: this.account,
          transaction,
        });

        const txResult = await client.waitForTransaction({
          transactionHash: signedTx.hash,
        });

        log.info(`Fulfillment transaction successful: ${signedTx.hash}`);
        return txResult;
      } catch (e) {
        log.error("Transaction failed:", e);
        throw e;
      }
    } catch (error) {
      log.error("Error in sendFulfillment:", error);
      throw error;
    }
  }

  async processRequestAddedEvent(event: ProcessedRequestAdded<any>) {
    try {
      if (event.params.url.includes("api.x.com")) {
        console.log("Using Twitter API with token:", env.integrations.xBearerToken);
        return await fetchTwitterData(event.params.url);
      } else {
        throw new Error(`Unsupported API endpoint: ${event.params.url}`);
      }
    } catch (error: any) {
      log.error("Error in processRequestAddedEvent:", error);
      return {
        status: 500,
        message: error instanceof Error ? error.message : String(error),
      };
    }
  }

  async processRequest(data: ProcessedRequestAdded<any>) {
    try {
      if (data.params.url.includes("api.x.com")) {
        log.info("Processing Twitter API request");
        const response = await fetchTwitterData(data.params.url);

        if (!response) {
          throw new Error("No response from Twitter API");
        }

        log.debug("Twitter API Response:", { status: response.status });
        await this.sendFulfillment(data, response.status, response.message);
      } else {
        throw new Error(`Unsupported API endpoint: ${data.params.url}`);
      }
    } catch (error) {
      log.error("Error processing request:", error);
      await this.save(
        data,
        {
          error: error instanceof Error ? error.message : String(error),
        },
        500,
      );
      throw error;
    }
  }

  async save(event: ProcessedRequestAdded<any>, data: any, status: number) {
    try {
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

      log.debug("Attempting to save event to database:", dbEventData);

      const savedEvent = await prismaClient.events.create({
        data: dbEventData,
      });

      log.info("Successfully saved event to database:", {
        eventId: savedEvent.id,
        status: savedEvent.status,
      });

      return savedEvent;
    } catch (error) {
      log.error("Failed to save event to database:", {
        error: error instanceof Error ? error.message : String(error),
        eventData: event,
        status,
      });
      throw error;
    }
  }
}
