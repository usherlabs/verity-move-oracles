import env from "@/env";
import { log } from "@/logger";
import Joi from "joi";
import { BasicBearerAPIHandler } from "./base";

const chatSchema = Joi.object({
  model: Joi.string().optional().allow(null, ""),
  messages: Joi.array().items(
    Joi.object({
      role: Joi.string().required(),
      content: Joi.string().required(),
    }).required(),
  ),
});
export default class AIIntegration extends BasicBearerAPIHandler {
  validatePayload(path: string, payload: string): boolean {
    try {
      const { error, value } = chatSchema.validate(JSON.parse(payload), {
        allowUnknown: true,
      });
      if (error) {
        log.error({ value, error });
        return false;
      }

      // AZURE
      if (this.hosts.some((s) => s.includes("openai.azure.com"))) {
        return true;
      }

      // OPENAI CHECK AND MODEL RESTRICTIONS
      if (path === "/v1/chat/completions" && value.model === "gpt-4o") {
        return true;
      }
      return false;
    } catch (e) {
      log.error({ validatePayloadError: e });
      return false;
    }
  }
}

export const openAIInstance = new AIIntegration(
  env.integrations.openAIToken,
  ["api.openai.com"],
  ["/v1/chat/completions"],
  60 * 1000,
);

export const azureInstance = new AIIntegration(
  env.integrations.azureToken,
  ["ai-oki6300ai905488739395.openai.azure.com"],
  ["/openai/deployments/"],
  60 * 1000,
);
