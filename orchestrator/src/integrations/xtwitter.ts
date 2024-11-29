import env from "@/env";

class XfkaTwitter {
  private SERVER_DOMAIN = "api.twitter.com";

  constructor(private accessToken: string) {}

  get hosts() {
    return ["x.com", "api.x.com", "twitter.com", "api.twitter.com"];
  }

  get getRequestRate() {
    return 60 * 1000; //
  }
  getAccessToken(): string | null {
    return this.accessToken;
  }
}

export const instance = new XfkaTwitter(env.integrations.xBearerToken);
