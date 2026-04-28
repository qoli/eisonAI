const browserAPI = globalThis.browser ?? globalThis.chrome;

const statusEl = document.getElementById("status");
const outputEl = document.getElementById("output");
const backendBadgeEl =
  document.getElementById("backend-badge") ?? document.querySelector(".ai-model");
const progressDotEl = document.querySelector(".progress-dot");
const summarizeButton = document.getElementById("summarize");
const copyButton = document.getElementById("share");

const DEFAULT_TOKEN_ESTIMATOR = "cl100k_base";
const DEFAULT_LONG_DOCUMENT_CHUNK_TOKEN_SIZE = 1792;
const DEFAULT_LONG_DOCUMENT_ROUTING_THRESHOLD = 2048;
const DEFAULT_LONG_DOCUMENT_MAX_CHUNKS = 5;
const MAX_OUTPUT_TOKENS = 1500;
const LONG_DOCUMENT_RETRY_CHUNK_STEP = 256;
const LONG_DOCUMENT_MIN_CHUNK_TOKEN_SIZE = 256;
const TOKENIZER_GLOBALS = {
  cl100k_base: "GPTTokenizer_cl100k_base",
  o200k_base: "GPTTokenizer_o200k_base",
  p50k_base: "GPTTokenizer_p50k_base",
  r50k_base: "GPTTokenizer_r50k_base",
};
const CJK_REGEX = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/gu;
const CJK_SINGLE_REGEX = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u;

const state = {
  backendSelection: "auto",
  availability: null,
  byokSettings: null,
  systemPrompt: "",
  tokenEstimatorEncoding: DEFAULT_TOKEN_ESTIMATOR,
  longDocumentChunkTokenSize: DEFAULT_LONG_DOCUMENT_CHUNK_TOKEN_SIZE,
  longDocumentRoutingThreshold: DEFAULT_LONG_DOCUMENT_ROUTING_THRESHOLD,
  longDocumentMaxChunks: DEFAULT_LONG_DOCUMENT_MAX_CHUNKS,
  effectiveChunkTokenSize: 0,
  articleContext: null,
  summary: "",
  readingAnchors: [],
  tokenEstimate: 0,
  isLongDocument: false,
  jobId: null,
  cursor: 0,
  isRunning: false,
  cancelRequested: false,
};
const tokenizerInstances = new Map();

function logPopupEvent(event, details = {}) {
  console.log(`[eisonAI Popup] ${event}`, details);
}

function callWithOptionalCallback(invoker) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const callback = (value) => {
      if (settled) return;
      settled = true;
      const runtimeError = globalThis.chrome?.runtime?.lastError;
      if (runtimeError) {
        reject(new Error(runtimeError.message));
        return;
      }
      resolve(value);
    };

    try {
      const result = invoker(callback);
      if (result && typeof result.then === "function") {
        result.then(
          (value) => {
            if (!settled) {
              settled = true;
              resolve(value);
            }
          },
          (error) => {
            if (!settled) {
              settled = true;
              reject(error);
            }
          },
        );
      } else if (invoker.length === 0 && !settled) {
        settled = true;
        resolve(result);
      }
    } catch (error) {
      reject(error);
    }
  });
}

function sendNative(command, payload = undefined) {
  const message = { v: 1, command, payload };
  let nativeResult;
  try {
    nativeResult = browserAPI.runtime.sendNativeMessage(message);
  } catch (_) {
    nativeResult = callWithOptionalCallback((callback) =>
      browserAPI.runtime.sendNativeMessage(message, callback),
    );
  }
  return Promise.resolve(nativeResult).then((response) => {
    if (response?.type === "error") {
      const error = new Error(response?.payload?.message || `${command} failed.`);
      error.code = response?.payload?.code || response?.code || "NATIVE_ERROR";
      error.nativeCommand = command;
      error.nativePayload = response?.payload;
      throw error;
    }
    return response?.payload ?? {};
  });
}

function queryTabs(query) {
  try {
    const result = browserAPI.tabs.query(query);
    if (result && typeof result.then === "function") {
      return result;
    }
  } catch (_) {
    // Fall through to callback variant.
  }
  return callWithOptionalCallback((callback) => browserAPI.tabs.query(query, callback));
}

function sendTabMessage(tabId, message) {
  try {
    const result = browserAPI.tabs.sendMessage(tabId, message);
    if (result && typeof result.then === "function") {
      return result;
    }
  } catch (_) {
    // Fall through to callback variant.
  }
  return callWithOptionalCallback((callback) => browserAPI.tabs.sendMessage(tabId, message, callback));
}

async function getActiveArticleContext() {
  const tabs = await queryTabs({ active: true, currentWindow: true });
  const tab = tabs?.[0];
  if (!tab?.id) {
    throw new Error("No active tab.");
  }

  const response = await sendTabMessage(tab.id, { command: "getArticleText" });
  if (!response) {
    throw new Error("No article response.");
  }
  if (response.error) {
    throw new Error(response.error);
  }

  const body = String(response.body || "").trim();
  if (!body) {
    throw new Error("The current tab does not have readable article text.");
  }

  return {
    url: tab.url || "",
    title: String(response.title || tab.title || "").trim(),
    body,
  };
}

function buildUserPrompt(context) {
  const sections = [];
  if (context.title) {
    sections.push(`TITLE\n${context.title}`);
  }
  if (context.url) {
    sections.push(`URL\n${context.url}`);
  }
  sections.push(`CONTENT\n${context.body}`);
  sections.push(
    "TASK\nCreate a concise markdown cognitive index with:\n- one short overview\n- key claims\n- caveats or risks\n- open questions",
  );
  return sections.join("\n\n");
}

function buildReadingAnchorSystemPrompt({ index, total }) {
  return [
    "You create compact reading anchors for a longer document.",
    `This is chunk ${index} of ${total}.`,
    "Return markdown bullets only. Preserve concrete facts, names, numbers, and caveats.",
  ].join("\n");
}

function buildReadingAnchorUserPrompt(chunkText) {
  return [
    "Create a concise reading anchor for this chunk.",
    "",
    chunkText,
  ].join("\n");
}

function buildSummaryUserPromptFromAnchors(context, anchors) {
  const sections = [];
  if (context.title) {
    sections.push(`TITLE\n${context.title}`);
  }
  if (context.url) {
    sections.push(`URL\n${context.url}`);
  }
  sections.push(
    `READING ANCHORS\n${anchors
      .map((anchor) => `Chunk ${anchor.index + 1} (${anchor.tokenCount} tokens)\n${anchor.text}`)
      .join("\n\n")}`,
  );
  sections.push(
    "TASK\nCreate a concise markdown cognitive index with:\n- one short overview\n- key claims\n- caveats or risks\n- open questions",
  );
  return sections.join("\n\n");
}

function resolveTokenizer(encoding) {
  const key = TOKENIZER_GLOBALS[encoding] ?? TOKENIZER_GLOBALS[DEFAULT_TOKEN_ESTIMATOR];
  if (tokenizerInstances.has(key)) {
    return tokenizerInstances.get(key);
  }
  const tokenizer = globalThis[key];
  if (!tokenizer) return null;
  tokenizerInstances.set(key, tokenizer);
  return tokenizer;
}

function getTokenizer() {
  return resolveTokenizer(state.tokenEstimatorEncoding);
}

function estimateTokensFromText(text) {
  const value = String(text ?? "");
  if (!value) return 0;

  const cjkCount = value.match(CJK_REGEX)?.length ?? 0;
  const nonCjkLength = value.replace(CJK_REGEX, "").length;
  return Math.max(1, Math.ceil(cjkCount + nonCjkLength / 4));
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
  } catch (error) {
    console.warn("[eisonAI Popup] Tokenizer failed, falling back:", error);
    return estimateTokensFromText(value);
  }
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
  const maxChunks = Math.max(1, state.longDocumentMaxChunks);

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
    if (Math.ceil(cjkCount + nonCjkCount / 4) >= chunkTokenSize) {
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

  let tokens = [];
  try {
    tokens = tokenizer.encode(value);
  } catch (error) {
    console.warn("[eisonAI Popup] Tokenizer encode failed, falling back:", error);
    return chunkByEstimatedTokens(value, chunkTokenSize);
  }
  if (!Array.isArray(tokens) || tokens.length === 0) {
    return { totalTokens: 0, chunks: [] };
  }

  const chunks = [];
  let utf16Offset = 0;
  const maxTokens = Math.max(1, chunkTokenSize) * Math.max(1, state.longDocumentMaxChunks);
  const limitedTokens = tokens.length > maxTokens ? tokens.slice(0, maxTokens) : tokens;

  for (let i = 0; i < limitedTokens.length; i += chunkTokenSize) {
    const slice = limitedTokens.slice(i, i + chunkTokenSize);
    let chunkText = "";
    try {
      chunkText = String(tokenizer.decode(slice) ?? "");
    } catch (error) {
      console.warn("[eisonAI Popup] Tokenizer decode failed, using empty chunk:", error);
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

function nextLowerChunkTokenSize(current) {
  const currentValue = Number(current) || 0;
  if (currentValue <= LONG_DOCUMENT_MIN_CHUNK_TOKEN_SIZE) return null;
  return Math.max(
    LONG_DOCUMENT_MIN_CHUNK_TOKEN_SIZE,
    currentValue - LONG_DOCUMENT_RETRY_CHUNK_STEP,
  );
}

function collectErrorMessages(error) {
  const messages = [];
  const seen = new Set();
  const stack = [];
  if (error !== null && error !== undefined) {
    stack.push(error);
  }

  while (stack.length) {
    const current = stack.pop();
    if (current === null || current === undefined) continue;

    if (typeof current === "string") {
      const text = current.trim();
      if (text && !seen.has(text)) {
        seen.add(text);
        messages.push(text);
      }
      continue;
    }

    if (current instanceof Error) {
      if (current.message && !seen.has(current.message)) {
        seen.add(current.message);
        messages.push(current.message);
      }
      if (current.cause) {
        stack.push(current.cause);
      }
      continue;
    }

    if (typeof current === "object") {
      const msg = typeof current.message === "string" ? current.message : "";
      const errMsg = typeof current.error === "string" ? current.error : "";
      const reason = typeof current.reason === "string" ? current.reason : "";
      for (const text of [msg, errMsg, reason]) {
        const trimmed = text.trim();
        if (trimmed && !seen.has(trimmed)) {
          seen.add(trimmed);
          messages.push(trimmed);
        }
      }
      if (current.cause) {
        stack.push(current.cause);
      }
      if (Array.isArray(current.errors)) {
        for (const item of current.errors) {
          stack.push(item);
        }
      }
      continue;
    }

    const fallback = String(current).trim();
    if (fallback && !seen.has(fallback)) {
      seen.add(fallback);
      messages.push(fallback);
    }
  }

  return messages;
}

function containsExceededHint(normalized) {
  return (
    normalized.includes("exceed") ||
    normalized.includes("too many") ||
    normalized.includes("too large") ||
    normalized.includes("over limit")
  );
}

function isContextWindowExceededError(error) {
  const code = String(error?.code || error?.errorCode || "").toUpperCase();
  if (code === "EXCEEDED_CONTEXT_WINDOW") return true;

  const messages = collectErrorMessages(error);
  for (const message of messages) {
    const normalized = message.toLowerCase();
    if (normalized.includes("exceeded model context window size")) return true;
    if (normalized.includes("exceeds the maximum allowed context size")) return true;
    if (
      normalized.includes("maximum allowed context size") &&
      normalized.includes("tokens")
    ) {
      return true;
    }
    if (normalized.includes("prompt tokens") && normalized.includes("context")) return true;
    if (normalized.includes("context window") && containsExceededHint(normalized)) return true;
    if (normalized.includes("context size") && containsExceededHint(normalized)) return true;
    if (normalized.includes("context length") && containsExceededHint(normalized)) return true;
  }

  return false;
}

function resolvedBackendLabel() {
  const selection = state.backendSelection;
  if (selection === "apple") {
    return "Apple Intelligence";
  }
  if (selection === "byok") {
    return "BYOK";
  }
  if (state.availability?.available) {
    return "Auto Apple";
  }
  return "Auto BYOK";
}

function resolvedModelId() {
  if (state.backendSelection === "apple") {
    return "apple-intelligence";
  }
  if (state.backendSelection === "byok") {
    return state.byokSettings?.model?.trim() || "byok";
  }
  if (state.availability?.available) {
    return "apple-intelligence";
  }
  return state.byokSettings?.model?.trim() || "byok";
}

function renderSummary(markdown, asMarkdown = false) {
  if (!markdown.trim()) {
    outputEl.textContent = "";
    outputEl.classList.remove("rendered");
    return;
  }

  if (asMarkdown && globalThis.marked?.parse) {
    outputEl.innerHTML = globalThis.marked.parse(markdown);
    outputEl.classList.add("rendered");
    return;
  }

  outputEl.textContent = markdown;
  outputEl.classList.remove("rendered");
}

function setStatus(message) {
  statusEl.textContent = message;
}

function setProgressState(stateName, breathing = false) {
  if (!progressDotEl) return;
  progressDotEl.classList.remove(
    "state-engine",
    "state-generating",
    "state-longdoc",
    "state-reading",
    "state-ready",
    "state-error",
    "state-stopped",
    "is-breathing",
  );
  progressDotEl.classList.add(`state-${stateName}`);
  progressDotEl.classList.toggle("is-breathing", breathing);
}

function updateBackendBadge() {
  if (!backendBadgeEl) return;
  backendBadgeEl.textContent = resolvedBackendLabel();
}

async function refreshConfiguration() {
  const [
    backendPayload,
    byokPayload,
    availabilityPayload,
    systemPromptPayload,
    tokenEstimatorPayload,
    chunkSizePayload,
    maxChunksPayload,
  ] = await Promise.all([
    sendNative("getGenerationBackend"),
    sendNative("getBYOKSettings"),
    sendNative("fm.checkAvailability"),
    sendNative("getSystemPrompt"),
    sendNative("getTokenEstimatorEncoding"),
    sendNative("getLongDocumentChunkTokenSize"),
    sendNative("getLongDocumentMaxChunks"),
  ]);

  state.backendSelection = backendPayload.backend || "auto";
  state.byokSettings = byokPayload;
  state.availability = availabilityPayload;
  state.systemPrompt = systemPromptPayload.prompt || "";
  if (TOKENIZER_GLOBALS[tokenEstimatorPayload.encoding]) {
    state.tokenEstimatorEncoding = tokenEstimatorPayload.encoding;
  }
  const chunkTokenSize = Number(chunkSizePayload.chunkTokenSize);
  if (Number.isFinite(chunkTokenSize) && chunkTokenSize > 0) {
    state.longDocumentChunkTokenSize = chunkTokenSize;
  }
  const routingThreshold = Number(chunkSizePayload.routingThreshold);
  if (Number.isFinite(routingThreshold) && routingThreshold > 0) {
    state.longDocumentRoutingThreshold = routingThreshold;
  }
  const maxChunks = Number(maxChunksPayload.maxChunks);
  if (Number.isFinite(maxChunks) && maxChunks > 0) {
    state.longDocumentMaxChunks = maxChunks;
  }

  updateBackendBadge();
  logPopupEvent("config.loaded", {
    backend: state.backendSelection,
    resolvedBackend: resolvedModelId(),
    tokenEstimator: state.tokenEstimatorEncoding,
    chunkTokenSize: state.longDocumentChunkTokenSize,
    routingThreshold: state.longDocumentRoutingThreshold,
    maxChunks: state.longDocumentMaxChunks,
  });
}

async function streamNativeText({
  systemPrompt,
  userPrompt,
  tokenEstimate,
  renderOutput = true,
}) {
  try {
    await sendNative("fm.prewarm", {
      systemPrompt,
      promptPrefix: userPrompt.slice(0, 1200),
      tokenEstimate,
    });
  } catch (_) {
    // Prewarm is optional.
  }

  const startPayload = await sendNative("fm.stream.start", {
    systemPrompt,
    userPrompt,
    tokenEstimate,
    options: {
      temperature: 0.2,
      maximumResponseTokens: MAX_OUTPUT_TOKENS,
    },
  });

  state.jobId = startPayload.jobId;
  state.cursor = startPayload.cursor || 0;
  let text = "";
  logPopupEvent("stream.start", {
    tokenEstimate,
    promptChars: userPrompt.length,
    systemPromptChars: systemPrompt.length,
    renderOutput,
  });

  while (state.jobId && state.isRunning && !state.cancelRequested) {
    const pollPayload = await sendNative("fm.stream.poll", {
      jobId: state.jobId,
      cursor: state.cursor,
    });

    const delta = String(pollPayload.delta || "");
    if (delta) {
      text += delta;
      if (renderOutput) {
        renderSummary(text, false);
      }
    }
    state.cursor = pollPayload.cursor || state.cursor;

    if (pollPayload.done) {
      break;
    }
    await new Promise((resolve) => setTimeout(resolve, 120));
  }

  state.jobId = null;
  state.cursor = 0;
  return text;
}

async function summarizeLongDocument(context, tokenEstimate) {
  let chunkTokenSize = Math.max(1, state.longDocumentChunkTokenSize);
  let lastError = null;

  while (chunkTokenSize) {
    try {
      return await summarizeLongDocumentWithChunkSize(context, tokenEstimate, chunkTokenSize);
    } catch (error) {
      lastError = error;
      if (!isContextWindowExceededError(error) || state.cancelRequested) {
        throw error;
      }

      const nextChunkTokenSize = nextLowerChunkTokenSize(chunkTokenSize);
      logPopupEvent("longdoc.contextLimit", {
        previousChunkTokenSize: chunkTokenSize,
        nextChunkTokenSize,
        tokenEstimate,
        errorCode: error.code,
        errorMessage: error.message,
      });
      if (!nextChunkTokenSize || nextChunkTokenSize === chunkTokenSize) {
        throw error;
      }

      setStatus(`Context limit, retry ${nextChunkTokenSize}…`);
      renderSummary(`Context limit, retrying with ${nextChunkTokenSize}-token chunks…`);
      state.readingAnchors = [];
      state.jobId = null;
      state.cursor = 0;
      chunkTokenSize = nextChunkTokenSize;
    }
  }

  throw lastError || new Error("Long document retry failed.");
}

async function summarizeLongDocumentWithChunkSize(context, tokenEstimate, chunkTokenSize) {
  state.effectiveChunkTokenSize = chunkTokenSize;
  const chunkInfo = chunkByTokens(context.body, chunkTokenSize);
  const chunks = chunkInfo.chunks;
  if (!chunks.length) {
    throw new Error("Chunking returned no chunks.");
  }

  state.readingAnchors = [];
  setProgressState("longdoc", true);
  logPopupEvent("longdoc.start", {
    tokenEstimate,
    chunkTokenSize,
    chunkCount: chunks.length,
    chunkTokenCounts: chunks.map((chunk) => chunk.tokenCount),
    maxChunks: state.longDocumentMaxChunks,
  });

  for (const chunk of chunks) {
    if (!state.isRunning) break;
    setStatus(`Reading chunk ${chunk.index + 1}/${chunks.length}…`);
    logPopupEvent("longdoc.chunk.start", {
      index: chunk.index + 1,
      total: chunks.length,
      tokenCount: chunk.tokenCount,
      textChars: chunk.text.length,
      chunkTokenSize,
    });
    setStatus(`Generating chunk ${chunk.index + 1}/${chunks.length}…`);
    renderSummary("");
    const anchorText = await streamNativeText({
      systemPrompt: buildReadingAnchorSystemPrompt({
        index: chunk.index + 1,
        total: chunks.length,
      }),
      userPrompt: buildReadingAnchorUserPrompt(chunk.text),
      tokenEstimate,
      renderOutput: true,
    });
    if (state.cancelRequested) {
      return { summaryText: "", userPrompt: "" };
    }
    state.readingAnchors.push({
      index: chunk.index,
      tokenCount: chunk.tokenCount,
      text: anchorText.trim(),
      startUTF16: chunk.startUTF16,
      endUTF16: chunk.endUTF16,
    });
    logPopupEvent("longdoc.chunk.done", {
      index: chunk.index + 1,
      total: chunks.length,
      anchorChars: anchorText.length,
    });
  }

  setStatus("Generating summary…");
  setProgressState("generating", true);
  renderSummary("");
  const summaryUserPrompt = buildSummaryUserPromptFromAnchors(context, state.readingAnchors);
  logPopupEvent("longdoc.final.start", {
    anchorCount: state.readingAnchors.length,
    summaryPromptChars: summaryUserPrompt.length,
    chunkTokenSize,
  });
  return streamNativeText({
    systemPrompt: state.systemPrompt,
    userPrompt: summaryUserPrompt,
    tokenEstimate,
    renderOutput: true,
  }).then((summaryText) => ({
    summaryText,
    userPrompt: summaryUserPrompt,
  }));
}

async function startSummary() {
  if (state.isRunning) {
    return;
  }

  await refreshConfiguration();
  setStatus("Reading tab…");
  setProgressState("reading", true);
  renderSummary("");

  const context = await getActiveArticleContext();
  state.articleContext = context;
  state.tokenEstimate = estimateTokensWithTokenizer(context.body);
  state.isLongDocument = state.tokenEstimate > state.longDocumentRoutingThreshold;
  state.readingAnchors = [];
  state.effectiveChunkTokenSize = 0;
  logPopupEvent("summary.context", {
    tokenEstimate: state.tokenEstimate,
    routingThreshold: state.longDocumentRoutingThreshold,
    isLongDocument: state.isLongDocument,
    articleChars: context.body.length,
  });

  state.summary = "";
  state.isRunning = true;
  state.cancelRequested = false;
  if (summarizeButton) {
    summarizeButton.textContent = "Stop";
  }

  let userPrompt = buildUserPrompt(context);
  if (state.isLongDocument) {
    const result = await summarizeLongDocument(context, state.tokenEstimate);
    state.summary = result.summaryText;
    userPrompt = result.userPrompt;
  } else {
    setStatus("Generating…");
    setProgressState("generating", true);
    try {
      state.summary = await streamNativeText({
        systemPrompt: state.systemPrompt,
        userPrompt,
        tokenEstimate: state.tokenEstimate,
        renderOutput: true,
      });
    } catch (error) {
      if (!isContextWindowExceededError(error)) {
        throw error;
      }
      logPopupEvent("summary.direct.contextLimit", {
        tokenEstimate: state.tokenEstimate,
        routingThreshold: state.longDocumentRoutingThreshold,
        errorCode: error.code,
        errorMessage: error.message,
      });
      state.isLongDocument = true;
      setStatus(`Context limit, retry ${state.longDocumentChunkTokenSize}…`);
      renderSummary(
        `Context limit, retrying with ${state.longDocumentChunkTokenSize}-token chunks…`,
      );
      const result = await summarizeLongDocument(context, state.tokenEstimate);
      state.summary = result.summaryText;
      userPrompt = result.userPrompt;
    }
  }

  if (state.cancelRequested) {
    return;
  }

  if (!state.summary.trim()) {
    throw new Error("Empty summary.");
  }

  renderSummary(state.summary, true);
  setStatus("Saving…");

  await sendNative("saveRawItem", {
    url: context.url,
    title: context.title,
    articleText: context.body,
    summaryText: state.summary,
    systemPrompt: state.systemPrompt,
    userPrompt,
    modelId: resolvedModelId(),
    readingAnchors: state.readingAnchors,
    tokenEstimate: state.tokenEstimate,
    tokenEstimator: state.tokenEstimatorEncoding,
    chunkTokenSize: state.isLongDocument ? state.effectiveChunkTokenSize : undefined,
    routingThreshold: state.longDocumentRoutingThreshold,
    isLongDocument: state.isLongDocument,
  });

  setStatus("Done");
  setProgressState("ready");
}

async function cancelSummary() {
  state.cancelRequested = true;
  if (!state.jobId) {
    state.isRunning = false;
    setStatus("Canceled");
    setProgressState("stopped");
    return;
  }
  try {
    await sendNative("fm.stream.cancel", { jobId: state.jobId });
  } finally {
    state.isRunning = false;
    state.jobId = null;
    state.cursor = 0;
    if (summarizeButton) {
      summarizeButton.textContent = "Summarize Tab";
    }
    setStatus("Canceled");
    setProgressState("stopped");
  }
}

async function handleSummarize() {
  if (state.isRunning) {
    await cancelSummary();
    return;
  }

  try {
    await startSummary();
  } catch (error) {
    if (state.cancelRequested) {
      setStatus("Canceled");
      setProgressState("stopped");
      return;
    }
    setStatus("Error");
    setProgressState("error");
    logPopupEvent("summary.error", {
      code: error?.code,
      command: error?.nativeCommand,
      message: error?.message || String(error),
      tokenEstimate: state.tokenEstimate,
      isLongDocument: state.isLongDocument,
      chunkTokenSize: state.longDocumentChunkTokenSize,
      effectiveChunkTokenSize: state.effectiveChunkTokenSize,
    });
    renderSummary(`Error: ${error?.message || String(error)}`);
  } finally {
    state.isRunning = false;
    state.jobId = null;
    state.cursor = 0;
    if (summarizeButton) {
      summarizeButton.textContent = "Summarize Tab";
    }
  }
}

async function shareSummary() {
  const summary = state.summary.trim();
  if (!summary) {
    setStatus("Nothing to share");
    return;
  }
  const url = state.articleContext?.url?.startsWith("http") ? state.articleContext.url : "";
  const shareText = url ? `${summary}\n\n${url}` : summary;

  try {
    if (typeof navigator.share === "function") {
      await navigator.share({ text: shareText });
      return;
    }
    await navigator.clipboard.writeText(shareText);
    setStatus("Summary and link copied");
  } catch (error) {
    setStatus(error?.message || "Share failed");
  }
}

async function boot() {
  if (summarizeButton) {
    summarizeButton.addEventListener("click", () => {
      handleSummarize();
    });
  }
  copyButton.addEventListener("click", (event) => {
    event.preventDefault();
    shareSummary();
  });
  statusEl.addEventListener("click", () => {
    handleSummarize();
  });
  statusEl.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      handleSummarize();
    }
  });

  try {
    setProgressState("engine", true);
    await refreshConfiguration();
    setStatus("Ready");
    setProgressState("ready");
    handleSummarize();
  } catch (error) {
    setStatus("Error");
    setProgressState("error");
    renderSummary(`Error: ${error?.message || String(error)}`);
  }
}

boot();
