import { log } from "@/logger";
import type { ProcessedRequestAdded } from "@/types";
import { isValidJson } from "@/util";
import axios, { type AxiosResponse } from "axios";
import jsonata from "jsonata";
import prismaClient from "prisma";
import APIBearerIntegration from "./xtwitter";
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
    return (
      this.hosts.includes(url.hostname.toLowerCase()) &&
      this.supported_paths.filter((path) => url.pathname.toLowerCase().startsWith(path)).length > 0
    );
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

      const url = data.params.url?.includes("http") ? data.params.url : `https://${data.params.url}`;

      try {
        const url_object = new URL(url);
        if (!this.isApprovedPath(url_object)) {
          return { status: 406, message: `${url_object} is supposed by this orchestrator` };
        }
        if (!this.validatePayload(url_object.pathname, data.params.body)) {
          return { status: 406, message: `Invalid Payload` };
        }
      } catch (err) {
        return { status: 406, message: `Invalid Domain Name` };
      }

      const token = this.getAccessToken();
      let request: AxiosResponse<any, any>;
      if (isValidJson(data.params.headers) && isValidJson(data.params.body)) {
        // TODO: Replace direct requests via axios with requests via VerityClient TS module
        request = await axios({
          method: data.params.method,
          data: JSON.parse(data.params.body),
          url: url,
          headers: {
            ...JSON.parse(data.params.headers),
            Authorization: `Bearer ${token}`,
          },
        });
        // return { status: request.status, message: request.data };
      } else {
        request = await axios({
          method: data.params.method,
          data: data.params.body,
          url: url,
          headers: {
            Authorization: `Bearer ${token}`,
          },
        });
      }

      try {
        // const result = (await jqRun(data.pick, JSON.stringify(request.data), { input: "string" })) as string;
        const expression = jsonata(
          data.pick === "." ? "*" : data.pick.startsWith(".") ? data.pick.replace(".", "") : data.pick,
        );
        const result =
          data.pick === "." ? JSON.stringify(request.data) : JSON.stringify(await expression.evaluate(request.data));
        log.info({ status: request.status, message: result });
        return { status: request.status, message: result };
      } catch {
        return { status: 409, message: "`Pick` value provided could not be resolved on the returned response" };
      }
      // return { status: request.status, message: result };
    } catch (error: any) {
      log.debug(
        JSON.stringify({
          error: error.message,
        }),
      );

      if (axios.isAxiosError(error)) {
        // Handle Axios-specific errors
        if (error.response) {
          // Server responded with a status other than 2xx
          return { status: error.response.status, message: error.response.data };
        } else if (error.request) {
          // No response received
          return { status: 504, message: "No response received" };
        } else {
          // Handle non-Axios errors
          return { status: 500, message: "Unexpected error" };
        }
      }
    }
    return { status: 500, message: "Something unexpected Happened" };
  }
}

export class DynamicInstanceManager {
  private instances: Map<string, APIBearerIntegration> = new Map();
  private isLoading = true;

  constructor() {
    this.initialize();
  }

  public async initialize() {
    const supportedUrls = await prismaClient.supportedUrl.findMany({
      where: {
        authKey: "BEARER",
      },
    });

    for (const url of supportedUrls) {
      this.instances.set(
        url.domain,
        new APIBearerIntegration(url.authKey, [url.domain], url.supported_path, Number(url.requestRate)),
      );
    }

    this.isLoading = false;
  }

  public getInstance(domain: string): APIBearerIntegration | undefined {
    if (this.isLoading) {
      throw new Error("DynamicInstanceManager is still loading. Try again later.");
    }
    return this.instances.get(domain);
  }

  public getAllInstances(): Map<string, APIBearerIntegration> {
    if (this.isLoading) {
      throw new Error("DynamicInstanceManager is still loading. Try again later.");
    }
    return this.instances;
  }

  public get loading(): boolean {
    return this.isLoading;
  }
}

export const dynamicInstanceManager = new DynamicInstanceManager();
