import Joi from "joi";
import { ChainList, type RoochNetwork, RoochNetworkList, SupportedChain } from "./types";
import { addressValidator, isRequiredWhenPreferredChainIs, privateKeyValidator } from "./validator";

const baseConfig = {
  preferredChain: process.env.PREFERRED_CHAIN ?? ChainList[0],
  roochChainId: process.env.ROOCH_CHAIN_ID,
  roochPrivateKey: process.env.ROOCH_PRIVATE_KEY ?? "",
  roochOracleAddress: process.env.ROOCH_ORACLE_ADDRESS ?? "",
  roochIndexerCron: process.env.ROOCH_INDEXER_CRON,
  sentryDSN: process.env.SENTRY_DSN ?? "",
  ecdsaPrivateKey: process.env.SENTRY_DSN ?? "",
  batchSize: process.env.BATCH_SIZE ?? 1000,
  xApiSecret: process.env.X_API_SECRET ?? "",
  xApiKey: process.env.X_API_KEY ?? "",
};
interface IEnvVars {
  preferredChain: SupportedChain;
  roochChainId: RoochNetwork;
  roochOracleAddress: string;
  roochPrivateKey: string;
  roochIndexerCron: string;
  sentryDSN?: string;
  ecdsaPrivateKey?: string;
  batchSize: number;
  xApiKey: string;
  xApiSecret: string;
}

const envVarsSchema = Joi.object({
  preferredChain: Joi.string()
    .valid(...ChainList)
    .insensitive()
    .default(ChainList[0]),
  roochChainId: Joi.string()
    .valid(...RoochNetworkList)
    .insensitive()
    .default(RoochNetworkList[0]),
  roochOracleAddress: isRequiredWhenPreferredChainIs(
    Joi.string().custom((value, helper) => addressValidator(value, helper)),
    SupportedChain.ROOCH,
  ),
  roochPrivateKey: isRequiredWhenPreferredChainIs(
    Joi.string().custom((value, helper) => {
      return privateKeyValidator(value, helper);
    }),
    SupportedChain.ROOCH,
  ),
  xApiSecret: Joi.string().required(),
  xApiKey: Joi.string().required(),
  roochIndexerCron: Joi.string().default("*/5 * * * * *"),
  sentryDSN: Joi.string().allow("", null),
  ecdsaPrivateKey: Joi.string().allow("", null),
  batchSize: Joi.number().default(1000),
});

const { value, error } = envVarsSchema.validate({
  ...baseConfig,
});

if (error) {
  throw new Error(error.message);
}
const envVars = value as IEnvVars;

export default {
  batchSize: envVars.batchSize,
  chain: envVars.preferredChain,
  ecdsaPrivateKey: envVars.ecdsaPrivateKey,
  sentryDSN: envVars.sentryDSN,
  xApiSecret: envVars.xApiSecret,
  xApiKey: envVars.xApiKey,
  rooch: {
    chainId: envVars.roochChainId,
    oracleAddress: envVars.roochOracleAddress,
    // Ideally promote indexerCron, it shouldn't necessary be tided to a chain
    indexerCron: envVars.roochIndexerCron,
    privateKey: envVars.roochPrivateKey,
  },
  // aptos: {
  //   chainId: process.env.APTOS_CHAIN_ID,
  //   oracleAddress: process.env.APTOS_ORACLE_ADDRESS,
  //   indexerCron: process.env.APTOS_INDEXER_CRON,
  //   privateKey: process.env.APTOS_PRIVATE_KEY,
  // }
};
