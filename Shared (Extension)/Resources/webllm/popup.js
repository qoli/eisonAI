import { CreateWebWorkerMLCEngine } from "./webllm.js";

const browser = globalThis.browser ?? globalThis.chrome;

const MODEL_ID = "Qwen3-0.6B-q4f16_1-MLC";
const MAX_OUTPUT_TOKENS = 1500;
const WASM_FILE = "Qwen3-0.6B-q4f16_1-ctx4k_cs1k-webgpu.wasm";
const WASM_URL = new URL(`../webllm-assets/wasm/${WASM_FILE}`, import.meta.url)
  .href;

const modelSelect = document.getElementById("model");
const loadButton = document.getElementById("load");
const unloadButton = document.getElementById("unload");
const summarizeButton = document.getElementById("summarize");
const copySystemButton = document.getElementById("copy-system");
const copyUserButton = document.getElementById("copy-user");
const clearButton = document.getElementById("clear");
const runButton = document.getElementById("run");
const stopButton = document.getElementById("stop");
const statusEl = document.getElementById("status");
const envEl = document.getElementById("env");
const progressEl = document.getElementById("progress");
const inputEl = document.getElementById("input");
const inputTokensEl = document.getElementById("input-tokens");
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

const CJK_REGEX = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/gu;

function estimateTokensFromText(text) {
  const value = String(text ?? "");
  if (!value) return 0;

  const cjkCount = value.match(CJK_REGEX)?.length ?? 0;
  const nonCjkLength = value.replace(CJK_REGEX, "").length;
  const estimate = cjkCount + nonCjkLength / 4;
  return Math.max(1, Math.ceil(estimate));
}

function estimateTokensForMessages(messages) {
  if (!Array.isArray(messages)) return 0;
  let total = 0;
  for (const msg of messages) {
    if (!msg) continue;
    const content = msg.content;
    if (typeof content === "string") {
      total += estimateTokensFromText(content);
    } else if (Array.isArray(content)) {
      for (const part of content) {
        if (part?.type === "text" && typeof part.text === "string") {
          total += estimateTokensFromText(part.text);
        }
      }
    }
  }
  return total;
}

function setInputTokenEstimate(tokens) {
  if (!inputTokensEl) return;
  if (typeof tokens !== "number" || !Number.isFinite(tokens)) {
    inputTokensEl.textContent = "—";
    return;
  }
  inputTokensEl.textContent = `~${Math.max(0, Math.round(tokens))}`;
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

function tryExecCommandCopy(value) {
  try {
    const textarea = document.createElement("textarea");
    textarea.value = value;
    textarea.readOnly = true;
    textarea.style.position = "fixed";
    textarea.style.top = "0";
    textarea.style.left = "0";
    textarea.style.width = "1px";
    textarea.style.height = "1px";
    textarea.style.opacity = "0";
    textarea.style.pointerEvents = "none";
    textarea.style.userSelect = "text";
    textarea.style.webkitUserSelect = "text";
    document.body.appendChild(textarea);

    textarea.focus({ preventScroll: true });
    textarea.select();
    textarea.setSelectionRange(0, textarea.value.length);

    const ok = document.execCommand("copy");
    textarea.remove();
    return ok;
  } catch {
    return false;
  }
}

async function copyToClipboard(text) {
  const value = String(text ?? "");
  if (!value) throw new Error("Nothing to copy.");

  if (tryExecCommandCopy(value)) {
    return { method: "execCommand" };
  }

  const clipboard = globalThis.navigator?.clipboard;
  if (clipboard?.writeText) {
    await clipboard.writeText(value);
    return { method: "clipboard" };
  }

  throw new Error("Clipboard is unavailable in this environment.");
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

const SUMMARY_SYSTEM_PROMPT =
  "你是一個網頁總結助手，請執行網頁總結任務。\n只需要輸出簡短的摘要內容，以繁體中文輸出。";

function buildSummaryUserPrompt({ title, text, url }) {
  const clippedText = clampText(text, 10000);
  return [
    "請摘要以下網頁內容：",
    "",
    `【標題】\n${title || "(no title)"}`,
    `【URL】\n${url || "(no url)"}`,
    `【正文】\n${clippedText || "(empty)"}`,
  ].join("\n\n");
}

function buildSummaryMessages({ title, text, url }) {
  const system = SUMMARY_SYSTEM_PROMPT;
  const user = buildSummaryUserPrompt({ title, text, url });

  return [
    { role: "system", content: system },
    { role: "user", content: user },
  ];
}

let engine = null;
let worker = null;
let generating = false;
let cachedUserPrompt = "";
let preparedMessagesForTokenEstimate = [];

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

async function refreshCachedUserPrompt() {
  try {
    const ctx = await getArticleTextFromContentScript();
    cachedUserPrompt = buildSummaryUserPrompt(ctx);
    preparedMessagesForTokenEstimate = buildSummaryMessages(ctx);
    setInputTokenEstimate(estimateTokensForMessages(preparedMessagesForTokenEstimate));
  } catch (err) {
    cachedUserPrompt = "";
    preparedMessagesForTokenEstimate = [];
    setInputTokenEstimate(0);
    console.warn("[WebLLM Demo] Failed to prefetch user prompt:", err);
  }
}

refreshCachedUserPrompt();

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

  preparedMessagesForTokenEstimate = messages;
  setInputTokenEstimate(estimateTokensForMessages(preparedMessagesForTokenEstimate));

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
    max_tokens: MAX_OUTPUT_TOKENS,
    extra_body: { enable_thinking: true },
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

copySystemButton?.addEventListener("click", async () => {
  try {
    await copyToClipboard(SUMMARY_SYSTEM_PROMPT);
    setStatus("已複製系統提示詞");
  } catch (err) {
    setOutput(SUMMARY_SYSTEM_PROMPT);
    setStatus("無法寫入剪貼簿，已在下方顯示內容，請手動複製。");
  }
});

copyUserButton?.addEventListener("click", async () => {
  if (!cachedUserPrompt) {
    copyUserButton.disabled = true;
    try {
      setStatus("Preparing user prompt…");
      await refreshCachedUserPrompt();
      setStatus("已準備用戶提示詞，請再按一次「複製用戶提示詞」。");
    } finally {
      copyUserButton.disabled = false;
    }
    return;
  }

  try {
    await copyToClipboard(cachedUserPrompt);
    setStatus("已複製用戶提示詞");
  } catch (err) {
    setOutput(cachedUserPrompt);
    setStatus("無法寫入剪貼簿，已在下方顯示內容，請手動複製。");
  }
});

runButton.addEventListener("click", async () => {
  try {
    const prompt = inputEl.value.trim();
    if (!prompt) {
      setStatus("請先輸入 prompt");
      return;
    }
    preparedMessagesForTokenEstimate = [{ role: "user", content: prompt }];
    setInputTokenEstimate(estimateTokensForMessages(preparedMessagesForTokenEstimate));
    await streamChat([{ role: "user", content: prompt }]);
  } catch (err) {
    setStatus(err?.message ? String(err.message) : String(err));
  }
});

inputEl.addEventListener("input", () => {
  const prompt = inputEl.value.trim();
  if (prompt) {
    setInputTokenEstimate(estimateTokensFromText(prompt));
  } else if (preparedMessagesForTokenEstimate.length) {
    setInputTokenEstimate(estimateTokensForMessages(preparedMessagesForTokenEstimate));
  } else {
    setInputTokenEstimate(0);
  }
});

summarizeButton.addEventListener("click", async () => {
  try {
    setStatus("Reading page…");
    const ctx = await getArticleTextFromContentScript();
    cachedUserPrompt = buildSummaryUserPrompt(ctx);
    preparedMessagesForTokenEstimate = buildSummaryMessages(ctx);
    setInputTokenEstimate(estimateTokensForMessages(preparedMessagesForTokenEstimate));
    await streamChat(buildSummaryMessages(ctx));
  } catch (err) {
    setStatus(err?.message ? String(err.message) : String(err));
  }
});
