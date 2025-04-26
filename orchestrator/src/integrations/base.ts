import { log } from "@/logger";
import type { ProcessedRequestAdded } from "@/types";
import axios from "axios";
export abstract class BasicBearerAPIHandler {
  protected last_executed = 0;

  constructor(
    protected accessToken: string,
    protected supported_host: string[],
    protected supported_paths: string[],
    protected rate: number,
  ) {}

  get hosts() {
    return this.supported_host;
  }

  get paths() {
    return this.supported_paths;
  }

  get getRequestRate() {
    return this.rate;
  }

  isApprovedPath(url: URL): boolean {
    const hostMatch = this.hosts.includes(url.hostname.toLowerCase());
    const pathMatch = this.supported_paths.filter((path) => url.pathname.toLowerCase().startsWith(path)).length > 0;

    return hostMatch && pathMatch;
  }

  getAccessToken(): string | null {
    return this.accessToken;
  }

  abstract validatePayload(path: string, payload: string | null): boolean;

  async submitRequest(data: ProcessedRequestAdded<any>): Promise<{ status: number; message: string }> {
    try {
      const currentTime = Date.now();
      const timeSinceLastExecution = currentTime - this.last_executed;

      if (timeSinceLastExecution < this.getRequestRate) {
        const waitTime = this.getRequestRate - timeSinceLastExecution;
        await new Promise((resolve) => setTimeout(resolve, waitTime));
      }

      this.last_executed = Date.now();

      const headers =
        typeof data.params.headers === "string" ? JSON.parse(data.params.headers || "{}") : data.params.headers || {};

      const request = await axios({
        method: data.params.method,
        url: data.params.url,
        headers: {
          Authorization: `Bearer ${this.accessToken}`,
          ...headers,
        },
      });

      return {
        status: request.status,
        message: JSON.stringify(request.data),
      };
    } catch (error: any) {
      log.error("API request failed:", {
        error: error.message,
        response: error.response?.data,
      });
      return {
        status: error.response?.status || 500,
        message: JSON.stringify(error.response?.data || error.message),
      };
    }
  }
}
