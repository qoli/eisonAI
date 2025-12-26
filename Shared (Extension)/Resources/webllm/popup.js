import { CreateWebWorkerMLCEngine } from "./webllm.js";

const browser = globalThis.browser ?? globalThis.chrome;

const MODEL_ID = "Qwen3-0.6B-q4f16_1-MLC";
const MAX_OUTPUT_TOKENS = 1500;
const FOUNDATION_PREWARM_PREFIX_LIMIT = 1200;
const NO_SUMMARY_TEXT_MESSAGE = "無可用總結正文";
const LONG_DOCUMENT_TOKEN_THRESHOLD = 3200;
const LONG_DOCUMENT_CHUNK_TOKEN_SIZE = 3000;
const MAX_LONG_DOCUMENT_CHUNKS = 5;
const DEFAULT_TOKEN_ESTIMATOR = "cl100k_base";
const TOKENIZER_GLOBALS = {
  cl100k_base: "GPTTokenizer_cl100k_base",
  o200k_base: "GPTTokenizer_o200k_base",
  p50k_base: "GPTTokenizer_p50k_base",
  r50k_base: "GPTTokenizer_r50k_base",
};
const VISIBILITY_TEXT_LIMIT = 600;
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
const thinkEl = document.getElementById("think");
const thinkContainerEl = thinkEl?.closest?.(".container") ?? null;
const outputEl = document.getElementById("output");
const shareEl = document.getElementById("share");

let lastModelOutputMarkdown = "";
let markdownParser = null;

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

function getLongDocumentChunkTokenSize(totalTokens) {
  const value = Number(totalTokens) || 0;
  if (value <= 0) return 1;
  return Math.max(1, LONG_DOCUMENT_CHUNK_TOKEN_SIZE);
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
  const maxChunks = Math.max(1, MAX_LONG_DOCUMENT_CHUNKS);

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
  const maxTokens = Math.max(1, chunkTokenSize) * Math.max(1, MAX_LONG_DOCUMENT_CHUNKS);
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
  return { title, text: body, url: tab.url ?? "" };
}

function buildSummaryUserPrompt({ title, text, url }) {
  const clippedText = clampText(text, 8000);
  return [
    `${title || "(no title)"}`,
    `【正文】\n${clippedText || "(empty)"}`,
  ].join("\n\n");
}

function buildSummaryMessages({ title, text, url }) {
  const system = systemPrompt;
  const user = buildSummaryUserPrompt({ title, text, url });

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
envEl.textContent = `WebGPU: ${hasWebGPU() ? "available" : "unavailable"} · Assets: bundled · model: ${new URL(demoModelUrl).protocol} · wasm: ${new URL(WASM_URL).protocol}`;
console.log("[WebLLM Demo] modelUrl =", demoModelUrl);
console.log("[WebLLM Demo] wasmUrl  =", WASM_URL);
setShareVisible(false);
enableControls(false);

function hasReadableBodyText(text) {
  return Boolean(String(text ?? "").trim());
}

const DEFAULT_SYSTEM_PROMPT =
  `將內容整理為簡短簡報，包含重點摘要。

輸出要求：
- 合適的格式結構
- 使用繁體中文。`;

const DEFAULT_CHUNK_PROMPT =
  `你是一個文字整理員。

你目前的任務是，正在協助用戶完整閱讀超長內容。

- 擷取此文章的關鍵點`;

const DEFAULT_SYSTEM_PROMPT_URL = new URL("../default_system_prompt.txt", import.meta.url);
let bundledDefaultSystemPrompt = null;

async function loadBundledDefaultSystemPrompt() {
  if (typeof bundledDefaultSystemPrompt === "string") return bundledDefaultSystemPrompt;
  try {
    const resp = await fetch(DEFAULT_SYSTEM_PROMPT_URL);
    const text = resp?.ok ? await resp.text() : "";
    bundledDefaultSystemPrompt = String(text ?? "").trim();
  } catch {
    bundledDefaultSystemPrompt = "";
  }
  return bundledDefaultSystemPrompt;
}

async function getDefaultSystemPromptFallback() {
  const bundled = await loadBundledDefaultSystemPrompt();
  return bundled || DEFAULT_SYSTEM_PROMPT;
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
    setStatus(err?.message ? String(err.message) : String(err));
    return false;
  }

  return waitUntil(() => !generating, { timeoutMs: 10000, intervalMs: 50 });
}

async function refreshSystemPromptFromNative() {
  if (typeof browser?.runtime?.sendNativeMessage !== "function") {
    systemPrompt = await getDefaultSystemPromptFallback();
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
    } else {
      systemPrompt = await getDefaultSystemPromptFallback();
    }
  } catch (err) {
    systemPrompt = await getDefaultSystemPromptFallback();
    console.warn("[WebLLM Demo] Failed to load system prompt from native:", err);
  }

  return systemPrompt;
}

async function refreshChunkPromptFromNative() {
  if (typeof browser?.runtime?.sendNativeMessage !== "function") {
    chunkPrompt = DEFAULT_CHUNK_PROMPT;
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
    } else {
      chunkPrompt = DEFAULT_CHUNK_PROMPT;
    }
  } catch (err) {
    chunkPrompt = DEFAULT_CHUNK_PROMPT;
    console.warn("[WebLLM Demo] Failed to load chunk prompt from native:", err);
  }

  return chunkPrompt;
}

async function refreshTokenEstimatorFromNative() {
  if (typeof browser?.runtime?.sendNativeMessage !== "function") {
    tokenEstimatorEncoding = DEFAULT_TOKEN_ESTIMATOR;
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
  } catch (err) {
    tokenEstimatorEncoding = DEFAULT_TOKEN_ESTIMATOR;
    console.warn("[WebLLM Demo] Failed to load token estimator from native:", err);
  }

  return tokenEstimatorEncoding;
}
async function checkFoundationModelsAvailabilityFromNative() {
  if (typeof browser?.runtime?.sendNativeMessage !== "function") {
    return { enabled: false, available: false, reason: "native messaging unavailable" };
  }

  try {
    const resp = await browser.runtime.sendNativeMessage({
      v: 1,
      command: "fm.checkAvailability",
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

async function shouldUseFoundationModels() {
  const info = await checkFoundationModelsAvailabilityFromNative();
  return Boolean(info.enabled && info.available);
}

async function prewarmFoundationModels({ systemPrompt, promptPrefix }) {
  const resp = await browser.runtime.sendNativeMessage({
    v: 1,
    command: "fm.prewarm",
    payload: {
      systemPrompt: String(systemPrompt ?? ""),
      promptPrefix: String(promptPrefix ?? ""),
    },
  });

  const payload = resp?.payload ?? resp;
  if (resp?.type === "error") {
    const msg = typeof payload?.message === "string" ? payload.message : "native prewarm failed";
    throw new Error(msg);
  }

  return { ok: Boolean(payload?.ok) };
}

async function startFoundationModelsStream({ systemPrompt, userPrompt }) {
  const resp = await browser.runtime.sendNativeMessage({
    v: 1,
    command: "fm.stream.start",
    payload: {
      systemPrompt: String(systemPrompt ?? ""),
      userPrompt: String(userPrompt ?? ""),
      options: {
        temperature: 0.4,
        maximumResponseTokens: MAX_OUTPUT_TOKENS,
      },
    },
  });

  const payload = resp?.payload ?? resp;
  if (resp?.type === "error") {
    const msg = typeof payload?.message === "string" ? payload.message : "native start failed";
    throw new Error(msg);
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
    throw new Error(msg);
  }
  return {
    delta: typeof payload?.delta === "string" ? payload.delta : "",
    cursor: Number.isFinite(payload?.cursor) ? Number(payload.cursor) : 0,
    done: Boolean(payload?.done),
    error: typeof payload?.error === "string" ? payload.error : "",
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
    routingThreshold: LONG_DOCUMENT_TOKEN_THRESHOLD,
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

    if (!hasReadableBodyText(normalized.text)) {
      cachedUserPrompt = "";
      preparedMessagesForTokenEstimate = [];
      setInputTokenEstimate(0);
      return null;
    }

    await refreshTokenEstimatorFromNative();
    lastTokenEstimate = estimateTokensWithTokenizer(normalized.text);
    setInputTokenEstimate(lastTokenEstimate);

    cachedUserPrompt = buildSummaryUserPrompt(normalized);
    preparedMessagesForTokenEstimate = buildSummaryMessages(normalized);
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

async function generateTextWithFoundationModels({ systemPrompt, userPrompt, renderOutput = false }) {
  const prewarmPrefix = String(userPrompt ?? "").slice(0, FOUNDATION_PREWARM_PREFIX_LIMIT);
  try {
    await prewarmFoundationModels({ systemPrompt, promptPrefix: prewarmPrefix });
  } catch (err) {
    console.warn("[WebLLM Demo] fm.prewarm failed:", err);
  }

  const started = await startFoundationModelsStream({
    systemPrompt,
    userPrompt,
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
      throw new Error(polled.error);
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
  const dynamicLine = `- 當前這是原文中的一個段落（chunks ${index} of ${total}）`;
  if (!base) return dynamicLine;
  return [base, "", dynamicLine].join("\n");
}

function buildReadingAnchorUserPrompt(text) {
  const trimmed = String(text ?? "").trim();
  return `【正文】\\n${trimmed || "(empty)"}`;
}

function buildSummaryUserPromptFromAnchors(anchors) {
  if (!anchors?.length) return "(empty)";
  return anchors
    .map((anchor) => `Chunk ${anchor.index + 1}\\n${anchor.text}`.trim())
    .join("\\n\\n");
}

async function runLongDocumentPipeline(ctx) {
  // Decide backend first; WebLLM needs engine warm-up while Foundation Models does not.
  const useFoundation = await shouldUseFoundationModels();
  await refreshTokenEstimatorFromNative();
  const totalTokens = Number(ctx.tokenEstimate ?? lastTokenEstimate) || 0;

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
    // Step 1: Split the source text into token-sized chunks for per-part reading.
    const chunkTokenSize = getLongDocumentChunkTokenSize(totalTokens);
    lastChunkTokenSize = chunkTokenSize;
    const chunkInfo = chunkByTokens(ctx.text, chunkTokenSize);
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
    lastChunkTokenSize = 0;

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

    summaryText = useFoundation
      ? await generateTextWithFoundationModels({
          systemPrompt: summarySystemPrompt,
          userPrompt: summaryUserPrompt,
          renderOutput: true,
        })
      : await generateTextWithWebLLM(
          [
            { role: "system", content: summarySystemPrompt },
            { role: "user", content: summaryUserPrompt },
          ],
          { renderOutput: true },
        );

    lastTokenEstimate = totalTokens;
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
      await prewarmFoundationModels({ systemPrompt, promptPrefix: prewarmPrefix });
    } catch (err) {
      console.warn("[WebLLM Demo] fm.prewarm failed:", err);
    }

    setStatus("Starting native stream…", 0);
    const started = await startFoundationModelsStream({
      systemPrompt,
      userPrompt: cachedUserPrompt,
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
        throw new Error(polled.error);
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
    lastSummarySystemPrompt = "";
    showVisibilityPreview(ctx.text);
    const tokenEstimate = Number(ctx.tokenEstimate ?? lastTokenEstimate) || 0;
    if (tokenEstimate > LONG_DOCUMENT_TOKEN_THRESHOLD) {
      await runLongDocumentPipeline(ctx);
      await saveRawHistoryItem(ctx);
      return;
    }

    try {
      if (await shouldUseFoundationModels()) {
        try {
          await streamSummaryWithFoundationModels(ctx);
        } catch (err) {
          console.warn("[WebLLM Demo] Foundation Models failed, falling back to WebLLM:", err);
          setStatus("Native failed, falling back…", 0);
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
              setStatus(loadErr?.message ? String(loadErr.message) : String(loadErr), 0);
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
            setStatus(err?.message ? String(err.message) : String(err), 0);
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
      setStatus(err?.message ? String(err.message) : String(err));
    }
  } finally {
    autoSummarizeRunning = false;
    loadButton.disabled = false;
    modelSelect.disabled = false;

    if (autoSummarizeQueued) {
      autoSummarizeQueued = false;
      autoSummarizeActiveTab({ force: true }).catch((err) => {
        console.warn("[WebLLM Demo] autoSummarizeActiveTab queued run failed:", err);
        setStatus(err?.message ? String(err.message) : String(err));
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
    setStatus(err?.message ? String(err.message) : String(err));
  }
});

copySystemButton?.addEventListener("click", async () => {
  try {
    await refreshSystemPromptFromNative();
    await copyToClipboard(systemPrompt);
    setStatus("已複製系統提示詞");
  } catch (err) {
    setShareVisible(false);
    setThink("");
    setOutput(systemPrompt);
    setStatus("無法寫入剪貼簿，已在下方顯示內容，請手動複製。");
  }
});

copyUserButton?.addEventListener("click", async () => {
  if (!cachedUserPrompt) {
    copyUserButton.disabled = true;
    try {
      setStatus("Preparing user prompt…");
      await refreshSystemPromptFromNative();
      const ctx = await prepareSummaryContextWithRetry();
      if (!ctx) {
        setStatus(NO_SUMMARY_TEXT_MESSAGE, 0);
        setShareVisible(false);
        setThink("");
        setOutput(NO_SUMMARY_TEXT_MESSAGE);
        return;
      }
      setStatus("已準備用戶提示詞，請再按一次「複製用戶提示詞」。", 1);
    } finally {
      copyUserButton.disabled = false;
    }
    return;
  }

  try {
    await copyToClipboard(cachedUserPrompt);
    setStatus("已複製用戶提示詞");
  } catch (err) {
    setShareVisible(false);
    setThink("");
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
    await streamChatWithRecovery([{ role: "user", content: prompt }]);
  } catch (err) {
    setStatus(err?.message ? String(err.message) : String(err));
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
    lastSummarySystemPrompt = "";
    showVisibilityPreview(ctx.text);
    const tokenEstimate = Number(ctx.tokenEstimate ?? lastTokenEstimate) || 0;
    if (tokenEstimate > LONG_DOCUMENT_TOKEN_THRESHOLD) {
      await runLongDocumentPipeline(ctx);
      await saveRawHistoryItem(ctx);
      return;
    }
    if (await shouldUseFoundationModels()) {
      try {
        await streamSummaryWithFoundationModels(ctx);
      } catch (err) {
        console.warn("[WebLLM Demo] Foundation Models failed, falling back to WebLLM:", err);
        setStatus("Native failed, falling back…", 0);
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
    setStatus(err?.message ? String(err.message) : String(err));
  }
});

shareEl?.addEventListener("click", async (event) => {
  event.preventDefault();
  if (generating) return;

  const text = String(outputEl?.textContent ?? "").trim();
  if (!text || text === NO_SUMMARY_TEXT_MESSAGE) {
    setStatus("沒有可分享的內容", 1);
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
      // 不能傳遞 URL，會導致文本信息消失
      try {
        await globalThis.navigator.share(shareData);
      } catch {
        // Ignore share cancellations / platform rejections.
      }
      return;
    }

    await copyToClipboard(shareText);
    setStatus("已複製摘要與連結", 1);
  } catch (err) {
    setStatus(err?.message ? String(err.message) : String(err));
  }
});

statusEl.addEventListener("click", () => {
  autoSummarizeActiveTab({ force: true, restart: true }).catch((err) => {
    console.warn("[WebLLM Demo] status click autoSummarizeActiveTab failed:", err);
    setStatus(err?.message ? String(err.message) : String(err));
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
  setStatus(err?.message ? String(err.message) : String(err));
});
