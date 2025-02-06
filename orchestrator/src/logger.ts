import { Logger } from "tslog";

const log = new Logger({
  type: process.env.NODE_ENV === "production" ? "json" : "pretty",
  stylePrettyLogs: false,
});

export { log };
