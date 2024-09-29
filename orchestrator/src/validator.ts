import Joi from "joi";

export const addressValidator = (value: string, helpers: Joi.CustomHelpers<any>) => {
  if (/^0x[a-fA-F0-9]{64}$/.test(value)) {
    return value;
  }
  return helpers.error("any.invalid");
};

export const privateKeyValidator = (value: string, helpers: Joi.CustomHelpers<any>) => {
  // TODO: Add proper validation for Private key
  return value;
};

// Define a regex pattern for basic cron expressions (seconds not included)
const cronPattern =
  /^(\*|([0-5]?[0-9])) (\*|([01]?[0-9]|2[0-3])) (\*|([0-2]?[0-9]|3[0-1])) (\*|([0-1]?[0-9]|1[0-2])) (\*|[0-6])$/;

// Define a regex pattern for cron expressions including seconds
const cronPatternWithSeconds =
  /^(\*|([0-5]?[0-9])) (\*|([0-5]?[0-9])) (\*|([0-5]?[0-9])) (\*|([0-1]?[0-9]|2[0-3])) (\*|([0-2]?[0-9]|3[0-1])) (\*|([0-1]?[0-9]|1[0-2])) (\*|[0-6])$/;

// Check for standard cron (5 fields) or extended cron (6 fields including seconds)
export const cronValidator = (value: string, helpers: Joi.CustomHelpers<any>) => {
  if (cronPattern.test(value) || cronPatternWithSeconds.test(value)) {
    return value;
  }
  return helpers.error("any.invalid");
};

/* eslint-disable lint/suspicious/noThenProperty */
export const isRequiredWhenChainsInclude = (schema: Joi.StringSchema<string>, value: string) =>
  Joi.string().when("chains", {
    is: Joi.array().items(Joi.string().valid(value)).has(value),
    then: schema.required(), // 'details' is required if 'status' is 'active'
    otherwise: Joi.string().optional().allow("", null).default(""), // 'details' is optional otherwise
  });
