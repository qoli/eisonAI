import { CreateWebWorkerMLCEngine } from "./webllm.js";

const browser = globalThis.browser ?? globalThis.chrome;

const MODEL_ID = "Qwen3-0.6B-q4f16_1-MLC";
const MAX_OUTPUT_TOKENS = 1500;
const FOUNDATION_PREWARM_PREFIX_LIMIT = 1200;
const NO_SUMMARY_TEXT_MESSAGE = "No summary text";
const DEFAULT_LONG_DOCUMENT_CHUNK_TOKEN_SIZE = 2000;
const DEFAULT_LONG_DOCUMENT_ROUTING_THRESHOLD = 2600;
const DEFAULT_AUTO_STRATEGY_THRESHOLD = 2600;
const DEFAULT_AUTO_LOCAL_PREFERENCE = "appleIntelligence";
const DEFAULT_LONG_DOCUMENT_MAX_CHUNKS = 5;
const DEFAULT_TOKEN_ESTIMATOR = "cl100k_base";
const TOKENIZER_GLOBALS = {
  cl100k_base: "GPTTokenizer_cl100k_base",
  o200k_base: "GPTTokenizer_o200k_base",
  p50k_base: "GPTTokenizer_p50k_base",
  r50k_base: "GPTTokenizer_r50k_base",
};
const LONG_DOCUMENT_CHUNK_SIZE_OPTIONS = new Set([2000, 2200, 2600, 3000, 3200]);
const LONG_DOCUMENT_MAX_CHUNK_OPTIONS = new Set([4, 5, 6, 7]);
const VISIBILITY_TEXT_LIMIT = 600;
const WASM_FILE = "Qwen3-0.6B-q4f16_1-ctx4k_cs1k-webgpu.wasm";
const WASM_URL = new URL(`../webllm-assets/wasm/${WASM_FILE}`, import.meta.url)
  .href;
const WEBGPU_REQUIRED_FEATURES = ["shader-f16"];
const WEBGPU_STATUS_TTL_MS = 15000;
const WEBGPU_STATUS_STATES = {
  checking: { text: "checking…", className: "is-checking" },
  available: { text: "ready", className: "is-available" },
  limited: { text: "limited", className: "is-limited" },
  unavailable: { text: "unavailable", className: "is-unavailable" },
  error: { text: "error", className: "is-error" },
};
const WEBGPU_STATUS_CLASSES = Object.values(WEBGPU_STATUS_STATES).map(
  (state) => state.className,
);
const LOG_PREVIEW_LIMIT = 160;

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
const webgpuStatusEl = document.getElementById("webgpu-status");
const progressEl = document.getElementById("progress");
const progressDotEl = document.querySelector(".progress-dot");
const aiModelEl = document.querySelector(".ai-model");
const inputEl = document.getElementById("input");
const inputTokensEl = document.getElementById("input-tokens");
const thinkEl = document.getElementById("think");
const thinkContainerEl = thinkEl?.closest?.(".container") ?? null;
const outputEl = document.getElementById("output");
const shareEl = document.getElementById("share");

let lastModelOutputMarkdown = "";
let markdownParser = null;
let lastWebGPUStatus = { state: "checking" };
let lastWebGPUStatusAt = 0;
let webgpuStatusPromise = null;
const envProtocols = { model: "", wasm: "" };
let nativeBackendSelection = "local";
let byokModelName = "";
let autoStrategyThreshold = DEFAULT_AUTO_STRATEGY_THRESHOLD;
let autoLocalPreference = DEFAULT_AUTO_LOCAL_PREFERENCE;
let autoQwenEnabled = false;
let autoAppleAvailability = null;
let lastFoundationAvailability = null;
let lastExecutionBackend = "";

const AI_MODEL_WEBLLM_LABEL = "Qwen3 0.6B";
const AI_MODEL_FM_LABEL = "Apple Intelligence";

const DOT_STATES = {
  engine: { className: "state-engine", breathing: true },
  generating: { className: "state-generating", breathing: true },
  longdoc: { className: "state-longdoc", breathing: true },
  reading: { className: "state-reading", breathing: true },
  stopped: { className: "state-stopped", breathing: false },
  error: { className: "state-error", breathing: false },
  ready: { className: "state-ready", breathing: false },
};
const DOT_STATE_CLASSES = Object.values(DOT_STATES).map((state) => state.className);

const STATUS_ENGINE = new Set([
  "Creating worker…",
  "Loading model…",
  "Unloaded",
  "Engine crashed, restarting…",
]);
const STATUS_GENERATING = new Set([
  "Generating…",
  "Generating summary…",
  "Starting native…",
  "Native failed, fallback…",
]);
const STATUS_LONGDOC = new Set([
  "Preparing long document…",
]);
const STATUS_READING = new Set([
  "Reading page…",
]);
const STATUS_STOPPED = new Set([
  "Stopping…",
]);
const STATUS_NO_DOT_CHANGE = new Set([
  "System prompt copied",
  "Clipboard unavailable, content shown.",
  "Preparing prompt…",
  "User prompt ready (click again to copy)",
  "User prompt copied",
  "Nothing to share",
  "Summary and link copied",
]);

function previewText(value, limit = LOG_PREVIEW_LIMIT) {
  const text = String(value ?? "");
  const normalized = text.replace(/\s+/g, " ").trim();
  if (!normalized) return "";
  if (normalized.length <= limit) return normalized;
  return `${normalized.slice(0, limit)}…`;
}

function logTextSummary(label, text) {
  const value = String(text ?? "");
  console.log(`[WebLLM Demo] ${label}`, {
    length: value.length,
    preview: previewText(value),
  });
}

function logPopupEvent(event, details) {
  console.log(`[WebLLM Demo] ${event}`, details ?? {});
}

function hasWebGPU() {
  return Boolean(globalThis.navigator?.gpu);
}

function getWebGPUStatusLabel(state, { isFallbackAdapter } = {}) {
  if (state === "available" && isFallbackAdapter) return "fallback";
  return WEBGPU_STATUS_STATES[state]?.text ?? "unknown";
}

function buildWebGPUStatusText(status) {
  const summary = getWebGPUStatusLabel(status.state, status);
  return `WebGPU: ${summary}`;
}

function buildWebGPUStatusDetails(status) {
  const lines = [];
  if (status.adapterDescription) {
    lines.push(`Adapter: ${status.adapterDescription}`);
  }
  if (typeof status.isFallbackAdapter === "boolean") {
    lines.push(`Fallback adapter: ${status.isFallbackAdapter ? "yes" : "no"}`);
  }
  if (Array.isArray(status.missingFeatures) && status.missingFeatures.length) {
    lines.push(`Missing features: ${status.missingFeatures.join(", ")}`);
  } else if (Number.isFinite(status.featureCount)) {
    lines.push(`Feature count: ${status.featureCount}`);
  }
  if (status.reason) {
    lines.push(`Reason: ${status.reason}`);
  }
  return lines.join("\n");
}

function updateEnvSummary(statusText) {
  if (!envEl) return;
  const modelProtocol = envProtocols.model || "unknown";
  const wasmProtocol = envProtocols.wasm || "unknown";
  envEl.textContent = `${statusText} · Assets: bundled · model: ${modelProtocol} · wasm: ${wasmProtocol}`;
}

function setWebGPUStatusDisplay(status) {
  const statusText = buildWebGPUStatusText(status);
  if (webgpuStatusEl) {
    const summary = getWebGPUStatusLabel(status.state, status);
    webgpuStatusEl.hidden = summary === "ready";
    webgpuStatusEl.textContent = statusText;
    webgpuStatusEl.classList.remove(...WEBGPU_STATUS_CLASSES);
    const className = WEBGPU_STATUS_STATES[status.state]?.className;
    if (className) {
      webgpuStatusEl.classList.add(className);
    }
    const details = buildWebGPUStatusDetails(status);
    webgpuStatusEl.title = details || statusText;
  }
  updateEnvSummary(statusText);
}

async function detectWebGPUStatus() {
  if (!globalThis.navigator?.gpu) {
    return { state: "unavailable", reason: "navigator.gpu missing" };
  }

  let adapter = null;
  try {
    adapter = await globalThis.navigator.gpu.requestAdapter();
  } catch (err) {
    return { state: "unavailable", reason: getErrorMessage(err) };
  }
  if (!adapter) {
    return { state: "unavailable", reason: "requestAdapter returned null" };
  }

  let adapterInfo = null;
  try {
    if (typeof adapter.requestAdapterInfo === "function") {
      adapterInfo = await adapter.requestAdapterInfo();
    } else if (adapter.info) {
      adapterInfo = adapter.info;
    }
  } catch (err) {
    adapterInfo = null;
  }

  const adapterDescription =
    adapterInfo?.description ||
    adapterInfo?.name ||
    adapterInfo?.vendor ||
    "";
  const featureCount = adapter.features?.size ?? 0;
  const missingFeatures = WEBGPU_REQUIRED_FEATURES.filter(
    (feature) => !adapter.features?.has?.(feature),
  );
  const state = missingFeatures.length ? "limited" : "available";
  return {
    state,
    adapterDescription,
    isFallbackAdapter: Boolean(adapter.isFallbackAdapter),
    missingFeatures,
    featureCount,
  };
}

async function refreshWebGPUStatus({ force = false } = {}) {
  if (webgpuStatusPromise) return webgpuStatusPromise;
  const now = Date.now();
  if (!force && now - lastWebGPUStatusAt < WEBGPU_STATUS_TTL_MS) {
    setWebGPUStatusDisplay(lastWebGPUStatus);
    return lastWebGPUStatus;
  }

  setWebGPUStatusDisplay({ state: "checking" });
  webgpuStatusPromise = (async () => {
    try {
      const status = await detectWebGPUStatus();
      lastWebGPUStatus = status;
      lastWebGPUStatusAt = Date.now();
      setWebGPUStatusDisplay(status);
      return status;
    } catch (err) {
      const fallback = { state: "error", reason: getErrorMessage(err) };
      lastWebGPUStatus = fallback;
      lastWebGPUStatusAt = Date.now();
      setWebGPUStatusDisplay(fallback);
      return fallback;
    } finally {
      webgpuStatusPromise = null;
    }
  })();

  return webgpuStatusPromise;
}

function normalizeLocalPreference(value) {
  return value === "qwen3" ? "qwen3" : "appleIntelligence";
}

function hasLocalAvailability() {
  return Boolean(autoAppleAvailability?.available) || Boolean(autoQwenEnabled);
}

function resolveExecutionBackendType(tokenEstimate) {
  const selection = String(nativeBackendSelection || "auto");
  if (selection === "byok") return "byok";
  if (selection === "local") {
    return hasLocalAvailability() ? "local" : "byok";
  }
  if (selection === "auto") {
    const threshold = Number(autoStrategyThreshold);
    const resolvedThreshold =
      Number.isFinite(threshold) && threshold > 0
        ? threshold
        : DEFAULT_AUTO_STRATEGY_THRESHOLD;
    const count = Number.isFinite(tokenEstimate) ? Number(tokenEstimate) : 0;
    const type = count <= resolvedThreshold ? "local" : "byok";
    return type === "local" && !hasLocalAvailability() ? "byok" : type;
  }
  return "byok";
}

function resolveLocalBackend() {
  const prefer = normalizeLocalPreference(autoLocalPreference);
  const appleAvailable = Boolean(autoAppleAvailability?.available);
  const qwenAvailable = Boolean(autoQwenEnabled);
  if (prefer === "appleIntelligence") {
    if (appleAvailable) return "apple";
    if (qwenAvailable) return "webllm";
  } else {
    if (qwenAvailable) return "webllm";
    if (appleAvailable) return "apple";
  }
  return null;
}

function resolveExecutionBackend(tokenEstimate) {
  const type = resolveExecutionBackendType(tokenEstimate);
  if (type === "byok") {
    return { type, backend: "byok", useFoundation: true };
  }
  const localBackend = resolveLocalBackend();
  if (localBackend === "apple") {
    return { type, backend: "apple", useFoundation: true };
  }
  if (localBackend === "webllm") {
    return { type, backend: "webllm", useFoundation: false };
  }
  return { type: "byok", backend: "byok", useFoundation: true };
}

function updateAiModelLabel(info) {
  if (!aiModelEl) return;
  if (info) {
    lastFoundationAvailability = info;
  }
  const resolved = resolveExecutionBackend(lastTokenEstimate);
  lastExecutionBackend = resolved.backend;
  if (resolved.backend === "byok") {
    const label = String(byokModelName ?? "").trim();
    aiModelEl.textContent = label || "BYOK";
    return;
  }
  if (resolved.backend === "apple") {
    aiModelEl.textContent = AI_MODEL_FM_LABEL;
    return;
  }
  aiModelEl.textContent = AI_MODEL_WEBLLM_LABEL;
}

function setProgressDotState(stateKey, { breathing } = {}) {
  if (!progressDotEl) return;
  const state = DOT_STATES[stateKey];
  if (!state) return;
  progressDotEl.classList.remove(
    ...DOT_STATE_CLASSES,
    "is-breathing",
    "progress-dot-breathe",
  );
  progressDotEl.classList.add(state.className);
  const shouldBreathe = typeof breathing === "boolean" ? breathing : state.breathing;
  if (shouldBreathe) {
    progressDotEl.classList.add("is-breathing");
  }
}

function applyStatusDotState(text, options = {}) {
  if (!progressDotEl || options.skipDot) return;
  const value = String(text ?? "");
  if (!value || STATUS_NO_DOT_CHANGE.has(value)) return;

  if (options.state) {
    setProgressDotState(options.state, options);
    return;
  }

  if (value === "Ready") {
    setProgressDotState("ready");
    return;
  }

  if (STATUS_ENGINE.has(value)) {
    setProgressDotState("engine");
    return;
  }
  if (
    STATUS_GENERATING.has(value) ||
    value.startsWith("Generating chunk ")
  ) {
    setProgressDotState("generating");
    return;
  }
  if (
    STATUS_LONGDOC.has(value) ||
    value.startsWith("Reading chunk ") ||
    value.startsWith("Context limit, retry ")
  ) {
    setProgressDotState("longdoc");
    return;
  }
  if (STATUS_READING.has(value) || value === NO_SUMMARY_TEXT_MESSAGE) {
    setProgressDotState("reading");
    return;
  }
  if (STATUS_STOPPED.has(value)) {
    setProgressDotState("stopped");
  }
}

function setStatus(text, progress, options) {
  let progressValue = progress;
  let opts = options;
  if (progress && typeof progress === "object") {
    opts = progress;
    progressValue = undefined;
  }
  statusEl.textContent = text;
  if (typeof progressValue === "number") {
    progressEl.value = Math.min(1, Math.max(0, progressValue));
  }
  applyStatusDotState(text, opts);
}

function setStatusError(value, progress) {
  const code = getErrorCode(value);
  const message = getErrorMessage(value);
  if (code && message && message !== code) {
    appendErrorMessageToOutput(message);
  }
  if (/webgpu|gpudevice|shader-f16/i.test(`${code} ${message}`)) {
    refreshWebGPUStatus({ force: true }).catch((err) => {
      console.warn("[WebLLM Demo] Failed to refresh WebGPU status:", err);
    });
  }
  const text =
    typeof value === "string" ? value : getStatusTextForError(value);
  setStatus(text, progress, { state: "error" });
}

function setOutput(text) {
  if (!outputEl) return;
  outputEl.classList.remove("rendered");
  outputEl.textContent = text;
}

function setModelOutputMarkdown(text) {
  lastModelOutputMarkdown = String(text ?? "");
  setOutput(lastModelOutputMarkdown);
}

function getMarkdownParser() {
  if (markdownParser) return markdownParser;

  const marked = globalThis.marked;
  if (!marked) return null;

  const parse =
    (typeof marked.parse === "function" && marked.parse.bind(marked)) ||
    (typeof marked.marked === "function" && marked.marked.bind(marked)) ||
    (typeof marked.marked?.parse === "function" &&
      marked.marked.parse.bind(marked.marked)) ||
    (typeof marked === "function" && marked.bind(marked));

  if (!parse) return null;

  const setOptions =
    (typeof marked.setOptions === "function" && marked.setOptions.bind(marked)) ||
    (typeof marked.options === "function" && marked.options.bind(marked)) ||
    (typeof marked.marked?.setOptions === "function" &&
      marked.marked.setOptions.bind(marked.marked)) ||
    (typeof marked.marked?.options === "function" &&
      marked.marked.options.bind(marked.marked));

  try {
    setOptions?.({
      gfm: true,
      breaks: true,
    });
  } catch {
    // ignore
  }

  markdownParser = parse;
  return markdownParser;
}

function isPossiblyDangerousUrl(url) {
  const value = String(url ?? "").trim().toLowerCase();
  if (!value) return false;
  return (
    value.startsWith("javascript:") ||
    value.startsWith("vbscript:") ||
    value.startsWith("data:text/html")
  );
}

function ensureAnchorSafe(anchorEl) {
  if (!anchorEl) return;
  const current = String(anchorEl.getAttribute("rel") ?? "");
  const parts = new Set(current.split(/\s+/).filter(Boolean));
  parts.add("noopener");
  parts.add("noreferrer");
  anchorEl.setAttribute("rel", Array.from(parts).join(" "));
  if (!anchorEl.getAttribute("target")) {
    anchorEl.setAttribute("target", "_blank");
  }
}

function sanitizeHtml(html) {
  const template = document.createElement("template");
  template.innerHTML = String(html ?? "");

  const disallowed = new Set([
    "SCRIPT",
    "STYLE",
    "IFRAME",
    "OBJECT",
    "EMBED",
    "LINK",
    "META",
    "BASE",
    "FORM",
    "INPUT",
    "BUTTON",
    "TEXTAREA",
    "SELECT",
    "OPTION",
  ]);

  for (const el of template.content.querySelectorAll("*")) {
    if (disallowed.has(el.tagName)) {
      el.remove();
      continue;
    }

    for (const attr of Array.from(el.attributes)) {
      const name = attr.name.toLowerCase();
      if (name.startsWith("on")) {
        el.removeAttribute(attr.name);
        continue;
      }
      if (name === "href" || name === "src" || name === "xlink:href") {
        if (isPossiblyDangerousUrl(attr.value)) {
          el.removeAttribute(attr.name);
        }
      }
    }

    if (el.tagName === "A") {
      ensureAnchorSafe(el);
    }
  }

  return template.innerHTML;
}

function renderModelOutputAsHtml() {
  if (!outputEl) return;
  const markdown = String(lastModelOutputMarkdown ?? "").trim();
  if (!markdown || markdown === NO_SUMMARY_TEXT_MESSAGE) return;

  const parse = getMarkdownParser();
  if (!parse) return;

  try {
    const html = parse(markdown);
    outputEl.classList.add("rendered");
    outputEl.innerHTML = sanitizeHtml(html);
  } catch (err) {
    console.warn("[WebLLM Demo] Failed to render markdown:", err);
  }
}

function setThink(text) {
  if (!thinkEl) return;
  thinkEl.textContent = text;
  try {
    thinkEl.scrollTop = thinkEl.scrollHeight;
  } catch {
    // ignore
  }
}

function setThinkBoxVisible(visible) {
  if (!thinkContainerEl) return;
  thinkContainerEl.hidden = !visible;
  if (!visible) setThink("");
}

function setShareVisible(_visible) {
  if (!shareEl) return;
  shareEl.hidden = false;
}

const THINK_OPEN_TAG = "<think>";
const THINK_CLOSE_TAG = "</think>";

function stripLeadingBlankLines(text) {
  return String(text ?? "").replace(/^(?:[ \t]*\r?\n)+/, "");
}

function stripTrailingWhitespace(text) {
  return String(text ?? "").replace(/\s+$/, "");
}

function splitModelThinking(rawText) {
  const raw = String(rawText ?? "");
  const openIndex = raw.indexOf(THINK_OPEN_TAG);
  if (openIndex === -1) {
    return { think: "", final: raw, hasThink: false, thinkClosed: true };
  }

  const afterOpen = openIndex + THINK_OPEN_TAG.length;
  const closeIndex = raw.indexOf(THINK_CLOSE_TAG, afterOpen);
  if (closeIndex === -1) {
    return {
      think: raw.slice(afterOpen),
      final: raw.slice(0, openIndex),
      hasThink: true,
      thinkClosed: false,
    };
  }

  const prefix = raw.slice(0, openIndex);
  const think = raw.slice(afterOpen, closeIndex);
  const final = prefix + raw.slice(closeIndex + THINK_CLOSE_TAG.length);
  return { think, final, hasThink: true, thinkClosed: true };
}

function renderModelOutput(rawText) {
  const { think, final } = splitModelThinking(rawText);
  setThink(stripTrailingWhitespace(stripLeadingBlankLines(think)));
  setModelOutputMarkdown(stripTrailingWhitespace(stripLeadingBlankLines(final)));
}

function getErrorMessage(err) {
  if (!err) return "";
  if (typeof err === "string") return err;
  if (typeof err?.message === "string") return err.message;
  try {
    return JSON.stringify(err);
  } catch {
    return String(err);
  }
}

function getErrorCode(err) {
  if (!err || typeof err !== "object") return "";
  const code = err.code ?? err.errorCode;
  return code ? String(code) : "";
}

function getStatusTextForError(err) {
  if (!err) return "";
  if (typeof err === "string") return err;
  const code = getErrorCode(err);
  if (code) return code;
  return getErrorMessage(err);
}

function appendErrorMessageToOutput(message) {
  if (!outputEl || !message) return;
  const existing = String(outputEl.textContent ?? "").trim();
  const separator = existing ? "\n\n" : "";
  outputEl.classList.remove("rendered");
  outputEl.textContent = `${existing}${separator}${message}`;
}

function isTokenizerDeletedBindingError(err) {
  const msg = getErrorMessage(err);
  return (
    msg.includes("Cannot pass deleted object as a pointer") &&
    (msg.includes("Tokenizer") || msg.includes("Tokenizer*"))
  );
}

function isDisposedObjectError(err) {
  return getErrorMessage(err).includes("has already been disposed");
}

let recoverPromise = null;

function hardResetEngineState() {
  generating = false;
  try {
    worker?.terminate();
  } catch (err) {
    console.warn("[WebLLM Demo] Failed to terminate worker:", err);
  }
  worker = null;
  engine = null;
  enableControls(false);
  stopButton.disabled = true;
  unloadButton.disabled = true;
}

async function recoverEngine(err) {
  if (recoverPromise) return recoverPromise;
  if (engineLoading) {
    console.warn("[WebLLM Demo] Skip recovery while engine is loading:", err);
    return;
  }

  recoverPromise = (async () => {
    console.warn("[WebLLM Demo] Recovering engine due to error:", err);
    setStatus("Engine crashed, restarting…", 0);
    hardResetEngineState();

    loadButton.disabled = true;
    modelSelect.disabled = true;
    try {
      await loadEngine(modelSelect.value);
    } finally {
      loadButton.disabled = false;
      modelSelect.disabled = false;
    }
  })();

  try {
    await recoverPromise;
  } finally {
    recoverPromise = null;
  }
}

const CJK_REGEX = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/gu;
const CJK_SINGLE_REGEX = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u;

let tokenEstimatorEncoding = DEFAULT_TOKEN_ESTIMATOR;
let longDocumentChunkTokenSize = DEFAULT_LONG_DOCUMENT_CHUNK_TOKEN_SIZE;
let longDocumentMaxChunks = DEFAULT_LONG_DOCUMENT_MAX_CHUNKS;
const tokenizerInstances = new Map();

function resolveTokenizer(encoding) {
  const key =
    TOKENIZER_GLOBALS[encoding] ??
    TOKENIZER_GLOBALS[DEFAULT_TOKEN_ESTIMATOR];
  if (tokenizerInstances.has(key)) {
    return tokenizerInstances.get(key);
  }
  const tokenizer = globalThis[key];
  if (!tokenizer) return null;
  tokenizerInstances.set(key, tokenizer);
  return tokenizer;
}

function getTokenizer() {
  return resolveTokenizer(tokenEstimatorEncoding);
}

function estimateTokensFromText(text) {
  const value = String(text ?? "");
  if (!value) return 0;

  const cjkCount = value.match(CJK_REGEX)?.length ?? 0;
  const nonCjkLength = value.replace(CJK_REGEX, "").length;
  const estimate = cjkCount + nonCjkLength / 4;
  return Math.max(1, Math.ceil(estimate));
}

function estimateTokensWithTokenizer(text) {
  const value = String(text ?? "");
  if (!value) return 0;
  const tokenizer = getTokenizer();
  if (!tokenizer) return estimateTokensFromText(value);
  try {
    if (typeof tokenizer.countTokens === "function") {
      return Number(tokenizer.countTokens(value)) || 0;
    }
    const tokens = tokenizer.encode(value);
    return Array.isArray(tokens) ? tokens.length : 0;
  } catch (err) {
    console.warn("[WebLLM Demo] Tokenizer failed, falling back:", err);
    return estimateTokensFromText(value);
  }
}

function getLongDocumentChunkTokenSize(totalTokens, { useFoundation } = {}) {
  const value = Number(totalTokens) || 0;
  if (value <= 0) return 1;
  return Math.max(1, longDocumentChunkTokenSize);
}

function getLongDocumentRoutingThreshold({ useFoundation } = {}) {
  return Math.max(1, DEFAULT_LONG_DOCUMENT_ROUTING_THRESHOLD);
}

function getAllowedChunkTokenSizes() {
  return Array.from(LONG_DOCUMENT_CHUNK_SIZE_OPTIONS).sort((a, b) => a - b);
}

function nextLowerChunkTokenSize(current, allowedSizes) {
  const currentValue = Number(current) || 0;
  if (currentValue <= 0) return null;
  const sorted = Array.isArray(allowedSizes)
    ? allowedSizes.filter((size) => Number.isFinite(size)).sort((a, b) => a - b)
    : [];
  if (!sorted.length) return null;
  let candidate = null;
  for (const size of sorted) {
    if (size < currentValue) candidate = size;
  }
  return candidate;
}

function isContextWindowExceededError(err) {
  const code =
    (err && typeof err === "object" && (err.code || err.errorCode)) || "";
  return code === "EXCEEDED_CONTEXT_WINDOW";
}

function chunkByEstimatedTokens(text, chunkTokenSize) {
  const value = String(text ?? "");
  if (!value || chunkTokenSize <= 0) {
    return { totalTokens: 0, chunks: [] };
  }

  const chunks = [];
  let buffer = "";
  let cjkCount = 0;
  let nonCjkCount = 0;
  let utf16Offset = 0;
  const maxChunks = Math.max(1, longDocumentMaxChunks);

  const flush = () => {
    if (!buffer) return true;
    if (chunks.length >= maxChunks) return false;
    const tokenCount = Math.max(1, Math.ceil(cjkCount + nonCjkCount / 4));
    const chunkLength = buffer.length;
    chunks.push({
      index: chunks.length,
      tokenCount,
      text: buffer,
      startUTF16: utf16Offset,
      endUTF16: utf16Offset + chunkLength,
    });
    utf16Offset += chunkLength;
    buffer = "";
    cjkCount = 0;
    nonCjkCount = 0;
    return chunks.length < maxChunks;
  };

  for (const char of value) {
    if (chunks.length >= maxChunks) break;
    buffer += char;
    if (CJK_SINGLE_REGEX.test(char)) {
      cjkCount += 1;
    } else {
      nonCjkCount += 1;
    }
    const estimatedTokens = Math.ceil(cjkCount + nonCjkCount / 4);
    if (estimatedTokens >= chunkTokenSize) {
      const canContinue = flush();
      if (!canContinue) break;
    }
  }

  if (chunks.length < maxChunks) {
    flush();
  }

  return { totalTokens: estimateTokensFromText(value), chunks };
}

function chunkByTokens(text, chunkTokenSize) {
  const value = String(text ?? "");
  if (!value || chunkTokenSize <= 0) {
    return { totalTokens: 0, chunks: [] };
  }

  const tokenizer = getTokenizer();
  if (!tokenizer) {
    return chunkByEstimatedTokens(value, chunkTokenSize);
  }

  const tokens = tokenizer.encode(value);
  if (!Array.isArray(tokens) || tokens.length === 0) {
    return { totalTokens: 0, chunks: [] };
  }

  const chunks = [];
  let utf16Offset = 0;
  const maxTokens = Math.max(1, chunkTokenSize) * Math.max(1, longDocumentMaxChunks);
  const limitedTokens = tokens.length > maxTokens ? tokens.slice(0, maxTokens) : tokens;

  for (let i = 0; i < limitedTokens.length; i += chunkTokenSize) {
    const slice = limitedTokens.slice(i, i + chunkTokenSize);
    let chunkText = "";
    try {
      chunkText = String(tokenizer.decode(slice) ?? "");
    } catch (err) {
      console.warn("[WebLLM Demo] Tokenizer decode failed, using empty chunk:", err);
      chunkText = "";
    }

    const chunkLength = chunkText.length;
    chunks.push({
      index: chunks.length,
      tokenCount: slice.length,
      text: chunkText,
      startUTF16: utf16Offset,
      endUTF16: utf16Offset + chunkLength,
    });
    utf16Offset += chunkLength;
  }

  return { totalTokens: tokens.length, chunks };
}

function estimateTokensForMessages(messages) {
  if (!Array.isArray(messages)) return 0;
  let total = 0;
  for (const msg of messages) {
    if (!msg) continue;
    const content = msg.content;
    if (typeof content === "string") {
      total += estimateTokensWithTokenizer(content);
    } else if (Array.isArray(content)) {
      for (const part of content) {
        if (part?.type === "text" && typeof part.text === "string") {
          total += estimateTokensWithTokenizer(part.text);
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
  setStatus(report.text, report.progress, { skipDot: true });
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
  return normalized.slice(0, limit) + "\n\n(Content too long, truncated)";
}

function truncateForVisibility(text) {
  const normalized = String(text ?? "").trim();
  if (!normalized) return "";
  if (normalized.length <= VISIBILITY_TEXT_LIMIT) return normalized;
  return normalized.slice(0, VISIBILITY_TEXT_LIMIT);
}

function resetOutputForVisibility() {
  setOutput("");
  lastModelOutputMarkdown = "";
}

function showVisibilityText(text) {
  resetOutputForVisibility();
  setOutput(text);
}

function showVisibilityPreview(text) {
  const preview = truncateForVisibility(text);
  if (!preview) return;
  showVisibilityText(preview);
}

function isThenable(value) {
  return Boolean(value) && typeof value.then === "function";
}

async function tabsQuery(queryInfo) {
  const fn = browser?.tabs?.query;
  if (typeof fn !== "function") {
    throw new Error("browser.tabs.query is unavailable");
  }

  try {
    const result = fn.call(browser.tabs, queryInfo);
    if (isThenable(result)) return await result;
  } catch {
    // fall back to callback style
  }

  return new Promise((resolve, reject) => {
    fn.call(browser.tabs, queryInfo, (tabs) => {
      const err = browser?.runtime?.lastError;
      if (err) {
        reject(new Error(err.message ? String(err.message) : String(err)));
        return;
      }
      resolve(tabs);
    });
  });
}

async function tabsSendMessage(tabId, message) {
  const fn = browser?.tabs?.sendMessage;
  if (typeof fn !== "function") {
    throw new Error("browser.tabs.sendMessage is unavailable");
  }

  try {
    const result = fn.call(browser.tabs, tabId, message);
    if (isThenable(result)) return await result;
  } catch {
    // fall back to callback style
  }

  return new Promise((resolve, reject) => {
    fn.call(browser.tabs, tabId, message, (resp) => {
      const err = browser?.runtime?.lastError;
      if (err) {
        reject(new Error(err.message ? String(err.message) : String(err)));
        return;
      }
      resolve(resp);
    });
  });
}

async function getActiveTab() {
  const primary = await tabsQuery({ active: true, currentWindow: true }).catch(() => null);
  if (Array.isArray(primary) && primary[0]) return primary[0];
  const fallback = await tabsQuery({ active: true }).catch(() => null);
  return Array.isArray(fallback) ? fallback[0] ?? null : null;
}

async function getArticleTextFromContentScript() {
  const tab = await getActiveTab();
  if (!tab?.id) throw new Error("No active tab found");
  logPopupEvent("getArticleText.start", { tabId: tab.id, url: tab.url ?? "" });
  const resp = await tabsSendMessage(tab.id, { command: "getArticleText" });

  if (!resp) {
    throw new Error("Content script did not respond");
  }

  if (typeof resp !== "object") {
    throw new Error(`Unexpected content script response: ${typeof resp}`);
  }

  const command = resp.command;
  if (command && command !== "articleTextResponse") {
    throw new Error(`Unexpected content script response command: ${String(command)}`);
  }

  if (resp.error) throw new Error(String(resp.error));

  const title = typeof resp.title === "string" ? resp.title : "";
  const body =
    typeof resp.body === "string"
      ? resp.body
      : typeof resp.text === "string"
      ? resp.text
      : "";
  logPopupEvent("getArticleText.response", {
    titleLength: title.length,
    bodyLength: body.length,
    command: resp.command ?? "articleTextResponse",
  });
  return { title, text: body, url: tab.url ?? "" };
}

function buildSummaryUserPrompt({ title, text, url }) {
  const clippedText = clampText(text, 8000);
  const resolvedTitle = title || "(no title)";
  const resolvedContent = clippedText || "(empty)";
  const template = summaryUserPromptTemplate || DEFAULT_SUMMARY_USER_PROMPT_TEMPLATE;
  const prompt = renderPromptTemplate(template, {
    title: resolvedTitle,
    content: resolvedContent,
  });
  logPopupEvent("buildSummaryUserPrompt", {
    titleLength: resolvedTitle.length,
    contentLength: String(text ?? "").length,
    clippedLength: resolvedContent.length,
    templateLength: String(template ?? "").length,
    resultLength: prompt.length,
  });
  return prompt;
}

function buildSummaryMessages({ title, text, url }) {
  const system = systemPrompt;
  const user = buildSummaryUserPrompt({ title, text, url });
  logPopupEvent("buildSummaryMessages", {
    systemPromptLength: String(system ?? "").length,
    userPromptLength: String(user ?? "").length,
  });

  return [
    { role: "system", content: system },
    { role: "user", content: user },
  ];
}

let engine = null;
let worker = null;
let generating = false;
let generationInterrupted = false;
let generationBackend = "webllm"; // "webllm" | "foundation-models"
let engineLoading = false;
let cachedUserPrompt = "";
let preparedMessagesForTokenEstimate = [];
let autoSummarizeStarted = false;
let autoSummarizeRunning = false;
let autoSummarizeQueued = false;
let activeModelIdOverride = "";
let foundationJobId = "";
let foundationCursor = 0;
let lastTokenEstimate = 0;
let lastChunkTokenSize = 0;
let lastRoutingThreshold = 0;
let lastReadingAnchors = [];
let lastSummarySystemPrompt = "";

const FOUNDATION_MODEL_ID = "foundation-models";
const FOUNDATION_POLL_INTERVAL_MS = 120;

modelSelect.appendChild(new Option(MODEL_ID, MODEL_ID));
modelSelect.value = MODEL_ID;

const demoModelUrl = new URL(
  `../webllm-assets/models/${MODEL_ID}/resolve/main/`,
  import.meta.url,
).href;
envProtocols.model = new URL(demoModelUrl).protocol;
envProtocols.wasm = new URL(WASM_URL).protocol;
setWebGPUStatusDisplay({
  state: hasWebGPU() ? "checking" : "unavailable",
  reason: hasWebGPU() ? "" : "navigator.gpu missing",
});
refreshWebGPUStatus({ force: true }).catch((err) => {
  console.warn("[WebLLM Demo] Failed to refresh WebGPU status:", err);
});
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) {
    refreshWebGPUStatus().catch((err) => {
      console.warn("[WebLLM Demo] Failed to refresh WebGPU status:", err);
    });
  }
});
console.log("[WebLLM Demo] modelUrl =", demoModelUrl);
console.log("[WebLLM Demo] wasmUrl  =", WASM_URL);
setShareVisible(false);
enableControls(false);
updateAiModelLabel();

function hasReadableBodyText(text) {
  return Boolean(String(text ?? "").trim());
}

const DEFAULT_SYSTEM_PROMPT =
  `Summarize the content as a short brief with key points.

Output requirements:
- Clear structured headings + bullet points
- No tables (including Markdown tables)
- Do not use the \`|\` character
`;

const DEFAULT_CHUNK_PROMPT =
  `You are a text organizer.

Your task is to help the user fully read very long content.

- Extract the key points from this article`;

const DEFAULT_SYSTEM_PROMPT_URL = new URL("../default_system_prompt.txt", import.meta.url);
const DEFAULT_CHUNK_PROMPT_URL = new URL("../default_chunk_prompt.txt", import.meta.url);
const SUMMARY_USER_PROMPT_TEMPLATE_URL = new URL("../summary_user_prompt.txt", import.meta.url);
const READING_ANCHOR_SYSTEM_SUFFIX_TEMPLATE_URL = new URL(
  "../reading_anchor_system_suffix.txt",
  import.meta.url,
);
const READING_ANCHOR_USER_PROMPT_TEMPLATE_URL = new URL(
  "../reading_anchor_user_prompt.txt",
  import.meta.url,
);
const READING_ANCHOR_SUMMARY_ITEM_TEMPLATE_URL = new URL(
  "../reading_anchor_summary_item.txt",
  import.meta.url,
);

const DEFAULT_SUMMARY_USER_PROMPT_TEMPLATE = "{{title}}\n\nCONTENT\n{{content}}";
const DEFAULT_READING_ANCHOR_SYSTEM_SUFFIX_TEMPLATE =
  "- This is a paragraph from the source (chunk {{chunk_index}} of {{chunk_total}})";
const DEFAULT_READING_ANCHOR_USER_PROMPT_TEMPLATE = "CONTENT\n{{content}}";
const DEFAULT_READING_ANCHOR_SUMMARY_ITEM_TEMPLATE = "Chunk {{chunk_index}}\n{{chunk_text}}";

const PROMPT_TEMPLATE_CACHE = new Map();
let summaryUserPromptTemplate = "";
let readingAnchorSystemSuffixTemplate = "";
let readingAnchorUserPromptTemplate = "";
let readingAnchorSummaryItemTemplate = "";

async function loadBundledPromptText(url, fallback = "") {
  const key = url?.href || String(url || "");
  if (PROMPT_TEMPLATE_CACHE.has(key)) {
    return PROMPT_TEMPLATE_CACHE.get(key);
  }
  let resolved = "";
  try {
    const resp = await fetch(url);
    const text = resp?.ok ? await resp.text() : "";
    resolved = String(text ?? "").trim();
  } catch {
    resolved = "";
  }
  const value = resolved || fallback;
  PROMPT_TEMPLATE_CACHE.set(key, value);
  return value;
}

async function getDefaultSystemPromptFallback() {
  return loadBundledPromptText(DEFAULT_SYSTEM_PROMPT_URL, DEFAULT_SYSTEM_PROMPT);
}

async function getDefaultChunkPromptFallback() {
  return loadBundledPromptText(DEFAULT_CHUNK_PROMPT_URL, DEFAULT_CHUNK_PROMPT);
}

async function refreshPromptTemplates() {
  summaryUserPromptTemplate = await loadBundledPromptText(
    SUMMARY_USER_PROMPT_TEMPLATE_URL,
    DEFAULT_SUMMARY_USER_PROMPT_TEMPLATE,
  );
  logTextSummary("summary user prompt template", summaryUserPromptTemplate);
  readingAnchorSystemSuffixTemplate = await loadBundledPromptText(
    READING_ANCHOR_SYSTEM_SUFFIX_TEMPLATE_URL,
    DEFAULT_READING_ANCHOR_SYSTEM_SUFFIX_TEMPLATE,
  );
  logTextSummary("reading anchor system suffix template", readingAnchorSystemSuffixTemplate);
  readingAnchorUserPromptTemplate = await loadBundledPromptText(
    READING_ANCHOR_USER_PROMPT_TEMPLATE_URL,
    DEFAULT_READING_ANCHOR_USER_PROMPT_TEMPLATE,
  );
  logTextSummary("reading anchor user prompt template", readingAnchorUserPromptTemplate);
  readingAnchorSummaryItemTemplate = await loadBundledPromptText(
    READING_ANCHOR_SUMMARY_ITEM_TEMPLATE_URL,
    DEFAULT_READING_ANCHOR_SUMMARY_ITEM_TEMPLATE,
  );
  logTextSummary("reading anchor summary item template", readingAnchorSummaryItemTemplate);
}

function renderPromptTemplate(template, values) {
  const normalized = String(template ?? "");
  return normalized.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, (match, key) => {
    if (!Object.prototype.hasOwnProperty.call(values, key)) return match;
    return String(values[key] ?? "");
  });
}

let systemPrompt = DEFAULT_SYSTEM_PROMPT;
let chunkPrompt = DEFAULT_CHUNK_PROMPT;

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitUntil(predicate, { timeoutMs = 8000, intervalMs = 50 } = {}) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (predicate()) return true;
    await delay(intervalMs);
  }
  return Boolean(predicate());
}

async function stopGenerationForRestart() {
  if (!generating) return true;

  if (generationBackend === "foundation-models") {
    generationInterrupted = true;
    if (foundationJobId) {
      await cancelFoundationModelsStream(foundationJobId);
    }
    setStatus("Stopping…");
    return waitUntil(() => !generating, { timeoutMs: 10000, intervalMs: 50 });
  }

  if (!engine) return true;
  try {
    generationInterrupted = true;
    engine.interruptGenerate();
    setStatus("Stopping…");
  } catch (err) {
    if (isTokenizerDeletedBindingError(err) || isDisposedObjectError(err)) {
      setStatus("Engine crashed, restarting…", 0);
      await recoverEngine(err);
      return true;
    }
    setStatusError(err);
    return false;
  }

  return waitUntil(() => !generating, { timeoutMs: 10000, intervalMs: 50 });
}

async function refreshSystemPromptFromNative() {
  if (typeof browser?.runtime?.sendNativeMessage !== "function") {
    systemPrompt = await getDefaultSystemPromptFallback();
    logPopupEvent("systemPrompt.fallback", { reason: "native messaging unavailable" });
    logTextSummary("system prompt", systemPrompt);
    return systemPrompt;
  }

  try {
    const resp = await browser.runtime.sendNativeMessage({
      v: 1,
      command: "getSystemPrompt",
    });

    const prompt =
      resp?.payload?.prompt ??
      resp?.prompt ??
      resp?.echo?.payload?.prompt ??
      resp?.echo?.prompt;

    if (typeof prompt === "string" && prompt.trim()) {
      systemPrompt = prompt;
      logPopupEvent("systemPrompt.loaded", { source: "native" });
    } else {
      systemPrompt = await getDefaultSystemPromptFallback();
      logPopupEvent("systemPrompt.fallback", { reason: "empty native prompt" });
    }
  } catch (err) {
    systemPrompt = await getDefaultSystemPromptFallback();
    console.warn("[WebLLM Demo] Failed to load system prompt from native:", err);
    logPopupEvent("systemPrompt.fallback", { reason: "native error", error: getErrorMessage(err) });
  }

  logTextSummary("system prompt", systemPrompt);
  return systemPrompt;
}

async function refreshChunkPromptFromNative() {
  if (typeof browser?.runtime?.sendNativeMessage !== "function") {
    chunkPrompt = await getDefaultChunkPromptFallback();
    logPopupEvent("chunkPrompt.fallback", { reason: "native messaging unavailable" });
    logTextSummary("chunk prompt", chunkPrompt);
    return chunkPrompt;
  }

  try {
    const resp = await browser.runtime.sendNativeMessage({
      v: 1,
      command: "getChunkPrompt",
    });

    const prompt =
      resp?.payload?.prompt ??
      resp?.prompt ??
      resp?.echo?.payload?.prompt ??
      resp?.echo?.prompt;

    if (typeof prompt === "string" && prompt.trim()) {
      chunkPrompt = prompt;
      logPopupEvent("chunkPrompt.loaded", { source: "native" });
    } else {
      chunkPrompt = await getDefaultChunkPromptFallback();
      logPopupEvent("chunkPrompt.fallback", { reason: "empty native prompt" });
    }
  } catch (err) {
    chunkPrompt = await getDefaultChunkPromptFallback();
    console.warn("[WebLLM Demo] Failed to load chunk prompt from native:", err);
    logPopupEvent("chunkPrompt.fallback", { reason: "native error", error: getErrorMessage(err) });
  }

  logTextSummary("chunk prompt", chunkPrompt);
  return chunkPrompt;
}

async function refreshTokenEstimatorFromNative() {
  if (typeof browser?.runtime?.sendNativeMessage !== "function") {
    tokenEstimatorEncoding = DEFAULT_TOKEN_ESTIMATOR;
    logPopupEvent("tokenEstimator.fallback", { reason: "native messaging unavailable" });
    return tokenEstimatorEncoding;
  }

  try {
    const resp = await browser.runtime.sendNativeMessage({
      v: 1,
      command: "getTokenEstimatorEncoding",
    });

    const encoding =
      resp?.payload?.encoding ??
      resp?.encoding ??
      resp?.echo?.payload?.encoding ??
      resp?.echo?.encoding;

    if (typeof encoding === "string" && TOKENIZER_GLOBALS[encoding]) {
      tokenEstimatorEncoding = encoding;
    } else {
      tokenEstimatorEncoding = DEFAULT_TOKEN_ESTIMATOR;
    }
    logPopupEvent("tokenEstimator.loaded", { encoding: tokenEstimatorEncoding });
  } catch (err) {
    tokenEstimatorEncoding = DEFAULT_TOKEN_ESTIMATOR;
    console.warn("[WebLLM Demo] Failed to load token estimator from native:", err);
    logPopupEvent("tokenEstimator.fallback", { reason: "native error", error: getErrorMessage(err) });
  }

  return tokenEstimatorEncoding;
}

async function refreshLongDocumentChunkTokenSizeFromNative() {
  if (typeof browser?.runtime?.sendNativeMessage !== "function") {
    longDocumentChunkTokenSize = DEFAULT_LONG_DOCUMENT_CHUNK_TOKEN_SIZE;
    logPopupEvent("longDocChunkSize.fallback", { reason: "native messaging unavailable" });
    return longDocumentChunkTokenSize;
  }

  try {
    const resp = await browser.runtime.sendNativeMessage({
      v: 1,
      command: "getLongDocumentChunkTokenSize",
    });

    const chunkSizeRaw =
      resp?.payload?.chunkTokenSize ??
      resp?.chunkTokenSize ??
      resp?.echo?.payload?.chunkTokenSize ??
      resp?.echo?.chunkTokenSize;
    const chunkSize = Number(chunkSizeRaw);
    if (Number.isFinite(chunkSize) && LONG_DOCUMENT_CHUNK_SIZE_OPTIONS.has(chunkSize)) {
      longDocumentChunkTokenSize = chunkSize;
    } else {
      longDocumentChunkTokenSize = DEFAULT_LONG_DOCUMENT_CHUNK_TOKEN_SIZE;
    }
    logPopupEvent("longDocChunkSize.loaded", { chunkTokenSize: longDocumentChunkTokenSize });
  } catch (err) {
    longDocumentChunkTokenSize = DEFAULT_LONG_DOCUMENT_CHUNK_TOKEN_SIZE;
    console.warn(
      "[WebLLM Demo] Failed to load long document chunk size from native:",
      err,
    );
    logPopupEvent("longDocChunkSize.fallback", { reason: "native error", error: getErrorMessage(err) });
  }

  return longDocumentChunkTokenSize;
}

async function refreshLongDocumentMaxChunksFromNative() {
  if (typeof browser?.runtime?.sendNativeMessage !== "function") {
    longDocumentMaxChunks = DEFAULT_LONG_DOCUMENT_MAX_CHUNKS;
    logPopupEvent("longDocMaxChunks.fallback", { reason: "native messaging unavailable" });
    return longDocumentMaxChunks;
  }

  try {
    const resp = await browser.runtime.sendNativeMessage({
      v: 1,
      command: "getLongDocumentMaxChunks",
    });

    const maxChunksRaw =
      resp?.payload?.maxChunks ??
      resp?.maxChunks ??
      resp?.echo?.payload?.maxChunks ??
      resp?.echo?.maxChunks;
    const maxChunks = Number(maxChunksRaw);
    if (Number.isFinite(maxChunks) && LONG_DOCUMENT_MAX_CHUNK_OPTIONS.has(maxChunks)) {
      longDocumentMaxChunks = maxChunks;
    } else {
      longDocumentMaxChunks = DEFAULT_LONG_DOCUMENT_MAX_CHUNKS;
    }
    logPopupEvent("longDocMaxChunks.loaded", { maxChunks: longDocumentMaxChunks });
  } catch (err) {
    longDocumentMaxChunks = DEFAULT_LONG_DOCUMENT_MAX_CHUNKS;
    console.warn("[WebLLM Demo] Failed to load long document max chunks from native:", err);
    logPopupEvent("longDocMaxChunks.fallback", { reason: "native error", error: getErrorMessage(err) });
  }

  return longDocumentMaxChunks;
}

async function refreshByokSettingsFromNative({ log = false } = {}) {
  if (typeof browser?.runtime?.sendNativeMessage !== "function") {
    return;
  }

  try {
    const [backendResp, byokResp, autoResp] = await Promise.all([
      browser.runtime.sendNativeMessage({ v: 1, command: "getGenerationBackend" }),
      browser.runtime.sendNativeMessage({ v: 1, command: "getBYOKSettings" }),
      browser.runtime.sendNativeMessage({ v: 1, command: "getAutoStrategySettings" }),
    ]);

    const backendPayload =
      backendResp?.payload ??
      backendResp?.echo?.payload ??
      backendResp;
    let backend = backendPayload?.backend ? String(backendPayload.backend) : "unknown";
    if (backend === "mlc" || backend === "apple") {
      backend = "local";
    }
    nativeBackendSelection = backend;

    const byokPayload =
      byokResp?.payload ??
      byokResp?.echo?.payload ??
      byokResp;

    const provider = byokPayload?.provider ? String(byokPayload.provider) : "";
    const apiURL = byokPayload?.apiURL ? String(byokPayload.apiURL) : "";
    const model = byokPayload?.model ? String(byokPayload.model) : "";
    const apiKey = byokPayload?.apiKey ? String(byokPayload.apiKey) : "";

    const autoPayload =
      autoResp?.payload ??
      autoResp?.echo?.payload ??
      autoResp;
    const autoThresholdRaw =
      autoPayload?.strategyThreshold ??
      autoPayload?.threshold;
    const autoThreshold = Number(autoThresholdRaw);
    const autoPreferenceRaw =
      typeof autoPayload?.localPreference === "string"
        ? autoPayload.localPreference
        : typeof autoPayload?.preference === "string"
          ? autoPayload.preference
          : "";
    const autoQwenRaw = autoPayload?.qwenEnabled;
    const autoApplePayload = autoPayload?.appleAvailability;

    byokModelName = String(model ?? "").trim();
    autoStrategyThreshold =
      Number.isFinite(autoThreshold) && [2600].includes(autoThreshold)
        ? autoThreshold
        : DEFAULT_AUTO_STRATEGY_THRESHOLD;
    autoLocalPreference = normalizeLocalPreference(autoPreferenceRaw);
    autoQwenEnabled = Boolean(autoQwenRaw);
    autoAppleAvailability =
      autoApplePayload && typeof autoApplePayload === "object"
        ? autoApplePayload
        : null;

    if (log) {
      console.log("[WebLLM Demo] generation backend =", backend);
      console.log("[WebLLM Demo] BYOK HTTP config =", {
        provider,
        apiURL,
        model,
        hasApiKey: Boolean(apiKey),
      });
      console.log("[WebLLM Demo] Auto strategy settings =", {
        strategyThreshold: autoStrategyThreshold,
        localPreference: autoLocalPreference,
        qwenEnabled: autoQwenEnabled,
        appleAvailability: autoAppleAvailability,
      });
    }

    updateAiModelLabel();
  } catch (err) {
    console.warn("[WebLLM Demo] Failed to load BYOK settings from native:", err);
  }
}

async function logByokSettingsFromNative() {
  await refreshByokSettingsFromNative({ log: true });
}
async function checkFoundationModelsAvailabilityFromNative({ backend } = {}) {
  if (typeof browser?.runtime?.sendNativeMessage !== "function") {
    return { enabled: false, available: false, reason: "native messaging unavailable" };
  }

  try {
    const resp = await browser.runtime.sendNativeMessage({
      v: 1,
      command: "fm.checkAvailability",
      payload: backend ? { backend: String(backend) } : undefined,
    });

    const payload =
      resp?.payload ??
      resp?.echo?.payload ??
      resp;

    if (resp?.type === "error") {
      const msg = typeof payload?.message === "string" ? payload.message : "native error";
      return { enabled: false, available: false, reason: msg };
    }

    return {
      enabled: Boolean(payload?.enabled),
      available: Boolean(payload?.available),
      reason: typeof payload?.reason === "string" ? payload.reason : "",
    };
  } catch (err) {
    return {
      enabled: false,
      available: false,
      reason: err?.message ? String(err.message) : String(err),
    };
  }
}

async function shouldUseFoundationModels({ tokenEstimate } = {}) {
  await refreshByokSettingsFromNative();
  const resolved = resolveExecutionBackend(tokenEstimate ?? lastTokenEstimate);
  if (resolved.backend === "webllm") {
    updateAiModelLabel();
    return false;
  }
  const info = await checkFoundationModelsAvailabilityFromNative({
    backend: resolved.backend,
  });
  updateAiModelLabel(info);
  return Boolean(info.enabled && info.available);
}

async function prewarmFoundationModels({
  systemPrompt,
  promptPrefix,
  tokenEstimate,
  backend,
}) {
  const resp = await browser.runtime.sendNativeMessage({
    v: 1,
    command: "fm.prewarm",
    payload: {
      systemPrompt: String(systemPrompt ?? ""),
      promptPrefix: String(promptPrefix ?? ""),
      tokenEstimate: Number.isFinite(tokenEstimate) ? Number(tokenEstimate) : 0,
      backend: backend ? String(backend) : "",
    },
  });

  const payload = resp?.payload ?? resp;
  if (resp?.type === "error") {
    const msg = typeof payload?.message === "string" ? payload.message : "native prewarm failed";
    const err = new Error(msg);
    const code = typeof payload?.code === "string" ? payload.code : "";
    if (code) {
      err.code = code;
    }
    throw err;
  }

  return { ok: Boolean(payload?.ok) };
}

async function startFoundationModelsStream({
  systemPrompt,
  userPrompt,
  tokenEstimate,
  backend,
}) {
  const resp = await browser.runtime.sendNativeMessage({
    v: 1,
    command: "fm.stream.start",
    payload: {
      systemPrompt: String(systemPrompt ?? ""),
      userPrompt: String(userPrompt ?? ""),
      tokenEstimate: Number.isFinite(tokenEstimate) ? Number(tokenEstimate) : 0,
      backend: backend ? String(backend) : "",
      options: {
        temperature: 0.4,
        maximumResponseTokens: MAX_OUTPUT_TOKENS,
      },
    },
  });

  const payload = resp?.payload ?? resp;
  if (resp?.type === "error") {
    const msg = typeof payload?.message === "string" ? payload.message : "native start failed";
    const err = new Error(msg);
    const code = typeof payload?.code === "string" ? payload.code : "";
    if (code) {
      err.code = code;
    }
    throw err;
  }
  const jobId = payload?.jobId ? String(payload.jobId) : "";
  const cursor = Number.isFinite(payload?.cursor) ? Number(payload.cursor) : 0;
  if (!jobId) throw new Error("Missing jobId from native stream.start");
  return { jobId, cursor };
}

async function pollFoundationModelsStream({ jobId, cursor }) {
  const resp = await browser.runtime.sendNativeMessage({
    v: 1,
    command: "fm.stream.poll",
    payload: {
      jobId: String(jobId ?? ""),
      cursor: Number.isFinite(cursor) ? cursor : 0,
    },
  });

  const payload = resp?.payload ?? resp;
  if (resp?.type === "error") {
    const msg = typeof payload?.message === "string" ? payload.message : "native poll failed";
    const err = new Error(msg);
    const code = typeof payload?.code === "string" ? payload.code : "";
    if (code) {
      err.code = code;
    }
    throw err;
  }
  return {
    delta: typeof payload?.delta === "string" ? payload.delta : "",
    cursor: Number.isFinite(payload?.cursor) ? Number(payload.cursor) : 0,
    done: Boolean(payload?.done),
    error: typeof payload?.error === "string" ? payload.error : "",
    errorCode: typeof payload?.errorCode === "string" ? payload.errorCode : "",
  };
}

async function cancelFoundationModelsStream(jobId) {
  try {
    await browser.runtime.sendNativeMessage({
      v: 1,
      command: "fm.stream.cancel",
      payload: { jobId: String(jobId ?? "") },
    });
  } catch (err) {
    console.warn("[WebLLM Demo] fm.stream.cancel failed:", err);
  }
}

async function saveRawHistoryItem({ title, text, url }) {
  if (typeof browser?.runtime?.sendNativeMessage !== "function") return null;

  const summaryText = String(lastModelOutputMarkdown ?? "").trim();
  if (!summaryText || summaryText === NO_SUMMARY_TEXT_MESSAGE) return null;
  if (generationInterrupted) return null;

  const payload = {
    url: String(url ?? ""),
    title: String(title ?? ""),
    articleText: String(text ?? ""),
    summaryText,
    systemPrompt: String(lastSummarySystemPrompt || systemPrompt || ""),
    userPrompt: String(cachedUserPrompt || buildSummaryUserPrompt({ title, text, url }) || ""),
    modelId: String(activeModelIdOverride || modelSelect?.value || MODEL_ID),
    readingAnchors: Array.isArray(lastReadingAnchors) ? lastReadingAnchors : [],
    tokenEstimate: Number(lastTokenEstimate) || 0,
    tokenEstimator: tokenEstimatorEncoding,
    chunkTokenSize:
      lastReadingAnchors?.length && lastChunkTokenSize > 0
        ? lastChunkTokenSize
        : undefined,
    routingThreshold:
      lastReadingAnchors?.length && lastRoutingThreshold > 0
        ? lastRoutingThreshold
        : getLongDocumentRoutingThreshold(),
    isLongDocument: Boolean(lastReadingAnchors?.length),
  };

  try {
    const resp = await browser.runtime.sendNativeMessage({
      v: 1,
      command: "saveRawItem",
      payload,
    });
    console.log("[WebLLM Demo] Saved raw history item:", resp);
    return resp;
  } catch (err) {
    console.warn("[WebLLM Demo] Failed to save raw history item:", err);
    return null;
  }
}

async function prepareSummaryContext() {
  try {
    const ctx = await getArticleTextFromContentScript();
    const normalized = {
      title: String(ctx.title ?? "").trim(),
      text: String(ctx.text ?? "").trim(),
      url: String(ctx.url ?? "").trim(),
    };
    logPopupEvent("prepareSummaryContext.normalized", {
      titleLength: normalized.title.length,
      textLength: normalized.text.length,
      url: normalized.url,
    });

    if (!hasReadableBodyText(normalized.text)) {
      cachedUserPrompt = "";
      preparedMessagesForTokenEstimate = [];
      setInputTokenEstimate(0);
      return null;
    }

    await refreshPromptTemplates();
    await refreshTokenEstimatorFromNative();
    await refreshByokSettingsFromNative();
    await refreshLongDocumentChunkTokenSizeFromNative();
    lastTokenEstimate = estimateTokensWithTokenizer(normalized.text);
    setInputTokenEstimate(lastTokenEstimate);

    cachedUserPrompt = buildSummaryUserPrompt(normalized);
    preparedMessagesForTokenEstimate = buildSummaryMessages(normalized);
    logPopupEvent("prepareSummaryContext.ready", {
      tokenEstimate: lastTokenEstimate,
      cachedUserPromptLength: cachedUserPrompt.length,
    });
    return { ...normalized, tokenEstimate: lastTokenEstimate };
  } catch (err) {
    cachedUserPrompt = "";
    preparedMessagesForTokenEstimate = [];
    setInputTokenEstimate(0);
    console.warn("[WebLLM Demo] Failed to prepare summary context:", err);
    return null;
  }
}

async function prepareSummaryContextWithRetry({ retries = 1, retryDelayMs = 250 } = {}) {
  let ctx = await prepareSummaryContext();
  for (let attempt = 0; attempt < retries && !ctx; attempt += 1) {
    await delay(retryDelayMs);
    ctx = await prepareSummaryContext();
  }
  return ctx;
}

function installWorkerCrashHandlers(currentWorker) {
  currentWorker.addEventListener("error", (event) => {
    const err = event?.error ?? new Error(event?.message ?? "Worker error");
    console.warn("[WebLLM Demo] Worker error:", err);
    if (engineLoading) return;
    recoverEngine(err).catch((recoverErr) => {
      console.warn("[WebLLM Demo] Failed to recover after worker error:", recoverErr);
    });
  });

  currentWorker.addEventListener("messageerror", (event) => {
    console.warn("[WebLLM Demo] Worker messageerror:", event);
    if (engineLoading) return;
    recoverEngine(new Error("Worker messageerror")).catch((recoverErr) => {
      console.warn("[WebLLM Demo] Failed to recover after worker messageerror:", recoverErr);
    });
  });
}

async function loadEngine(modelId) {
  if (!hasWebGPU()) {
    throw new Error("WebGPU is unavailable in this environment.");
  }

  if (engineLoading) {
    throw new Error("Engine is already loading.");
  }

  engineLoading = true;
  setStatus("Creating worker…", 0);
  worker?.terminate();
  try {
    worker = new Worker(new URL("./worker.js", import.meta.url), {
      type: "module",
    });
  } catch (err) {
    engineLoading = false;
    throw new Error(
      `Worker init failed: ${err?.message ? String(err.message) : String(err)}`,
    );
  }

  installWorkerCrashHandlers(worker);

  try {
    setStatus("Loading model…", 0);
    engine = await CreateWebWorkerMLCEngine(worker, modelId, {
      initProgressCallback,
      appConfig: getLocalAppConfig(modelId),
    });

    enableControls(true);
    setStatus("Ready", 1);
  } catch (err) {
    engine = null;
    worker?.terminate();
    worker = null;
    enableControls(false);
    throw err;
  } finally {
    engineLoading = false;
  }
}

async function unloadEngine() {
  generating = false;
  stopButton.disabled = true;
  runButton.disabled = true;
  summarizeButton.disabled = true;

  try {
    await engine?.unload?.();
  } catch (err) {
    console.warn("[WebLLM Demo] engine.unload failed (ignored):", err);
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
  if (engineLoading) throw new Error("Engine is still loading.");
  if (generating) throw new Error("Generation is already running.");

  setThinkBoxVisible(true);
  generationBackend = "webllm";
  activeModelIdOverride = "";

  preparedMessagesForTokenEstimate = messages;
  setInputTokenEstimate(estimateTokensForMessages(preparedMessagesForTokenEstimate));

  generationInterrupted = false;
  generating = true;
  runButton.disabled = true;
  summarizeButton.disabled = true;
  stopButton.disabled = false;
  loadButton.disabled = true;
  unloadButton.disabled = true;
  modelSelect.disabled = true;
  setStatus("Generating…");
  setShareVisible(false);
  setThink("");
  setOutput("");
  lastModelOutputMarkdown = "";

  let acc = "";
  let completed = false;
  try {
    await engine.resetChat();
    const completion = await engine.chat.completions.create({
      stream: true,
      stream_options: { include_usage: true },
      messages,
      temperature: 0.4,
      max_tokens: MAX_OUTPUT_TOKENS,
      extra_body: { enable_thinking: true },
    });

    for await (const chunk of completion) {
      const delta = chunk?.choices?.[0]?.delta?.content ?? "";
      if (delta) {
        acc += delta;
        renderModelOutput(acc);
      }
    }
    completed = true;
  } finally {
    generating = false;
    stopButton.disabled = true;
    runButton.disabled = false;
    summarizeButton.disabled = false;
    loadButton.disabled = false;
    unloadButton.disabled = !engine;
    modelSelect.disabled = false;
    setStatus("Ready", 1);
    if (completed && !generationInterrupted) {
      const markdown = String(lastModelOutputMarkdown ?? "").trim();
      renderModelOutputAsHtml();
      setShareVisible(Boolean(markdown) && markdown !== NO_SUMMARY_TEXT_MESSAGE);
    }
  }
}

async function streamChatWithRecovery(messages, { retry = true } = {}) {
  try {
    await streamChat(messages);
  } catch (err) {
    if (retry && (isTokenizerDeletedBindingError(err) || isDisposedObjectError(err))) {
      setStatus("Engine crashed, restarting…", 0);
      await recoverEngine(err);
      return streamChatWithRecovery(messages, { retry: false });
    }
    throw err;
  }
}

async function ensureWebLLMEngineLoaded() {
  if (engine) return;
  loadButton.disabled = true;
  modelSelect.disabled = true;
  setShareVisible(false);
  setThink("");
  setOutput("");
  try {
    await loadEngine(modelSelect.value);
  } finally {
    loadButton.disabled = false;
    modelSelect.disabled = false;
  }
}

async function generateTextWithWebLLM(messages, { renderOutput = false } = {}) {
  if (!engine) throw new Error("Engine is not loaded.");
  if (engineLoading) throw new Error("Engine is still loading.");

  let acc = "";
  await engine.resetChat();
  const completion = await engine.chat.completions.create({
    stream: true,
    stream_options: { include_usage: true },
    messages,
    temperature: 0.4,
    max_tokens: MAX_OUTPUT_TOKENS,
    extra_body: { enable_thinking: true },
  });

  for await (const chunk of completion) {
    if (generationInterrupted) break;
    const delta = chunk?.choices?.[0]?.delta?.content ?? "";
    if (!delta) continue;
    acc += delta;
    if (renderOutput) {
      renderModelOutput(acc);
    }
  }
  return acc;
}

async function generateTextWithFoundationModels({
  systemPrompt,
  userPrompt,
  renderOutput = false,
  tokenEstimate,
}) {
  const prewarmPrefix = String(userPrompt ?? "").slice(0, FOUNDATION_PREWARM_PREFIX_LIMIT);
  const resolved = resolveExecutionBackend(tokenEstimate ?? lastTokenEstimate);
  const backend = resolved.backend === "webllm" ? "" : resolved.backend;
  try {
    await prewarmFoundationModels({
      systemPrompt,
      promptPrefix: prewarmPrefix,
      tokenEstimate,
      backend,
    });
  } catch (err) {
    console.warn("[WebLLM Demo] fm.prewarm failed:", err);
  }

  const started = await startFoundationModelsStream({
    systemPrompt,
    userPrompt,
    tokenEstimate,
    backend,
  });

  foundationJobId = started.jobId;
  foundationCursor = started.cursor || 0;

  let acc = "";
  while (!generationInterrupted) {
    const polled = await pollFoundationModelsStream({
      jobId: foundationJobId,
      cursor: foundationCursor,
    });

    if (polled.error) {
      const err = new Error(polled.error);
      if (polled.errorCode) {
        err.code = polled.errorCode;
      }
      throw err;
    }

    if (polled.delta) {
      acc += polled.delta;
      if (renderOutput) {
        renderModelOutput(acc);
      }
    }

    foundationCursor = polled.cursor || foundationCursor;
    if (polled.done) {
      break;
    }

    await delay(FOUNDATION_POLL_INTERVAL_MS);
  }

  return acc;
}

function buildReadingAnchorSystemPrompt({ index, total }) {
  const base = String(chunkPrompt ?? "").trim();
  const suffixTemplate =
    readingAnchorSystemSuffixTemplate || DEFAULT_READING_ANCHOR_SYSTEM_SUFFIX_TEMPLATE;
  const dynamicLine = renderPromptTemplate(suffixTemplate, {
    chunk_index: index,
    chunk_total: total,
  });
  if (!base) return dynamicLine;
  return [base, "", dynamicLine].join("\n");
}

function buildReadingAnchorUserPrompt(text) {
  const trimmed = String(text ?? "").trim();
  const template =
    readingAnchorUserPromptTemplate || DEFAULT_READING_ANCHOR_USER_PROMPT_TEMPLATE;
  return renderPromptTemplate(template, {
    content: trimmed || "(empty)",
  });
}

function buildSummaryUserPromptFromAnchors(anchors) {
  if (!anchors?.length) return "(empty)";
  const template =
    readingAnchorSummaryItemTemplate || DEFAULT_READING_ANCHOR_SUMMARY_ITEM_TEMPLATE;
  return anchors
    .map((anchor) =>
      renderPromptTemplate(template, {
        chunk_index: anchor.index + 1,
        chunk_text: anchor.text,
      }).trim(),
    )
    .join("\\n\\n");
}

async function runLongDocumentPipelineOnce(ctx, { useFoundation, totalTokens, chunkTokenSize }) {
  logPopupEvent("longDoc.runOnce.start", {
    useFoundation,
    totalTokens,
    chunkTokenSize,
  });
  const resolvedChunkTokenSize = Math.max(1, Number(chunkTokenSize) || 1);
  lastChunkTokenSize = resolvedChunkTokenSize;
  lastRoutingThreshold = getLongDocumentRoutingThreshold();

  // Step 1: Split the source text into token-sized chunks for per-part reading.
  const chunkInfo = chunkByTokens(ctx.text, resolvedChunkTokenSize);
  const chunks = chunkInfo.chunks.map((chunk) => ({
    index: Number(chunk.index) || 0,
    tokenCount: Number(chunk.tokenCount) || 0,
    text: String(chunk.text ?? ""),
    startUTF16: Number(chunk.startUTF16) || 0,
    endUTF16: Number(chunk.endUTF16) || 0,
  }));
  if (!chunks.length) {
    throw new Error("Chunking returned no chunks.");
  }

  lastReadingAnchors = [];

  // Step 2: For each chunk, ask the model to produce a short "reading anchor".
  for (const chunk of chunks) {
    if (generationInterrupted) break;
    const chunkText = String(chunk.text ?? "");
    console.log(
      `[WebLLM Demo] Chunk ${chunk.index + 1}/${chunks.length} token count: ${chunk.tokenCount}`,
    );
    console.log(
      `[WebLLM Demo] Chunk ${chunk.index + 1}/${chunks.length} text:\\n${chunkText}`,
    );
    setStatus(`Reading chunk ${chunk.index + 1}/${chunks.length}…`, 0);
    showVisibilityPreview(chunkText);

    const systemPrompt = buildReadingAnchorSystemPrompt({
      index: chunk.index + 1,
      total: chunks.length,
    });
    const userPrompt = buildReadingAnchorUserPrompt(chunkText);

    setStatus(`Generating chunk ${chunk.index + 1}/${chunks.length}…`, 0);
    resetOutputForVisibility();
    setThink("");

    const anchorText = useFoundation
      ? await generateTextWithFoundationModels({
          systemPrompt,
          userPrompt,
          renderOutput: true,
          tokenEstimate: totalTokens,
        })
      : await generateTextWithWebLLM(
          [
            { role: "system", content: systemPrompt },
            { role: "user", content: userPrompt },
          ],
          { renderOutput: true },
        );

    const cleanedAnchor = (() => {
      const { final } = splitModelThinking(anchorText);
      return stripTrailingWhitespace(stripLeadingBlankLines(final));
    })();

    // Keep anchors so the final summary can use them instead of the full text.
    lastReadingAnchors.push({
      index: chunk.index,
      tokenCount: chunk.tokenCount,
      text: String(cleanedAnchor ?? "").trim(),
      startUTF16: chunk.startUTF16,
      endUTF16: chunk.endUTF16,
    });
  }

  if (generationInterrupted) {
    return "";
  }

  // Step 3: Feed the anchors back into the model to generate the final summary.
  setStatus("Generating summary…", 0);
  resetOutputForVisibility();
  setThink("");
  const summaryUserPrompt = buildSummaryUserPromptFromAnchors(lastReadingAnchors);
  const summarySystemPrompt = await getDefaultSystemPromptFallback();
  lastSummarySystemPrompt = summarySystemPrompt;
  cachedUserPrompt = summaryUserPrompt;

  const summaryText = useFoundation
    ? await generateTextWithFoundationModels({
        systemPrompt: summarySystemPrompt,
        userPrompt: summaryUserPrompt,
        renderOutput: true,
        tokenEstimate: totalTokens,
      })
    : await generateTextWithWebLLM(
        [
          { role: "system", content: summarySystemPrompt },
          { role: "user", content: summaryUserPrompt },
        ],
        { renderOutput: true },
      );

  lastTokenEstimate = Number(totalTokens) || 0;
  return summaryText;
}

async function runLongDocumentPipeline(ctx) {
  // Decide backend first; WebLLM needs engine warm-up while Foundation Models does not.
  const totalTokens = Number(ctx.tokenEstimate ?? lastTokenEstimate) || 0;
  const useFoundation = await shouldUseFoundationModels({ tokenEstimate: totalTokens });
  await refreshPromptTemplates();
  await refreshTokenEstimatorFromNative();
  await refreshLongDocumentChunkTokenSizeFromNative();
  await refreshLongDocumentMaxChunksFromNative();
  logPopupEvent("longDoc.pipeline.start", {
    useFoundation,
    totalTokens,
    chunkTokenSize: longDocumentChunkTokenSize,
    maxChunks: longDocumentMaxChunks,
  });

  if (!useFoundation) {
    await ensureWebLLMEngineLoaded();
  }

  // Reset UI + state before long-document processing starts.
  generationBackend = useFoundation ? "foundation-models" : "webllm";
  activeModelIdOverride = useFoundation ? FOUNDATION_MODEL_ID : "";
  generationInterrupted = false;
  generating = true;
  runButton.disabled = true;
  summarizeButton.disabled = true;
  stopButton.disabled = false;
  loadButton.disabled = true;
  unloadButton.disabled = true;
  modelSelect.disabled = true;
  setStatus("Preparing long document…", 0);
  setShareVisible(false);
  setThinkBoxVisible(!useFoundation);
  setThink("");
  lastModelOutputMarkdown = "";

  let summaryText = "";
  try {
    let chunkTokenSize = getLongDocumentChunkTokenSize(totalTokens);
    const allowedChunkSizes = getAllowedChunkTokenSizes();

    while (true) {
      try {
        summaryText = await runLongDocumentPipelineOnce(ctx, {
          useFoundation,
          totalTokens,
          chunkTokenSize,
        });
        break;
      } catch (err) {
        if (!useFoundation || !isContextWindowExceededError(err)) {
          throw err;
        }

        const nextChunkTokenSize = nextLowerChunkTokenSize(
          chunkTokenSize,
          allowedChunkSizes,
        );
        if (!nextChunkTokenSize) {
          throw err;
        }

        console.warn(
          `[WebLLM Demo] Context window exceeded. Retrying with chunk size ${nextChunkTokenSize} (was ${chunkTokenSize}).`,
        );

        if (foundationJobId) {
          await cancelFoundationModelsStream(foundationJobId);
        }
        foundationJobId = "";
        foundationCursor = 0;
        cachedUserPrompt = "";
        lastModelOutputMarkdown = "";
        lastReadingAnchors = [];
        lastChunkTokenSize = 0;
        lastRoutingThreshold = 0;
        lastSummarySystemPrompt = "";

        setStatus(`Context limit, retry ${nextChunkTokenSize}…`, 0);
        resetOutputForVisibility();
        setThink("");
        setShareVisible(false);

        chunkTokenSize = nextChunkTokenSize;
      }
    }
  } finally {
    if (generationInterrupted && generationBackend === "foundation-models" && foundationJobId) {
      await cancelFoundationModelsStream(foundationJobId);
    }

    foundationJobId = "";
    foundationCursor = 0;
    generating = false;
    stopButton.disabled = true;
    runButton.disabled = false;
    summarizeButton.disabled = false;
    loadButton.disabled = false;
    unloadButton.disabled = !engine;
    modelSelect.disabled = false;
    setStatus("Ready", 1);

    if (!generationInterrupted) {
      const markdown = String(lastModelOutputMarkdown ?? "").trim();
      renderModelOutputAsHtml();
      setShareVisible(Boolean(markdown) && markdown !== NO_SUMMARY_TEXT_MESSAGE);
    }
  }

  return summaryText;
}

async function streamSummaryWithFoundationModels(ctx) {
  if (generating) throw new Error("Generation is already running.");

  setThinkBoxVisible(false);
  generationBackend = "foundation-models";
  activeModelIdOverride = FOUNDATION_MODEL_ID;
  lastSummarySystemPrompt = systemPrompt;

  preparedMessagesForTokenEstimate = buildSummaryMessages(ctx);
  setInputTokenEstimate(estimateTokensForMessages(preparedMessagesForTokenEstimate));

  const tokenEstimate = Number(ctx.tokenEstimate ?? lastTokenEstimate) || 0;
  const resolved = resolveExecutionBackend(tokenEstimate);
  const backend = resolved.backend === "webllm" ? "" : resolved.backend;

  generationInterrupted = false;
  generating = true;
  runButton.disabled = true;
  summarizeButton.disabled = true;
  stopButton.disabled = false;
  loadButton.disabled = true;
  unloadButton.disabled = true;
  modelSelect.disabled = true;
  setStatus("Generating…");
  setShareVisible(false);
  setThink("");
  setOutput("");
  lastModelOutputMarkdown = "";

  cachedUserPrompt = buildSummaryUserPrompt(ctx);

  let acc = "";
  let completed = false;
  try {
    const prewarmPrefix = String(cachedUserPrompt ?? "").slice(0, FOUNDATION_PREWARM_PREFIX_LIMIT);
    try {
      await prewarmFoundationModels({
        systemPrompt,
        promptPrefix: prewarmPrefix,
        tokenEstimate,
        backend,
      });
    } catch (err) {
      console.warn("[WebLLM Demo] fm.prewarm failed:", err);
    }

    setStatus("Starting native…", 0);
    const started = await startFoundationModelsStream({
      systemPrompt,
      userPrompt: cachedUserPrompt,
      tokenEstimate,
      backend,
    });

    foundationJobId = started.jobId;
    foundationCursor = started.cursor || 0;

    setStatus("Generating…", 0);
    while (!generationInterrupted) {
    const polled = await pollFoundationModelsStream({
      jobId: foundationJobId,
      cursor: foundationCursor,
    });

    if (polled.error) {
      const err = new Error(polled.error);
      if (polled.errorCode) {
        err.code = polled.errorCode;
      }
      throw err;
    }

      if (polled.delta) {
        acc += polled.delta;
        renderModelOutput(acc);
      }

      foundationCursor = polled.cursor || foundationCursor;
      if (polled.done) {
        completed = true;
        break;
      }

      await delay(FOUNDATION_POLL_INTERVAL_MS);
    }
  } finally {
    if (generationInterrupted && foundationJobId) {
      await cancelFoundationModelsStream(foundationJobId);
    }

    foundationJobId = "";
    foundationCursor = 0;
    generating = false;
    stopButton.disabled = true;
    runButton.disabled = false;
    summarizeButton.disabled = false;
    loadButton.disabled = false;
    unloadButton.disabled = !engine;
    modelSelect.disabled = false;
    setStatus("Ready", 1);

    if (completed && !generationInterrupted) {
      const markdown = String(lastModelOutputMarkdown ?? "").trim();
      renderModelOutputAsHtml();
      setShareVisible(Boolean(markdown) && markdown !== NO_SUMMARY_TEXT_MESSAGE);
    }
  }
}

async function autoSummarizeActiveTab({ force = false, restart = false } = {}) {
  logPopupEvent("autoSummarize.start", {
    force,
    restart,
    autoSummarizeRunning,
    autoSummarizeStarted,
    autoSummarizeQueued,
  });
  if (autoSummarizeRunning) {
    if (force || restart) {
      autoSummarizeQueued = true;
      if (restart) {
        stopGenerationForRestart().catch((err) => {
          console.warn("[WebLLM Demo] stopGenerationForRestart failed:", err);
        });
      }
    }
    return;
  }

  if (autoSummarizeStarted && !force) return;
  autoSummarizeStarted = true;
  autoSummarizeRunning = true;
  autoSummarizeQueued = false;

  try {
    if (restart) {
      const stopped = await stopGenerationForRestart();
      if (!stopped) return;
    }

    loadButton.disabled = true;
    modelSelect.disabled = true;
    await refreshSystemPromptFromNative();
    await refreshChunkPromptFromNative();
    setStatus("Reading page…", 0);
    setShareVisible(false);
    setThink("");
    setOutput("");

    const ctx = await prepareSummaryContextWithRetry();
    if (!ctx) {
      setStatus(NO_SUMMARY_TEXT_MESSAGE, 0);
      setShareVisible(false);
      setThink("");
      setOutput(NO_SUMMARY_TEXT_MESSAGE);
      return;
    }

    lastReadingAnchors = [];
    lastChunkTokenSize = 0;
    lastRoutingThreshold = 0;
    lastSummarySystemPrompt = "";
    showVisibilityPreview(ctx.text);
    const tokenEstimate = Number(ctx.tokenEstimate ?? lastTokenEstimate) || 0;
    const useFoundation = await shouldUseFoundationModels({ tokenEstimate });
    const executionType = resolveExecutionBackendType(tokenEstimate);
    await refreshLongDocumentChunkTokenSizeFromNative();
    logPopupEvent("autoSummarize.decision", {
      tokenEstimate,
      useFoundation,
      executionType,
      routingThreshold: getLongDocumentRoutingThreshold(),
    });
    if (executionType === "local" && tokenEstimate > getLongDocumentRoutingThreshold()) {
      await runLongDocumentPipeline(ctx);
      await saveRawHistoryItem(ctx);
      return;
    }

    try {
      if (useFoundation) {
        try {
          await streamSummaryWithFoundationModels(ctx);
        } catch (err) {
          console.warn("[WebLLM Demo] Foundation Models failed, falling back to WebLLM:", err);
          setStatus("Native failed, fallback…", 0);
          activeModelIdOverride = "";
          if (!engine) {
            loadButton.disabled = true;
            modelSelect.disabled = true;
            setShareVisible(false);
            setThink("");
            setOutput("");
            try {
              await loadEngine(modelSelect.value);
            } catch (loadErr) {
              setStatusError(loadErr, 0);
              enableControls(false);
              return;
            } finally {
              loadButton.disabled = false;
              modelSelect.disabled = false;
            }
          }
          lastSummarySystemPrompt = systemPrompt;
          await streamChatWithRecovery(buildSummaryMessages(ctx));
        }
      } else {
        activeModelIdOverride = "";
        if (!engine) {
          loadButton.disabled = true;
          modelSelect.disabled = true;
          setShareVisible(false);
          setThink("");
          setOutput("");
          try {
            await loadEngine(modelSelect.value);
          } catch (err) {
            setStatusError(err, 0);
            enableControls(false);
            return;
          } finally {
            loadButton.disabled = false;
            modelSelect.disabled = false;
          }
        }
        lastSummarySystemPrompt = systemPrompt;
        await streamChatWithRecovery(buildSummaryMessages(ctx));
      }
      await saveRawHistoryItem(ctx);
    } catch (err) {
      setStatusError(err);
    }
  } finally {
    autoSummarizeRunning = false;
    loadButton.disabled = false;
    modelSelect.disabled = false;

    if (autoSummarizeQueued) {
      autoSummarizeQueued = false;
      autoSummarizeActiveTab({ force: true }).catch((err) => {
        console.warn("[WebLLM Demo] autoSummarizeActiveTab queued run failed:", err);
        setStatusError(err);
      });
    }
  }
}

loadButton.addEventListener("click", async () => {
  loadButton.disabled = true;
  modelSelect.disabled = true;
  setShareVisible(false);
  setThink("");
  setOutput("");
  try {
    await loadEngine(modelSelect.value);
  } catch (err) {
    setStatusError(err, 0);
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

clearButton.addEventListener("click", () => {
  setShareVisible(false);
  setThink("");
  setOutput("");
  lastModelOutputMarkdown = "";
});

stopButton.addEventListener("click", async () => {
  if (!generating) return;
  if (generationBackend === "foundation-models") {
    generationInterrupted = true;
    setStatus("Stopping…");
    if (foundationJobId) {
      await cancelFoundationModelsStream(foundationJobId);
    }
    return;
  }
  if (!engine) return;
  try {
    generationInterrupted = true;
    engine.interruptGenerate();
    setStatus("Stopping…");
  } catch (err) {
    if (isTokenizerDeletedBindingError(err) || isDisposedObjectError(err)) {
      setStatus("Engine crashed, restarting…", 0);
      await recoverEngine(err);
      return;
    }
    setStatusError(err);
  }
});

copySystemButton?.addEventListener("click", async () => {
  try {
    await refreshSystemPromptFromNative();
    logPopupEvent("copySystemPrompt", { length: systemPrompt.length });
    await copyToClipboard(systemPrompt);
    setStatus("System prompt copied");
  } catch (err) {
    setShareVisible(false);
    setThink("");
    setOutput(systemPrompt);
    setStatus("Clipboard unavailable, content shown.");
  }
});

copyUserButton?.addEventListener("click", async () => {
  if (!cachedUserPrompt) {
    copyUserButton.disabled = true;
    try {
      setStatus("Preparing prompt…");
      await refreshSystemPromptFromNative();
      const ctx = await prepareSummaryContextWithRetry();
      if (!ctx) {
        setStatus(NO_SUMMARY_TEXT_MESSAGE, 0);
        setShareVisible(false);
        setThink("");
        setOutput(NO_SUMMARY_TEXT_MESSAGE);
        return;
      }
      logPopupEvent("copyUserPrompt.prepared", {
        cachedUserPromptLength: cachedUserPrompt.length,
        tokenEstimate: lastTokenEstimate,
      });
      setStatus("User prompt ready (click again to copy)", 1);
    } finally {
      copyUserButton.disabled = false;
    }
    return;
  }

  try {
    logPopupEvent("copyUserPrompt.copy", { length: cachedUserPrompt.length });
    await copyToClipboard(cachedUserPrompt);
    setStatus("User prompt copied");
  } catch (err) {
    setShareVisible(false);
    setThink("");
    setOutput(cachedUserPrompt);
    setStatus("Clipboard unavailable, content shown.");
  }
});

runButton.addEventListener("click", async () => {
  try {
    const prompt = inputEl.value.trim();
    if (!prompt) {
      setStatus("Enter a prompt first");
      return;
    }
    preparedMessagesForTokenEstimate = [{ role: "user", content: prompt }];
    setInputTokenEstimate(estimateTokensForMessages(preparedMessagesForTokenEstimate));
    await streamChatWithRecovery([{ role: "user", content: prompt }]);
  } catch (err) {
    setStatusError(err);
  }
});

inputEl.addEventListener("input", () => {
  const prompt = inputEl.value.trim();
  if (prompt) {
    setInputTokenEstimate(estimateTokensWithTokenizer(prompt));
  } else if (preparedMessagesForTokenEstimate.length) {
    setInputTokenEstimate(estimateTokensForMessages(preparedMessagesForTokenEstimate));
  } else {
    setInputTokenEstimate(0);
  }
});

summarizeButton.addEventListener("click", async () => {
  try {
    await refreshSystemPromptFromNative();
    await refreshChunkPromptFromNative();
    setStatus("Reading page…", 0);
    const ctx = await prepareSummaryContextWithRetry();
    if (!ctx) {
      setStatus(NO_SUMMARY_TEXT_MESSAGE, 0);
      setShareVisible(false);
      setThink("");
      setOutput(NO_SUMMARY_TEXT_MESSAGE);
      return;
    }
    lastReadingAnchors = [];
    lastChunkTokenSize = 0;
    lastRoutingThreshold = 0;
    lastSummarySystemPrompt = "";
    showVisibilityPreview(ctx.text);
    const tokenEstimate = Number(ctx.tokenEstimate ?? lastTokenEstimate) || 0;
    const useFoundation = await shouldUseFoundationModels({ tokenEstimate });
    const executionType = resolveExecutionBackendType(tokenEstimate);
    logPopupEvent("summarize.decision", {
      tokenEstimate,
      useFoundation,
      executionType,
      routingThreshold: getLongDocumentRoutingThreshold(),
    });
    if (executionType === "local" && tokenEstimate > getLongDocumentRoutingThreshold()) {
      await runLongDocumentPipeline(ctx);
      await saveRawHistoryItem(ctx);
      return;
    }
    if (useFoundation) {
      try {
        await streamSummaryWithFoundationModels(ctx);
      } catch (err) {
        console.warn("[WebLLM Demo] Foundation Models failed, falling back to WebLLM:", err);
        setStatus("Native failed, fallback…", 0);
        activeModelIdOverride = "";
        if (!engine) {
          loadButton.disabled = true;
          modelSelect.disabled = true;
          setShareVisible(false);
          setThink("");
          setOutput("");
          try {
            await loadEngine(modelSelect.value);
          } finally {
            loadButton.disabled = false;
            modelSelect.disabled = false;
          }
        }
        lastSummarySystemPrompt = systemPrompt;
        await streamChatWithRecovery(buildSummaryMessages(ctx));
      }
    } else {
      activeModelIdOverride = "";
      if (!engine) {
        loadButton.disabled = true;
        modelSelect.disabled = true;
        setShareVisible(false);
        setThink("");
        setOutput("");
        try {
          await loadEngine(modelSelect.value);
        } finally {
          loadButton.disabled = false;
          modelSelect.disabled = false;
        }
      }
      lastSummarySystemPrompt = systemPrompt;
      await streamChatWithRecovery(buildSummaryMessages(ctx));
    }
    await saveRawHistoryItem(ctx);
  } catch (err) {
    setStatusError(err);
  }
});

shareEl?.addEventListener("click", async (event) => {
  event.preventDefault();
  if (generating) return;

  const text = String(outputEl?.textContent ?? "").trim();
  if (!text || text === NO_SUMMARY_TEXT_MESSAGE) {
    setStatus("Nothing to share", 1);
    return;
  }

  try {
    const tab = await getActiveTab().catch(() => null);
    const url = tab?.url ? String(tab.url) : "";
    const httpUrl = url && url.startsWith("http") ? url : "";
    const shareText = httpUrl ? `${text}\n\n${httpUrl}` : text;

    if (typeof globalThis.navigator?.share === "function") {
      const shareData = { text: shareText };
      // if (httpUrl) shareData.url = httpUrl;
      // Cannot pass URL; it causes the text to disappear.
      try {
        await globalThis.navigator.share(shareData);
      } catch {
        // Ignore share cancellations / platform rejections.
      }
      return;
    }

    await copyToClipboard(shareText);
    setStatus("Summary and link copied", 1);
  } catch (err) {
    setStatusError(err);
  }
});

statusEl.addEventListener("click", () => {
  autoSummarizeActiveTab({ force: true, restart: true }).catch((err) => {
    console.warn("[WebLLM Demo] status click autoSummarizeActiveTab failed:", err);
    setStatusError(err);
  });
});

statusEl.addEventListener("keydown", (event) => {
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    statusEl.click();
  }
});

globalThis.addEventListener("unhandledrejection", (event) => {
  const err = event?.reason;
  if (!isTokenizerDeletedBindingError(err) && !isDisposedObjectError(err)) return;
  console.warn("[WebLLM Demo] Unhandled engine error:", err);
  event?.preventDefault?.();
  recoverEngine(err).catch((recoverErr) => {
    console.warn(
      "[WebLLM Demo] Failed to recover after unhandled rejection:",
      recoverErr,
    );
  });
});

globalThis.addEventListener("error", (event) => {
  const err = event?.error ?? event?.message;
  if (!isTokenizerDeletedBindingError(err) && !isDisposedObjectError(err)) return;
  console.warn("[WebLLM Demo] Engine error:", err);
  recoverEngine(err).catch((recoverErr) => {
    console.warn("[WebLLM Demo] Failed to recover after error event:", recoverErr);
  });
});

autoSummarizeActiveTab().catch((err) => {
  console.warn("[WebLLM Demo] autoSummarizeActiveTab failed:", err);
  setStatusError(err);
});

logByokSettingsFromNative();
