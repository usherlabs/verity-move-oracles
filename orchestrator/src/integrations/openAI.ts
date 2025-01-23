import env from "@/env";
import { log } from "@/logger";
import Joi from "joi";
import { BasicBearerAPIHandler } from "./base";

const chatSchema = Joi.object({
  model: Joi.string().required(),
  messages: Joi.array().items(
    Joi.object({
      role: Joi.string().required(),
      content: Joi.string().required(),
    }).required(),
  ),
});
export default class OpenAIIntegration extends BasicBearerAPIHandler {
  validatePayload(path: string, payload: string): boolean {
    try {
      if (this.supported_paths.includes(path)) {
        if (path === "/v1/chat/completions") {
          const { error, value } = chatSchema.validate(JSON.parse(payload), {
            allowUnknown: true,
          });
          if (error) {
            log.error({ value, error });
            return false;
          } else {
            if (value.model === "gpt-4o") {
              return true;
            }
          }
        }
      }
      return false;
    } catch {
      return false;
    }
  }
}

export const instance = new OpenAIIntegration(
  env.integrations.openAIToken,
  ["api.openai.com"],
  ["/v1/chat/completions"],
  60 * 1000,
);
