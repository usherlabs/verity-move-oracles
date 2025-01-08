

export class BasicBearerAPIHandler {

    constructor(private accessToken: string, private supported_host:string[],private  supported_paths: string[] , private rate: number) {}
  
    get hosts() {
      return this.supported_host;
    }

    get paths() {
      return this.supported_paths;
    }
  
    get getRequestRate() {
      return this.rate;
    }

    getAccessToken(): string | null {
      return this.accessToken;
    }
}