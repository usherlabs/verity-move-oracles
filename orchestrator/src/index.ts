import { CronJob } from "cron";
import "dotenv/config";

import { Network } from "@aptos-labs/ts-sdk";
import env from "./env";
import AptosIndexer from "./indexer/aptos";
import RoochIndexer from "./indexer/rooch";
import { instance as xInstance } from "./integrations/xtwitter";
// import { log } from "./logger";

(async () => {
  // Check env variables to determine which chains to subscribe to for events.
  // Start cron job to check for new events from Rooch Oracles
  if (xInstance.isAvailable()) {
    await xInstance.requestAccessToken();
  }

  if (env.rooch.privateKey) {
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
  }
  // TODO: replace/clean up with a proper select condition
  else {
    const aptosIndexer = new AptosIndexer(
      env.rooch.privateKey,
      Network.TESTNET,
      "0xa2b7160c0dc70548e8105121b075df9ea3b98c0c82294207ca38cb1165b94f59",
    );
    new CronJob(
      env.rooch.indexerCron,
      () => {
        aptosIndexer.run();
      },
      null,
      true,
    );
  }
})();
