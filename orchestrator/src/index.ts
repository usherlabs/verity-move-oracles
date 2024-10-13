import { CronJob } from "cron";
import "dotenv/config";

import { Network } from "@aptos-labs/ts-sdk";
import env from "./env";
import AptosIndexer from "./indexer/aptos";
import RoochIndexer from "./indexer/rooch";
import { instance as xInstance } from "./integrations/xtwitter";
import { log } from "./logger";

(async () => {
  // Check env variables to determine which chains to subscribe to for events.
  // Start cron job to check for new events from Rooch Oracles
  if (xInstance.isAvailable()) {
    await xInstance.requestAccessToken();
  }

  if (env.rooch.privateKey && env.rooch.chainId && env.rooch.oracleAddress) {
    // https://www.npmjs.com/package/cron#cronjob-class
    const rooch = new RoochIndexer(env.rooch.privateKey, env.rooch.chainId, env.rooch.oracleAddress);
    new CronJob(
      env.rooch.indexerCron,
      () => {
        rooch.run();
      },
      null,
      true,
    );
  } else {
    log.info(`Skipping Rooch Indexer initialization...`);
  }

  if (env.aptos.privateKey && env.aptos.chainId && env.aptos.oracleAddress) {
    const aptosIndexer = new AptosIndexer(env.rooch.privateKey, Network.TESTNET, env.aptos.oracleAddress);
    new CronJob(
      env.rooch.indexerCron,
      () => {
        aptosIndexer.run();
      },
      null,
      true,
    );
  } else {
    log.info(`Skipping Aptos Indexer initialization...`);
  }
})();
