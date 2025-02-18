import { Network } from "@aptos-labs/ts-sdk";
import Joi from "joi";
import { AptosNetworkList, ChainList, type RoochNetwork, RoochNetworkList, SupportedChain } from "./types";
import { addressValidator, isRequiredWhenChainsInclude, privateKeyValidator } from "./validator";

const baseConfig = {
  chains: (process.env.CHAINS ? process.env.CHAINS.split(",") : ChainList) as SupportedChain[],
  // Rooch
  roochChainId: (process.env.ROOCH_CHAIN_ID
    ? process.env.ROOCH_CHAIN_ID.split(",")
    : ["testnet", "pre-mainnet"]) as RoochNetwork[],
  roochPrivateKey: process.env.ROOCH_PRIVATE_KEY ?? "",
  roochOracleAddress: process.env.ROOCH_ORACLE_ADDRESS ?? "",
  roochIndexerCron: process.env.ROOCH_INDEXER_CRON,
  // Aptos
  aptosChainId: process.env.APTOS_CHAIN_ID,
  aptosOracleAddress: process.env.APTOS_ORACLE_ADDRESS,
  aptosIndexerCron: process.env.APTOS_INDEXER_CRON,
  aptosPrivateKey: process.env.APTOS_PRIVATE_KEY,
  aptosNoditKey: process.env.APTOS_NODIT_KEY,
  // Common
  sentryDSN: process.env.SENTRY_DSN ?? "",
  ecdsaPrivateKey: process.env.ECDSA_PRIVATE_KEY ?? "",
  batchSize: process.env.BATCH_SIZE ?? 1000,
  // Integrations
  xBearerToken: process.env.X_BEARER_TOKEN ?? "",
  openAIToken: process.env.OPEN_AI_TOKEN ?? "",
  // Add Sui configuration
  sui: process.env.CHAINS?.includes("SUI")
    ? {
        chainId: process.env.SUI_CHAIN_ID as "mainnet" | "testnet" | "devnet",
        oracleAddress: process.env.SUI_ORACLE_ADDRESS,
        indexerCron: process.env.SUI_INDEXER_CRON,
        privateKey: process.env.SUI_PRIVATE_KEY,
      }
    : undefined,
};

interface IEnvVars {
  chains: SupportedChain[];
  roochChainId: RoochNetwork[];
  roochOracleAddress: string;
  roochPrivateKey: string;
  roochIndexerCron: string;
  aptosChainId: Network;
  aptosOracleAddress: string;
  aptosIndexerCron: string;
  aptosNoditKey: string;
  aptosPrivateKey: string;
  sentryDSN?: string;
  ecdsaPrivateKey?: string;
  batchSize: number;
  xBearerToken: string;
  openAIToken: string;
  sui?: {
    chainId: "mainnet" | "testnet" | "devnet";
    oracleAddress: string;
    indexerCron: string;
    privateKey: string;
  };
}

const envVarsSchema = Joi.object({
  // Chains
  chains: Joi.array()
    .items(
      Joi.string()
        .valid(...ChainList)
        .insensitive(),
    )
    .default(ChainList),
  roochChainId: Joi.array()
    .items(
      Joi.string()
        .valid(...RoochNetworkList)
        .insensitive()
        .default(RoochNetworkList[0]),
    )
    .default([RoochNetworkList[0]]),
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
    .valid(...Object.values(Network))
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
  aptosNoditKey: isRequiredWhenChainsInclude(Joi.string(), SupportedChain.APTOS),
  roochIndexerCron: Joi.string().default("*/5 * * * * *"),
  aptosIndexerCron: Joi.string().default("*/5 * * * * *"),

  // Integrations
  xBearerToken: Joi.string().allow("").required(),
  openAIToken: Joi.string().allow("").required(),

  // Common
  sentryDSN: Joi.string().allow("", null),
  ecdsaPrivateKey: Joi.string().allow("", null),
  batchSize: Joi.number().default(1000),

  // Add Sui validation
  sui: Joi.object({
    chainId: Joi.string().valid("mainnet", "testnet", "devnet").insensitive(),
    oracleAddress: Joi.string().custom((value, helper) => addressValidator(value, helper)),
    indexerCron: Joi.string().default("*/5 * * * * *"),
    privateKey: Joi.string().custom((value, helper) => {
      return privateKeyValidator(value, helper);
    }),
  }).when("chains", {
    is: Joi.array().items(Joi.string().valid(SupportedChain.SUI)),
    then: Joi.required(),
    otherwise: Joi.optional(),
  }),
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
  integrations: {
    xBearerToken: envVars.xBearerToken,
    openAIToken: envVars.openAIToken,
  },
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
    noditKey: envVars.aptosNoditKey,
  },
  sui: envVars.sui,
};
