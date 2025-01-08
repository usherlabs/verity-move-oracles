import env from "@/env";
import { BasicBearerAPIHandler } from "./base";

export const instance = new BasicBearerAPIHandler(env.integrations.xBearerToken, ["api.openai.com",],["/v1/chat/completions"], 60*1000);
