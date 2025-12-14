const browser = globalThis.browser ?? globalThis.chrome;

function measureJsonBytes(value) {
  try {
    const encoder = new TextEncoder();
    return encoder.encode(JSON.stringify(value)).length;
  } catch {
    return null;
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function splitTextToUtf8Chunks(text, maxBytes) {
  const encoder = new TextEncoder();
  const chunks = [];

  if (!text) return chunks;
  if (maxBytes <= 0) return [text];

  let start = 0;
  const textLength = text.length;

  // Heuristic starting point: assume 2 bytes/char average for CJK-heavy text.
  const approxCharsPerChunk = Math.max(256, Math.floor(maxBytes / 2));

  while (start < textLength) {
    let end = Math.min(textLength, start + approxCharsPerChunk);

    // If our guess is too large, shrink until it fits.
    while (end > start && encoder.encode(text.slice(start, end)).length > maxBytes) {
      end = Math.max(start + 1, end - 64);
    }
    while (end > start && encoder.encode(text.slice(start, end)).length > maxBytes) {
      end -= 1;
    }

    // Safety fallback to avoid infinite loops.
    if (end <= start) {
      end = Math.min(textLength, start + 1);
    }

    chunks.push(text.slice(start, end));
    start = end;
  }

  return chunks;
}

function createMutex() {
  let tail = Promise.resolve();
  return {
    async run(task) {
      const previous = tail;
      let release = null;
      tail = new Promise((resolve) => (release = resolve));
      await previous;
      try {
        return await task();
      } finally {
        release?.();
      }
    }
  };
}

const nativeMessageMutex = createMutex();

function sendMessageToBackground(message) {
  if (typeof browser?.runtime?.sendMessage !== "function") {
    console.error("[Eison-Popup] runtime.sendMessage unavailable, cannot message background:", message);
    return;
  }
  console.log("[Eison-Popup] Sending message to background:", message);
  browser.runtime
    .sendMessage(message)
    .catch((e) => console.error("[Eison-Popup] Error sending message to background:", e));
}

async function getActiveTab() {
  if (typeof browser?.tabs?.query !== "function") {
    throw new Error("browser.tabs.query is unavailable");
  }
  try {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    return tabs && tabs[0] ? tabs[0] : null;
  } catch (error) {
    console.error("[Eison-Popup] tabs.query failed with currentWindow, retrying without it:", error);
    const tabs = await browser.tabs.query({ active: true });
    return tabs && tabs[0] ? tabs[0] : null;
  }
}

async function sendMessageToActiveTabContent(message) {
  if (typeof browser?.tabs?.sendMessage !== "function") {
    throw new Error("browser.tabs.sendMessage is unavailable");
  }
  const tab = await getActiveTab();
  if (!tab?.id) {
    throw new Error("No active tab found");
  }
  console.log("[Eison-Popup] Sending message to content:", { tabId: tab.id, message });
  return await browser.tabs.sendMessage(tab.id, message);
}

async function sendNativeMessage(request, options = {}) {
  if (typeof browser?.runtime?.sendNativeMessage !== "function") {
    const error = new Error("browser.runtime.sendNativeMessage is unavailable in popup context");
    console.error("[Eison-Popup] sendNativeMessage unavailable:", { request, error });
    throw error;
  }

  return await nativeMessageMutex.run(async () => {
    return await sendNativeMessageUnlocked(request, options);
  });
}

async function sendNativeMessageUnlocked(request, options = {}) {
  // Safari's `sendNativeMessage` is often callback-based and may throw
  // "Invalid call to runtime.sendNativeMessage()" when invoked without a callback.
  // The function arity isn't reliable on Safari (can be 0), so try callback-style first.

  // Safari ignores the first argument, but iOS Safari appears to reject certain values (e.g. extension bundle id).
  // Use the sample's placeholder first, then fall back to the containing app bundle id.
  const nativeAppIds = ["application.id", "com.qoli.eisonAI"];
  const fn = browser.runtime.sendNativeMessage;
  const timeoutMs = typeof options.timeoutMs === "number" ? options.timeoutMs : 10_000;

  const callWithCallbackOrPromise = (appId) =>
    new Promise((resolve, reject) => {
      let settled = false;

      const finish = (error, response) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        if (error) reject(error);
        else resolve(response);
      };

      const timer = setTimeout(() => {
        finish(new Error("sendNativeMessage timed out"));
      }, timeoutMs);

      try {
        const maybePromise = fn.call(browser.runtime, appId, request, (response) => {
          const runtimeError = browser?.runtime?.lastError;
          if (runtimeError) {
            finish(new Error(runtimeError.message || String(runtimeError)));
            return;
          }
          finish(null, response);
        });

        if (maybePromise && typeof maybePromise.then === "function") {
          maybePromise.then(
            (response) => finish(null, response),
            (error) => finish(error)
          );
        }
      } catch (error) {
        try {
          Promise.resolve(fn.call(browser.runtime, appId, request)).then(
            (response) => finish(null, response),
            (err) => finish(err)
          );
        } catch (err2) {
          finish(err2);
        }
      }
    });

  let lastError = null;
  for (const appId of nativeAppIds) {
    try {
      console.log("[Eison-Popup] sendNativeMessage:", { appId, name: request?.name, id: request?.id });
      return await callWithCallbackOrPromise(appId);
    } catch (error) {
      lastError = error;
      console.error("[Eison-Popup] sendNativeMessage failed:", { appId, error });
    }
  }

  // Very old/alternate implementations may accept 1-arg; keep as last resort.
  try {
    return await fn.call(browser.runtime, request);
  } catch (error) {
    lastError = lastError || error;
  }

  throw lastError || new Error("Unable to reach native app via sendNativeMessage");
}

function makeEnvelope(name, payload) {
  const requestId = crypto?.randomUUID ? crypto.randomUUID() : String(Date.now());
  return {
    v: 1,
    id: requestId,
    type: "request",
    name,
    payload: payload || {}
  };
}

async function saveData(key, data) {
  const obj = {};
  obj[key] = data;
  await browser.storage.local.set(obj);
}

async function loadData(key, defaultValue = "") {
  const result = await browser.storage.local.get(key);
  const value = result[key];
  return value === undefined ? defaultValue : value;
}

function hideID(idName) {
  const element = document.getElementById(idName);
  if (element) {
    element.style.display = "none";
  }
}

function showID(idName, display = "block") {
  const element = document.getElementById(idName);
  if (element) {
    element.style.display = display;
  }
}

window.addEventListener("error", (event) => {
  try {
    const text = document.getElementById("StatusText");
    if (text) {
      text.textContent = `錯誤：${event?.message || "unknown"}`;
    }
    const icon = document.getElementById("StatusIcon");
    if (icon) {
      icon.classList.remove("normal", "warming");
      icon.classList.add("error");
    }
  } catch {
    // ignore
  }
});

window.addEventListener("unhandledrejection", (event) => {
  try {
    const text = document.getElementById("StatusText");
    if (text) {
      const reason = event?.reason?.message ? String(event.reason.message) : String(event?.reason || "unknown");
      text.textContent = `錯誤：${reason}`;
    }
    const icon = document.getElementById("StatusIcon");
    if (icon) {
      icon.classList.remove("normal", "warming");
      icon.classList.add("error");
    }
  } catch {
    // ignore
  }
});

function getDebugText() {
  sendMessageToBackground({ command: "getDebugText" });
}

function addMessageListener() {
  browser.runtime.onMessage.addListener(function (
    request,
    sender,
    sendResponse
  ) {
    console.log("Popup: Message received", request);

    // This listener is now only for messages actively pushed from other scripts,
    // not for handling responses to requests made from this script.
    if (request.command === "debugTextResponse") {
      document.querySelector("#ReadabilityText").innerHTML = request.body;
    }

    if (request.command === "summaryStream") {
      showArea("SummaryContent");
      summaryStatusText("總結中...");
      renderStreamingSummary(request.text || "");
    }

    if (request.command === "summaryStatusUpdate") {
      if (request.status === "completed") {
        showArea("SummaryContent");
        summaryStatusText("總結完畢");

        if (request.titleText && request.summaryText) {
          displaySummaryResult(request.titleText, request.summaryText);
          if (!request.noCache) {
            cacheSummaryResultFromPopup(request.titleText, request.summaryText, request.url);
          }
        } else {
          reloadReceiptData();
        }
      }

      if (request.status === "error") {
        const errorMsg = request.error ? `總結失敗：${request.error}` : "總結失敗";
        summaryStatusText(errorMsg);
      }
    }
  });
}

function addClickListeners() {
  // 取得所有具有 clickListen 類別的按鈕
  const buttons = document.querySelectorAll(".clickListen");

  console.log(buttons);

  // 迭代每個按鈕
  buttons.forEach((button) => {
    // 監聽按鈕的點擊事件
    button.addEventListener("click", () => {
      // 取得 data-function 屬性的值
      const functionName = button.getAttribute("data-function");

      // 檢查是否存在 data-function 屬性
      if (functionName) {
        // 取得 data-params 屬性的值
        const params = button.getAttribute("data-params");

        console.log("call", functionName, params);

        // 檢查是否存在 data-params 屬性
        if (params) {
          // 呼叫函數並傳遞參數
          window[functionName](params);
        } else {
          // 呼叫函數，不傳遞參數
          window[functionName]();
        }
      }
    });
  });
}

function getHostFromUrl(url) {
  try {
    const parsedUrl = new URL(url);
    return parsedUrl.host || "";
  } catch (error) {
    console.error("[Eison-Popup] Invalid URL for host parse:", { url, error });
    return "";
  }
}

function setupButtonBarActions() {
  const buttonBars = document.querySelectorAll(".buttonBar");

  buttonBars.forEach((buttonBar) => {
    buttonBar.addEventListener("click", function () {
      const id = buttonBar.getAttribute("data-id");
      toggleArea(id);
    });
  });
}

function setupStatus() {
  let text = document.getElementById("StatusText");

  (async () => {
    try {
      const response = await sendNativeMessage(makeEnvelope("model.getStatus", {}), { timeoutMs: 2_500 });
      console.log("[Eison-Popup] model.getStatus response:", response);
      const payload = response?.name === "model.status" ? response.payload : null;
      const state = payload?.state || "unknown";
      const progress = typeof payload?.progress === "number" ? payload.progress : 0;

      if (state === "ready") {
        setStatus("normal");
        text.innerHTML = "本地模型已就緒";
        return;
      }

      if (state === "downloading" || state === "verifying") {
        setStatus("warming");
        text.innerHTML = `模型下載中 ${Math.round(progress * 100)}%`;
        return;
      }

      if (state === "failed") {
        setStatus("error");
        text.innerHTML = "模型下載失敗，請打開 App 重試";
        return;
      }

      setStatus("error");
      text.innerHTML = "未下載模型，請打開 App 下載";
    } catch (error) {
      setStatus("error");
      const message = error?.message ? String(error.message) : String(error);
      text.innerHTML = "模型狀態取得失敗：" + message;
      console.error("[Eison-Popup] setupStatus failed:", error);
    }
  })();
}

function toggleArea(id) {
  const correspondingElement = document.querySelector("#" + id);

  if (correspondingElement) {
    if (correspondingElement.classList.contains("areaSlideVisible")) {
      correspondingElement.classList.remove("areaSlideVisible");
      correspondingElement.classList.add("areaSlideHidden");
    } else {
      correspondingElement.classList.remove("areaSlideHidden");
      correspondingElement.classList.add("areaSlideVisible");
    }
  }
}

function showArea(id) {
  const correspondingElement = document.querySelector("#" + id);

  if (!correspondingElement.classList.contains("areaSlideVisible")) {
    correspondingElement.classList.remove("areaSlideHidden");
    correspondingElement.classList.add("areaSlideVisible");
  }
}

async function shareContent() {
  try {
    const title = document.getElementById("receiptTitle").innerText;
    const text = document.getElementById("receipt").innerText;
    const url = await getTabURL();

    if (navigator.share) {
      await navigator.share({
        text: title + "\n\r" + text + url,
      });
      console.log("Content shared successfully");
    } else {
      console.log("Web Share API not supported in this browser.");
      // Fallback behavior can be implemented here
    }
  } catch (error) {
    console.error("Error sharing:", error);
  }
}

function mainApp() {
  console.log("[Eison-Popup] runtime:", {
    runtimeId: browser?.runtime?.id,
    hasNativeMessaging: typeof browser?.runtime?.sendNativeMessage === "function",
    sendNativeMessageArity: browser?.runtime?.sendNativeMessage?.length
  });

  setupButtonBarActions();
  addClickListeners();
  setPlatformClassToBody();

  //runtime only
  addMessageListener();
  setupStatus();

  hideID("shareButton")
}

async function getTabURL() {
  const tab = await getActiveTab();
  return tab?.url || "";
}

function setStatus(className) {
  let icon = document.getElementById("StatusIcon");

  icon.classList.remove("normal");
  icon.classList.remove("warming");
  icon.classList.remove("error");

  icon.classList.add(className);
}

function setPlatformClassToBody() {
  // 判斷用戶平台並添加相應的 class
  if (isIOS()) {
    document.body.classList.add("ios");
  } else if (isMacOS()) {
    document.body.classList.add("macos");
  } else {
    document.body.classList.add("other-platform");
  }
}

// 判斷是否在 iOS 上運行
function isIOS() {
  return /iPhone|iPad|iPod/i.test(navigator.platform);
}

// 判斷是否在 macOS 上運行
function isMacOS() {
  return /MacIntel/i.test(navigator.platform);
}

// Run app
try {
  const text = document.getElementById("StatusText");
  if (text) {
    text.textContent = "載入中... (popup.js m2)";
  }
} catch {
  // ignore
}

mainApp();

setTimeout(() => {
  delayRun();
}, 50);

// delay enter ...
function delayRun() {
  (async () => {
    let currentTabURL = await getTabURL();

    document.querySelector("#currentHOST").innerHTML =
      getHostFromUrl(currentTabURL);

    reloadReceiptData();

    if (document.getElementById("receipt").innerHTML == "") {
      summaryStatusText("即將總結...");
      setTimeout(() => {
        sendRunSummaryMessage();
      }, 500);
    }
  })();
}

async function reloadReceiptData() {
  try {
    let tabURL = await loadData("ReceiptURL", "");
    let currentURL = await getTabURL();

    if (tabURL != currentURL) {
      return;
    }

    let receiptTitleText = await loadData("ReceiptTitleText", "");
    let receiptText = await loadData("ReceiptText", "");

    if (receiptText != "") {
      showArea("SummaryContent");

      document.getElementById("receiptTitle").innerText = receiptTitleText;
      document.getElementById("receipt").innerText = receiptText;

      // Ensure status reflects completion when cached data is shown
      summaryStatusText("總結完畢");

      displaySummaryResult(receiptTitleText, receiptText)
    }
  } catch (error) {
    console.error("[Eison-Popup] Failed to reload cached data:", error);
  }
}

async function cacheSummaryResultFromPopup(titleText, summaryText, urlFromMessage) {
  try {
    const url = urlFromMessage || await getTabURL();

    if (!url) {
      console.error("[Eison-Popup] No URL available to cache summary");
      return;
    }

    await saveData("ReceiptURL", url);
    await saveData("ReceiptTitleText", titleText);
    await saveData("ReceiptText", summaryText);
  } catch (error) {
    console.error("[Eison-Popup] Failed to cache summary result:", error);
  }
}

async function summarizeViaNativeChunked({ url, title, text }) {
  const sessionId = crypto?.randomUUID ? crypto.randomUUID() : String(Date.now());
  const maxChunkBytes = 2000;
  const chunks = splitTextToUtf8Chunks(text || "", maxChunkBytes);
  if (chunks.length === 0) {
    chunks.push("");
  }

  console.log("[Eison-Popup] summarize chunked:", {
    sessionId,
    maxChunkBytes,
    chunkCount: chunks.length,
    titleLength: (title || "").length,
    textLength: (text || "").length
  });

  // Begin
  const beginResp = await sendNativeMessage(
    makeEnvelope("summarize.begin", {
      sessionId,
      url: url || "",
      title: title || "",
      chunkCount: chunks.length
    }),
    { timeoutMs: 2_500 }
  );
  if (beginResp?.name === "error") {
    const msg = beginResp?.payload?.message ? String(beginResp.payload.message) : "Native error";
    throw new Error(msg);
  }

  // Chunks
  for (let i = 0; i < chunks.length; i++) {
    const chunkResp = await sendNativeMessage(
      makeEnvelope("summarize.chunk", {
        sessionId,
        index: i,
        text: chunks[i]
      }),
      { timeoutMs: 2_500 }
    );
    if (chunkResp?.name === "error") {
      const msg = chunkResp?.payload?.message ? String(chunkResp.payload.message) : "Native error";
      throw new Error(msg);
    }
    await sleep(25);
  }

  // End (returns final summary)
  await sleep(150);

  let lastError = null;
  const endRequest = makeEnvelope("summarize.end", { sessionId });
  for (const delay of [0, 250, 750]) {
    if (delay) {
      await sleep(delay);
    }
    try {
      return await sendNativeMessage(endRequest, { timeoutMs: 120_000 });
    } catch (error) {
      lastError = error;
      const message = error?.message ? String(error.message) : String(error);
      console.error("[Eison-Popup] summarize.end failed, retrying:", { delay, message, error });
    }
  }
  throw lastError || new Error("summarize.end failed");
}

/// 請求總結 - 新架構
async function sendRunSummaryMessage() {
  showArea("SummaryContent");
  summaryStatusText("準備中...");

  try {
    const tab = await getActiveTab();
    if (!tab?.id || !tab.url) {
      summaryStatusText("錯誤：找不到當前頁面");
      console.error("[Eison-Popup] No active tab for summary");
      return;
    }

    // Cache hit?
    const cachedURL = await loadData("ReceiptURL", "");
    const cachedTitle = await loadData("ReceiptTitleText", "");
    const cachedText = await loadData("ReceiptText", "");
    if (cachedURL === tab.url && cachedText) {
      console.log("[Eison-Popup] Cache hit:", tab.url);
      displaySummaryResult(cachedTitle || "Summary", cachedText);
      return;
    }

    summaryStatusText("提取內容中...");
    const articleResponse = await sendMessageToActiveTabContent({ command: "getArticleText" });
    if (!articleResponse || typeof articleResponse !== "object") {
      summaryStatusText("錯誤：無法取得文章內容");
      console.error("[Eison-Popup] Invalid article response:", articleResponse);
      return;
    }
    if (articleResponse.error) {
      summaryStatusText("錯誤：" + String(articleResponse.error));
      console.error("[Eison-Popup] Article extraction error:", articleResponse.error);
      return;
    }

    const title = articleResponse.title || "";
    const body = articleResponse.body || "";
    console.log("[Eison-Popup] Article extracted:", { titleLength: title.length, bodyLength: body.length });

    summaryStatusText("呼叫本地模型中...");
    renderStreamingSummary("");

    const request = makeEnvelope("summarize.start", {
      url: tab.url,
      title,
      text: body
    });
    const requestBytes = measureJsonBytes(request);
    console.log("[Eison-Popup] summarize.start request size:", { requestBytes, titleLength: title.length, bodyLength: body.length });

    let response;
    try {
      response = await sendNativeMessage(request, { timeoutMs: 120_000 });
    } catch (error) {
      const message = error?.message ? String(error.message) : String(error);
      // Safari may reject larger messages; fall back to chunked native messaging.
      if (message.includes("Invalid call to runtime.sendNativeMessage")) {
        console.warn("[Eison-Popup] summarize.start rejected; falling back to chunked mode:", { message });
        response = await summarizeViaNativeChunked({ url: tab.url, title, text: body });
      } else {
        throw error;
      }
    }

    console.log("[Eison-Popup] Summary response:", response);

    if (response?.name === "error") {
      const msg = response?.payload?.message ? String(response.payload.message) : "Native error";
      summaryStatusText("錯誤：" + msg);
      console.error("[Eison-Popup] Native error:", response);
      return;
    }

    if (response?.name !== "summarize.done") {
      summaryStatusText("錯誤：Native 回傳格式不符");
      console.error("[Eison-Popup] Unexpected native response:", response);
      return;
    }

    const result = response?.payload?.result;
    const titleText = result?.titleText || title || "Summary";
    const summaryText = result?.summaryText || "";
    if (!summaryText) {
      summaryStatusText("錯誤：摘要內容為空");
      console.error("[Eison-Popup] Empty summaryText:", response);
      return;
    }

    displaySummaryResult(titleText, summaryText);
    await cacheSummaryResultFromPopup(titleText, summaryText, tab.url);

  } catch (e) {
    const message = e?.message ? String(e.message) : String(e);
    console.error("[Eison-Popup] Error requesting summary:", e);
    summaryStatusText("錯誤：" + message);
  }
}

// Poll for summary status updates
async function pollSummaryStatus() {
  const pollInterval = 1000; // Poll every second
  const maxPolls = 120; // Max 2 minutes
  let pollCount = 0;

  const poll = async () => {
    try {
      pollCount++;

      // Check if we've exceeded max polling time
      if (pollCount > maxPolls) {
        summaryStatusText("處理超時");
        return;
      }

      // Get current summary status
      const statusResponse = await browser.runtime.sendMessage({
        command: "getSummaryStatus"
      });

      console.log("[Eison-Popup] Status poll:", statusResponse);

      switch (statusResponse.status) {
        case 'extracting':
          summaryStatusText("提取內容中...");
          setTimeout(poll, pollInterval);
          break;

        case 'summarizing':
          summaryStatusText("總結中...");
          setTimeout(poll, pollInterval);
          break;

        case 'completed':
          // Summary is complete, reload the cached result
          await reloadReceiptData();
          break;

        case 'error':
          // Keep the detailed error message pushed via `summaryStatusUpdate` if available.
          break;

        default:
          if (statusResponse.isRunning) {
            summaryStatusText("處理中...");
            setTimeout(poll, pollInterval);
          } else {
            // Might be completed, try to reload
            await reloadReceiptData();
          }
      }

    } catch (error) {
      console.error("[Eison-Popup] Error polling status:", error);
      summaryStatusText("狀態查詢錯誤");
    }
  };

  // Start polling
  setTimeout(poll, pollInterval);
}

// Display summary result
function displaySummaryResult(titleText, summaryText) {
  summaryStatusText("");
  document.getElementById("receiptTitle").innerText = titleText;
  document.getElementById("receipt").innerText = summaryText;
  showID("shareButton");

  console.log("[Eison-Popup] Summary result displayed");
}

// Render streaming summary text while LLM is working
function renderStreamingSummary(text) {
  document.getElementById("receiptTitle").innerText = "";
  document.getElementById("receipt").innerText = text;
}

function summaryStatusText(msg) {
  let text = document.getElementById("response");
  text.innerHTML = msg;

  if (msg == "") {
    document.getElementById("responseTitle").innerHTML = "Summary";
  } else {
    document.getElementById("responseTitle").innerHTML = "";
  }
}

function statusText(msg) {
  let text = document.getElementById("StatusText");
  text.innerHTML = msg;
}

function resetGPT() {
  // Keep this for compatibility, but it's no longer used in new architecture
  document.querySelector("#response").innerHTML = "";
  document.querySelector("#receiptTitle").innerHTML = "";
  document.querySelector("#receipt").innerHTML = "";
}
