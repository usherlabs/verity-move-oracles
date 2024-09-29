import { Logger } from "tslog";

const log = new Logger({
  type: "json", // This will stringify all objects passed in parameters
});

export { log };
