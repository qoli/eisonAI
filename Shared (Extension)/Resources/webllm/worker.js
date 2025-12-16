import { WebWorkerMLCEngineHandler } from "./webllm.js";

const handler = new WebWorkerMLCEngineHandler();
self.onmessage = (event) => {
  handler.onmessage(event);
};

