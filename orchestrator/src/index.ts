import { CronJob } from "cron";
import "dotenv/config";

import env from "./env";
import RoochIndexer from "./indexer/rooch";
import { xInstance } from "./request/twitter";
// import { log } from "./logger";

(async () => {
  // Check env variables to determine which chains to subscribe to for events.
  // Start cron job to check for new events from Rooch Oracles
  await xInstance.requestAccessToken();

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
})();
