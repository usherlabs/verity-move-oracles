import env from "@/env";
import { log } from "@/logger";
import { BasicBearerAPIHandler } from "./base";

export class XTwitterHandler extends BasicBearerAPIHandler {
  constructor(accessToken: string) {
    super(accessToken, ["api.x.com", "api.twitter.com"], ["/2/tweets", "/2/users/by/username", "/2/users/"], 15000);
  }

  async submitRequest(data: any) {
    // Add Twitter-specific headers
    data.params.headers = {
      ...data.params.headers,
      "User-Agent": "v2TwitterBot",
      Accept: "application/json",
    };

    log.debug("Twitter request params:", {
      url: data.params.url,
      method: data.params.method,
      headers: "Present", // Don't log actual headers
    });

    return super.submitRequest(data);
  }

  validatePayload(path: string): boolean {
    log.debug("Validating Twitter path:", path);
    return true;
  }
}

export const instance = new XTwitterHandler(env.integrations.xBearerToken);
