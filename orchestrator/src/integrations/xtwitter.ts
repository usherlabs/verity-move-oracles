import env from "@/env";
import { BasicBearerAPIHandler } from "./base";

export default class TwitterIntegration extends BasicBearerAPIHandler {
  validatePayload(path: string): boolean {
    return true;
  }
}

export const instance = new TwitterIntegration(
  env.integrations.openAIToken,
  ["api.x.com", "api.twitter.com"],
  ["/2/tweets"],
  60 * 1000,
);
