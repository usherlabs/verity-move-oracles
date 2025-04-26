import { CronJob } from "cron";
import "dotenv/config";
import env from "./env";
import AptosIndexer from "./indexer/aptos";
import RoochIndexer from "./indexer/rooch";
import SuiIndexer from "./indexer/sui";
import { log } from "./logger";

(async () => {
  // Check env variables to determine which chains to subscribe to for events.
  // Start cron job to check for new events from Rooch Oracles

  if (env.rooch.privateKey && env.rooch.chainId.length > 0 && env.rooch.oracleAddress && env.chains.includes("ROOCH")) {
    // https://www.npmjs.com/package/cron#cronjob-class

    env.rooch.chainId.map((chain) => {
      const rooch = new RoochIndexer(env.rooch.privateKey, chain, env.rooch.oracleAddress);
      let running = false;
      const job = new CronJob(
        env.rooch.indexerCron,
        async () => {
          if (!running) {
            running = true;
            await rooch.run();
            running = false;
          }
        },
        null,
        true,
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

  // Add debug logs before the Sui check
  console.log("Debug Sui values:", {
    privateKey: !!env.sui?.privateKey, // just log if it exists
    chainId: env.sui?.chainId,
    oracleAddress: env.sui?.oracleAddress,
    chains: env.chains,
    includesSUI: env.chains.includes("SUI"),
  });

  if (env.sui?.privateKey && env.sui.chainId && env.sui.oracleAddress && env.chains.includes("SUI")) {
    const suiIndexer = new SuiIndexer(env.sui.oracleAddress, env.sui.chainId, env.sui.privateKey);

    // Add immediate execution for testing
    log.info("Running Sui indexer immediately...");
    await suiIndexer.run();

    new CronJob(
      env.sui.indexerCron,
      async () => {
        log.info("Running Sui indexer from cron...");
        await suiIndexer.run();
      },
      null,
      true,
    );
  } else {
    log.info(`Skipping Sui Indexer initialization...`, {
      hasPrivateKey: !!env.sui?.privateKey,
      chainId: env.sui?.chainId,
      oracleAddress: env.sui?.oracleAddress,
      includesSUI: env.chains.includes("SUI"),
    });
  }
})();
