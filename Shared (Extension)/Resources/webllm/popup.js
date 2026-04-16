const browserAPI = globalThis.browser ?? globalThis.chrome;

const statusEl = document.getElementById("status");
const outputEl = document.getElementById("output");
const availabilityEl = document.getElementById("availability");
const backendBadgeEl = document.getElementById("backend-badge");
const summarizeButton = document.getElementById("summarize");
const copyButton = document.getElementById("share");

const state = {
  backendSelection: "auto",
  availability: null,
  byokSettings: null,
  systemPrompt: "",
  articleContext: null,
  summary: "",
  jobId: null,
  cursor: 0,
  isRunning: false,
};

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
      throw new Error(response?.payload?.message || `${command} failed.`);
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

function resolvedBackendLabel() {
  const selection = state.backendSelection;
  if (selection === "apple") {
    return "Apple Intelligence";
  }
  if (selection === "byok") {
    return "BYOK";
  }
  if (state.availability?.available) {
    return "Auto -> Apple Intelligence";
  }
  return "Auto -> BYOK";
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
    outputEl.textContent = "No output.";
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

function setAvailabilityText(message, isError = false) {
  availabilityEl.textContent = message;
  availabilityEl.classList.toggle("is-error", isError);
}

function updateBackendBadge() {
  backendBadgeEl.textContent = `Backend: ${resolvedBackendLabel()}`;
}

async function refreshConfiguration() {
  const [backendPayload, byokPayload, availabilityPayload, systemPromptPayload] = await Promise.all([
    sendNative("getGenerationBackend"),
    sendNative("getBYOKSettings"),
    sendNative("fm.checkAvailability"),
    sendNative("getSystemPrompt"),
  ]);

  state.backendSelection = backendPayload.backend || "auto";
  state.byokSettings = byokPayload;
  state.availability = availabilityPayload;
  state.systemPrompt = systemPromptPayload.prompt || "";

  updateBackendBadge();
  if (availabilityPayload.available) {
    setAvailabilityText("Available");
  } else {
    setAvailabilityText(availabilityPayload.reason || "Unavailable", true);
  }
}

async function startSummary() {
  if (state.isRunning) {
    return;
  }

  await refreshConfiguration();
  setStatus("Reading tab…");
  renderSummary("");

  const context = await getActiveArticleContext();
  state.articleContext = context;
  const userPrompt = buildUserPrompt(context);

  try {
    await sendNative("fm.prewarm", {
      systemPrompt: state.systemPrompt,
      promptPrefix: userPrompt.slice(0, 1200),
    });
  } catch (_) {
    // Prewarm is optional.
  }

  const startPayload = await sendNative("fm.stream.start", {
    systemPrompt: state.systemPrompt,
    userPrompt,
    options: {
      temperature: 0.2,
      maximumResponseTokens: 2048,
    },
  });

  state.jobId = startPayload.jobId;
  state.cursor = startPayload.cursor || 0;
  state.summary = "";
  state.isRunning = true;
  summarizeButton.textContent = "Stop";
  setStatus("Generating…");

  while (state.jobId && state.isRunning) {
    const pollPayload = await sendNative("fm.stream.poll", {
      jobId: state.jobId,
      cursor: state.cursor,
    });

    const delta = String(pollPayload.delta || "");
    if (delta) {
      state.summary += delta;
      renderSummary(state.summary, false);
    }
    state.cursor = pollPayload.cursor || state.cursor;

    if (pollPayload.done) {
      break;
    }
    await new Promise((resolve) => setTimeout(resolve, 120));
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
  });

  setStatus("Done");
}

async function cancelSummary() {
  if (!state.jobId) {
    return;
  }
  try {
    await sendNative("fm.stream.cancel", { jobId: state.jobId });
  } finally {
    state.isRunning = false;
    state.jobId = null;
    state.cursor = 0;
    summarizeButton.textContent = "Summarize Tab";
    setStatus("Canceled");
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
    setStatus("Error");
    renderSummary(`Error: ${error?.message || String(error)}`);
  } finally {
    state.isRunning = false;
    state.jobId = null;
    state.cursor = 0;
    summarizeButton.textContent = "Summarize Tab";
  }
}

async function copySummary() {
  if (!state.summary.trim()) {
    return;
  }
  try {
    await navigator.clipboard.writeText(state.summary);
    setStatus("Copied");
  } catch (error) {
    setStatus(error?.message || "Copy failed");
  }
}

async function boot() {
  summarizeButton.addEventListener("click", () => {
    handleSummarize();
  });
  copyButton.addEventListener("click", () => {
    copySummary();
  });

  try {
    await refreshConfiguration();
    setStatus("Ready");
  } catch (error) {
    setStatus("Error");
    setAvailabilityText(error?.message || "Failed to load", true);
    renderSummary(`Error: ${error?.message || String(error)}`);
  }
}

boot();
