import { CreateWebWorkerMLCEngine } from "./webllm.js";

const browser = globalThis.browser ?? globalThis.chrome;

const MODEL_ID = "Qwen3-0.6B-q4f16_1-MLC";
const WASM_FILE = "Qwen3-0.6B-q4f16_1-ctx4k_cs1k-webgpu.wasm";
const WASM_URL = new URL(`../webllm-assets/wasm/${WASM_FILE}`, import.meta.url)
  .href;

const modelSelect = document.getElementById("model");
const loadButton = document.getElementById("load");
const unloadButton = document.getElementById("unload");
const summarizeButton = document.getElementById("summarize");
const clearButton = document.getElementById("clear");
const runButton = document.getElementById("run");
const stopButton = document.getElementById("stop");
const statusEl = document.getElementById("status");
const envEl = document.getElementById("env");
const progressEl = document.getElementById("progress");
const inputEl = document.getElementById("input");
const outputEl = document.getElementById("output");

function hasWebGPU() {
  return Boolean(globalThis.navigator?.gpu);
}

function setStatus(text, progress) {
  statusEl.textContent = text;
  if (typeof progress === "number") {
    progressEl.value = Math.min(1, Math.max(0, progress));
  }
}

function setOutput(text) {
  outputEl.textContent = text;
}

function enableControls(loaded) {
  unloadButton.disabled = !loaded;
  summarizeButton.disabled = !loaded;
  clearButton.disabled = !loaded;
  runButton.disabled = !loaded;
  stopButton.disabled = true;
  inputEl.disabled = !loaded;
}

function initProgressCallback(report) {
  setStatus(report.text, report.progress);
}

function getLocalAppConfig(modelId) {
  const modelUrl = new URL(
    `../webllm-assets/models/${modelId}/resolve/main/`,
    import.meta.url,
  ).href;
  return {
    useIndexedDBCache: false,
    model_list: [
      {
        model: modelUrl,
        model_id: modelId,
        model_lib: WASM_URL,
        vram_required_MB: 1403.34,
        low_resource_required: true,
        overrides: { context_window_size: 4096 },
      },
    ],
  };
}

function clampText(text, limit) {
  const normalized = String(text ?? "").trim();
  if (normalized.length <= limit) return normalized;
  return normalized.slice(0, limit) + "\n\n（內容過長，已截斷）";
}

async function getActiveTab() {
  if (typeof browser?.tabs?.query !== "function") {
    throw new Error("browser.tabs.query is unavailable");
  }
  const tabs = await browser.tabs.query({ active: true, currentWindow: true });
  return tabs?.[0] ?? null;
}

async function getArticleTextFromContentScript() {
  if (typeof browser?.tabs?.sendMessage !== "function") {
    throw new Error("browser.tabs.sendMessage is unavailable");
  }
  const tab = await getActiveTab();
  if (!tab?.id) throw new Error("No active tab found");
  const resp = await browser.tabs.sendMessage(tab.id, {
    command: "getArticleText",
  });
  if (!resp || resp.command !== "articleTextResponse") {
    throw new Error("Unexpected content script response");
  }
  if (resp.error) throw new Error(resp.error);
  return { title: resp.title ?? "", text: resp.body ?? "", url: tab.url ?? "" };
}

function buildSummaryMessages({ title, text, url }) {
  const clippedText = clampText(text, 6000);
  const system = [
    "你是一個網頁文章摘要助手。請用繁體中文輸出，並嚴格遵守格式：",
    "",
    "總結：<一行>",
    "要點：",
    "- <每行一個要點，開頭請用 emoji>",
    "",
    "除了以上格式，不要輸出任何多餘文字。",
    "禁止輸出任何推理過程或標籤（例如 <think>、<analysis>）。",
  ].join("\n");

  const user = [
    "請摘要以下網頁內容：",
    "",
    `【標題】\n${title || "(no title)"}`,
    `【URL】\n${url || "(no url)"}`,
    `【正文】\n${clippedText || "(empty)"}`,
  ].join("\n\n");

  return [
    { role: "system", content: system },
    { role: "user", content: user },
  ];
}

let engine = null;
let worker = null;
let generating = false;

modelSelect.appendChild(new Option(MODEL_ID, MODEL_ID));
modelSelect.value = MODEL_ID;

const demoModelUrl = new URL(
  `../webllm-assets/models/${MODEL_ID}/resolve/main/`,
  import.meta.url,
).href;
envEl.textContent = `WebGPU: ${hasWebGPU() ? "available" : "unavailable"} · Assets: bundled · model: ${new URL(demoModelUrl).protocol} · wasm: ${new URL(WASM_URL).protocol}`;
console.log("[WebLLM Demo] modelUrl =", demoModelUrl);
console.log("[WebLLM Demo] wasmUrl  =", WASM_URL);
enableControls(false);

async function loadEngine(modelId) {
  if (!hasWebGPU()) {
    throw new Error("WebGPU is unavailable in this environment.");
  }

  setStatus("Creating worker…", 0);
  worker?.terminate();
  try {
    worker = new Worker(new URL("./worker.js", import.meta.url), {
      type: "module",
    });
  } catch (err) {
    throw new Error(
      `Worker init failed: ${err?.message ? String(err.message) : String(err)}`,
    );
  }

  setStatus("Loading model…", 0);
  engine = await CreateWebWorkerMLCEngine(worker, modelId, {
    initProgressCallback,
    appConfig: getLocalAppConfig(modelId),
  });

  enableControls(true);
  setStatus("Ready", 1);
}

async function unloadEngine() {
  generating = false;
  stopButton.disabled = true;
  runButton.disabled = true;
  summarizeButton.disabled = true;

  try {
    await engine?.unload?.();
  } finally {
    engine = null;
    worker?.terminate();
    worker = null;
    enableControls(false);
    setStatus("Unloaded", 0);
  }
}

async function streamChat(messages) {
  if (!engine) throw new Error("Engine is not loaded.");

  generating = true;
  runButton.disabled = true;
  summarizeButton.disabled = true;
  stopButton.disabled = false;
  setOutput("");

  await engine.resetChat();

  let acc = "";
  const completion = await engine.chat.completions.create({
    stream: true,
    stream_options: { include_usage: true },
    messages,
    temperature: 0.4,
    max_tokens: 512,
    extra_body: { enable_thinking: false },
  });

  try {
    for await (const chunk of completion) {
      const delta = chunk?.choices?.[0]?.delta?.content ?? "";
      if (delta) {
        acc += delta;
        setOutput(acc);
      }
    }
  } finally {
    generating = false;
    stopButton.disabled = true;
    runButton.disabled = false;
    summarizeButton.disabled = false;
  }
}

loadButton.addEventListener("click", async () => {
  loadButton.disabled = true;
  modelSelect.disabled = true;
  setOutput("");
  try {
    await loadEngine(modelSelect.value);
  } catch (err) {
    setStatus(err?.message ? String(err.message) : String(err), 0);
    enableControls(false);
  } finally {
    loadButton.disabled = false;
    modelSelect.disabled = false;
  }
});

unloadButton.addEventListener("click", async () => {
  unloadButton.disabled = true;
  try {
    await unloadEngine();
  } finally {
    unloadButton.disabled = false;
  }
});

clearButton.addEventListener("click", () => setOutput(""));

stopButton.addEventListener("click", () => {
  if (!engine || !generating) return;
  engine.interruptGenerate();
  setStatus("Stopping…");
});

runButton.addEventListener("click", async () => {
  try {
    const prompt = inputEl.value.trim();
    if (!prompt) {
      setStatus("請先輸入 prompt");
      return;
    }
    await streamChat([{ role: "user", content: prompt }]);
  } catch (err) {
    setStatus(err?.message ? String(err.message) : String(err));
  }
});

summarizeButton.addEventListener("click", async () => {
  try {
    setStatus("Reading page…");
    const ctx = await getArticleTextFromContentScript();
    await streamChat(buildSummaryMessages(ctx));
  } catch (err) {
    setStatus(err?.message ? String(err.message) : String(err));
  }
});
