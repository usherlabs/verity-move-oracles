import env from "@/env";
import { BasicBearerAPIHandler } from "./base";

export default class AlbyIntegration extends BasicBearerAPIHandler {
  validatePayload(path: string): boolean {
    return true;
  }
}

export const instance = new AlbyIntegration(
  env.integrations.albyAccessToken,
  ["api.getalby.com"],
  ["/nwc/nip47/info", "/nwc/nip47", "/nwc/publish", "/nwc/subscriptions", "/nwc/nip47/notifications", "/nwc/subscriptions/"],
  60 * 1000,
);
