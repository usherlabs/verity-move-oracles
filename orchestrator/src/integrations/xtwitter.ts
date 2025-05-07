import env from "@/env";
import APIBaseIntegration from "@/integrations/base";

export const xTwitterInstance = new APIBaseIntegration(
  env.integrations.xBearerToken,
  ["api.x.com", "api.twitter.com"],
  ["/2/tweets", "/2/users/"],
  60 * 1000,
);
