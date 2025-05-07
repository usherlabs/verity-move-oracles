import env from "@/env";
import { BasicBearerAPIHandler } from "./base";

export default class APIBearerIntegration extends BasicBearerAPIHandler {
  validatePayload(path: string): boolean {
    return true;
  }
}

export const xTwitterInstance = new APIBearerIntegration(
  env.integrations.xBearerToken,
  ["api.x.com", "api.twitter.com"],
  ["/2/tweets", "/2/users/"],
  60 * 1000,
);
