import env from "@/env";
import axios from "axios";

class XfkaTwitter {
  private initialized = false;
  private accessToken: string | null = null;
  private SERVER_DOMAIN = "api.twitter.com";

  constructor(
    private apiKey: string,
    private apiKeySecret: string,
  ) {}

  get hosts() {
    return ["x.com", "api.x.com", "twitter.com", "api.twitter.com"];
  }

  isAvailable(): boolean {
    if (this.apiKey && this.apiKeySecret) {
      return true;
    }
    return false;
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  async requestAccessToken() {
    try {
      // Fetch bearer token
      const response = await axios.post(
        `https://${this.SERVER_DOMAIN}/oauth2/token`,
        new URLSearchParams({
          grant_type: "client_credentials",
        }).toString(),
        {
          headers: {
            "Content-Type": "application/x-www-form-urlencoded",
          },
          auth: {
            username: this.apiKey,
            password: this.apiKeySecret,
          },
        },
      );
      const accessToken = response.data.access_token;

      this.accessToken = accessToken;
      this.initialized = true;
      return accessToken;
    } catch (error: any) {
      console.error("Error fetching bearer token:", typeof error, error.message);
      throw error;
    }
  }

  getAccessToken(): string | null {
    if (!this.initialized) {
      throw new Error("Class not initialized");
    }
    return this.accessToken;
  }
}

export const instance = new XfkaTwitter(env.integrations.xApiKey, env.integrations.xApiSecret);
