import { getNetworkConfig } from "@/config/network";
import { log } from "@/logger";
import type { ProcessedRequestAdded, SuiNetwork, SuiRequestEvent } from "@/types";
import { SuiClient } from "@mysten/sui/client";
import { decodeSuiPrivateKey } from "@mysten/sui/cryptography";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction } from "@mysten/sui/transactions";
import prismaClient from "../../prisma";
import { Indexer } from "./base";

export default class SuiIndexer extends Indexer {
  private client: SuiClient;
  private keypair: Ed25519Keypair;

  constructor(
    protected oracleAddress: string,
    private network: SuiNetwork,
    privateKey: string,
  ) {
    if (!privateKey.startsWith("suiprivkey")) {
      throw new Error("Invalid private key format. Must be in Sui CLI format (suiprivkey...)");
    }

    // Use the SDK's built-in decoder
    const decoded = decodeSuiPrivateKey(privateKey);

    // Access the private key bytes
    const keyBytes = decoded.secretKey;

    log.debug("Key details:", {
      keyLength: keyBytes.length,
      hasKey: !!keyBytes,
    });

    const keypair = Ed25519Keypair.fromSecretKey(keyBytes);
    const derivedAddress = keypair.getPublicKey().toSuiAddress();

    if (derivedAddress.toLowerCase() !== oracleAddress.toLowerCase()) {
      throw new Error(`Derived address ${derivedAddress} does not match expected address ${oracleAddress}`);
    }

    super(oracleAddress, derivedAddress);

    this.keypair = keypair;
    const config = getNetworkConfig(network);
    this.client = new SuiClient({ url: config.url });

    log.info(`Sui Indexer (${network.toUpperCase()})`, {
      oracleAddress: this.oracleAddress,
      walletAddress: derivedAddress,
      match: true,
    });
  }

  getChainId(): string {
    return `SUI-${this.network.toUpperCase()}`;
  }

  async fetchRequestAddedEvents(cursor: null | number | string = null): Promise<ProcessedRequestAdded<any>[]> {
    try {
      const packageId = "0xc8bb9d3feb5315cf30099a2bfa66f5dbbb771876847434b3792a68be66b4ee4d";
      const eventTypes = [`${packageId}::oracles::RequestAdded`];

      // Sui-specific cursor handling
      const lastProcessedEvent = await prismaClient.events.findFirst({
        where: {
          chain: this.getChainId(),
        },
        orderBy: {
          eventSeq: "desc",
        },
      });

      // Format cursor properly for Sui
      const cursorObject = lastProcessedEvent
        ? {
            txDigest: lastProcessedEvent.eventHandleId,
            eventSeq: lastProcessedEvent.eventSeq.toString(),
          }
        : null;

      log.debug("Querying Sui events", {
        eventType: eventTypes[0],
        cursor: cursorObject ? `${cursorObject.txDigest}:${cursorObject.eventSeq}` : "none",
      });

      const events = await this.client.queryEvents({
        query: { MoveEventType: eventTypes[0] },
        cursor: cursorObject,
        limit: 50,
      });

      log.debug("Found Sui events", {
        count: events.data.length,
        hasMore: events.hasNextPage,
        firstEvent: events.data[0]?.id,
        lastEvent: events.data[events.data.length - 1]?.id,
      });

      return events.data.map((event) => {
        const parsedJson = event.parsedJson as SuiRequestEvent;
        return {
          params: parsedJson.params,
          fullData: event,
          oracle: parsedJson.oracle,
          pick: parsedJson.pick,
          request_id: parsedJson.request_id,
          notify: parsedJson.notify,
        };
      });
    } catch (error: any) {
      log.error("Sui event fetch failed", {
        error: error instanceof Error ? error.message : String(error),
        cursor: cursor,
      });
      return [];
    }
  }

  async isPreviouslyExecuted(data: ProcessedRequestAdded<any>): Promise<boolean> {
    try {
      const txb = new Transaction();
      txb.moveCall({
        target: `0xc8bb9d3feb5315cf30099a2bfa66f5dbbb771876847434b3792a68be66b4ee4d::oracles::get_response_status`,
        arguments: [txb.pure.string(data.request_id)],
      });

      const result = await this.client.devInspectTransactionBlock({
        sender: this.getOrchestratorAddress(),
        transactionBlock: txb,
      });

      if (!result.results?.[0]?.returnValues?.[0]) {
        return false;
      }

      const status = result.results[0].returnValues[0];
      log.debug("Response status check:", {
        requestId: data.request_id,
        status: status[0][0],
        isExecuted: status[0][0] !== 0,
      });

      return status[0][0] !== 0;
    } catch (error: any) {
      log.error("Error checking execution status:", {
        error: error instanceof Error ? error.message : String(error),
        requestId: data.request_id,
      });
      return false;
    }
  }

  async sendFulfillment(data: ProcessedRequestAdded<any>, status: number, result: string): Promise<void> {
    try {
      const address = this.keypair.getPublicKey().toSuiAddress();
      const packageId = "0xc8bb9d3feb5315cf30099a2bfa66f5dbbb771876847434b3792a68be66b4ee4d";

      const coins = await this.client.getCoins({
        owner: address,
        coinType: "0x2::sui::SUI",
      });

      if (!coins.data.length) {
        throw new Error(`No SUI coins found for address ${address}`);
      }

      const tx = new Transaction();
      const resultStr = typeof result === "string" ? result : JSON.stringify(result);

      tx.moveCall({
        arguments: [tx.pure.string(data.request_id), tx.pure.u64(status), tx.pure.string(resultStr)],
        target: `${packageId}::oracles::fulfil_request`,
      });

      // Explicitly set gas coin and budget
      tx.setGasPayment([
        {
          objectId: coins.data[0].coinObjectId,
          version: coins.data[0].version,
          digest: coins.data[0].digest,
        },
      ]);
      tx.setGasBudget(10000000);

      const response = await this.client.signAndExecuteTransaction({
        transaction: tx,
        signer: this.keypair,
        options: {
          showEffects: true,
          showEvents: true,
        },
      });

      log.info("Fulfillment transaction details:", {
        digest: response.digest,
        status: response.effects?.status,
        events: response.events,
        errors: response.effects?.status?.error,
      });
    } catch (error) {
      log.error("Error sending fulfillment:", error);
      throw error;
    }
  }

  async save(event: ProcessedRequestAdded<any>, data: any, status: number) {
    try {
      const dbEventData = {
        eventHandleId: event.fullData.id.txDigest,
        eventSeq: BigInt(event.fullData.timestampMs),
        eventData: JSON.stringify(event.fullData),
        eventType: `${this.oracleAddress}::oracles::RequestAdded`,
        eventIndex: event.fullData.id.eventSeq,
        decoded_event_data: JSON.stringify(event.fullData.parsedJson),
        retries: 0,
        response: JSON.stringify(data),
        chain: this.getChainId(),
        status,
      };

      log.debug("Saving event to database:", dbEventData);

      const savedEvent = await prismaClient.events.create({
        data: dbEventData,
      });

      log.info("Successfully saved event:", {
        eventId: savedEvent.id,
        status: savedEvent.status,
      });

      return savedEvent;
    } catch (error) {
      log.error("Failed to save event:", {
        error: error instanceof Error ? error.message : String(error),
        event,
        status,
      });
      throw error;
    }
  }
}
