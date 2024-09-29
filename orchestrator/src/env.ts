import Joi from "joi";
import {
  type AptosNetwork,
  AptosNetworkList,
  ChainList,
  type RoochNetwork,
  RoochNetworkList,
  SupportedChain,
} from "./types";
import { addressValidator, isRequiredWhenChainsInclude, privateKeyValidator } from "./validator";

const baseConfig = {
  chains: (process.env.CHAINS ? process.env.CHAINS.split(",") : ChainList) as SupportedChain[],
  // Rooch
  roochChainId: process.env.ROOCH_CHAIN_ID,
  roochPrivateKey: process.env.ROOCH_PRIVATE_KEY ?? "",
  roochOracleAddress: process.env.ROOCH_ORACLE_ADDRESS ?? "",
  roochIndexerCron: process.env.ROOCH_INDEXER_CRON,
  // Aptos
  aptosChainId: process.env.APTOS_CHAIN_ID,
  aptosOracleAddress: process.env.APTOS_ORACLE_ADDRESS,
  aptosIndexerCron: process.env.APTOS_INDEXER_CRON,
  aptosPrivateKey: process.env.APTOS_PRIVATE_KEY,
  // Common
  sentryDSN: process.env.SENTRY_DSN ?? "",
  ecdsaPrivateKey: process.env.SENTRY_DSN ?? "",
  batchSize: process.env.BATCH_SIZE ?? 1000,
  // Integrations
  xApiSecret: process.env.X_API_SECRET ?? "",
  xApiKey: process.env.X_API_KEY ?? "",
};

interface IEnvVars {
  chains: SupportedChain[];
  roochChainId: RoochNetwork;
  roochOracleAddress: string;
  roochPrivateKey: string;
  roochIndexerCron: string;
  aptosChainId: AptosNetwork;
  aptosOracleAddress: string;
  aptosIndexerCron: string;
  aptosPrivateKey: string;
  sentryDSN?: string;
  ecdsaPrivateKey?: string;
  batchSize: number;
  xApiKey: string;
  xApiSecret: string;
}

const envVarsSchema = Joi.object({
  chains: Joi.array()
    .items(
      Joi.string()
        .valid(...ChainList)
        .insensitive(),
    )
    .default(ChainList),
  roochChainId: Joi.string()
    .valid(...RoochNetworkList)
    .insensitive()
    .default(RoochNetworkList[0]),
  roochOracleAddress: isRequiredWhenChainsInclude(
    Joi.string().custom((value, helper) => addressValidator(value, helper)),
    SupportedChain.ROOCH,
  ),
  roochPrivateKey: isRequiredWhenChainsInclude(
    Joi.string().custom((value, helper) => {
      return privateKeyValidator(value, helper);
    }),
    SupportedChain.ROOCH,
  ),
  aptosChainId: Joi.string()
    .valid(...AptosNetworkList) // Assuming AptosNetworkList is defined similarly to RoochNetworkList
    .insensitive()
    .default(AptosNetworkList[0]),
  aptosOracleAddress: isRequiredWhenChainsInclude(
    Joi.string().custom((value, helper) => addressValidator(value, helper)),
    SupportedChain.APTOS,
  ),
  aptosPrivateKey: isRequiredWhenChainsInclude(
    Joi.string().custom((value, helper) => {
      return privateKeyValidator(value, helper);
    }),
    SupportedChain.APTOS,
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
  chains: envVars.chains,
  batchSize: envVars.batchSize,
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
  aptos: {
    chainId: envVars.aptosChainId,
    oracleAddress: envVars.aptosOracleAddress,
    indexerCron: envVars.aptosIndexerCron,
    privateKey: envVars.aptosPrivateKey,
  },
};
