import { CronJob } from "cron";
import "dotenv/config";
import env from "./env";
import AptosIndexer from "./indexer/aptos";
import RoochIndexer from "./indexer/rooch";
import { log } from "./logger";

(async () => {
  // Check env variables to determine which chains to subscribe to for events.
  // Start cron job to check for new events from Rooch Oracles

  if (env.rooch.privateKey && env.rooch.chainId.length > 0 && env.rooch.oracleAddress && env.chains.includes("ROOCH")) {
    // https://www.npmjs.com/package/cron#cronjob-class

    env.rooch.chainId.map((chain) => {
      const rooch = new RoochIndexer(env.rooch.privateKey, chain, env.rooch.oracleAddress);
      const job = new CronJob(
        env.rooch.indexerCron,
        async () => {
          if (job.running) {
            return;
          }

          job.running = true;
          await rooch.run();
          job.running = false;
        },
        null,
        true,
        "UTC",
      );
    });
  } else {
    log.info(`Skipping Rooch Indexer initialization...`);
  }

  if (env.aptos.privateKey && env.aptos.chainId && env.aptos.oracleAddress && env.chains.includes("APTOS")) {
    const aptosIndexer = new AptosIndexer(env.aptos.privateKey, env.aptos.chainId, env.aptos.oracleAddress);
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
