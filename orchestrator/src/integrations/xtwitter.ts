import env from "@/env";
import { BasicBearerAPIHandler } from "./base";

export const instance = new BasicBearerAPIHandler(env.integrations.xBearerToken, ["api.x.com", "api.twitter.com"],["/2/tweets"], 60*1000);
