function sendMessageToContent(message) {
  console.log("Popup: Sending message to background:", message);
  browser.runtime
    .sendMessage(message)
    .catch((e) => console.error("Error sending message from popup:", e));
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
  sendMessageToContent({ command: "getDebugText" });
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
  const parsedUrl = new URL(url);
  return parsedUrl.host;
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
      const status = await browser.runtime.sendMessage({ command: "getModelStatus" });
      const state = status?.state || "unknown";
      const progress = typeof status?.progress === "number" ? status.progress : 0;

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
  setupButtonBarActions();
  addClickListeners();
  setPlatformClassToBody();

  //runtime only
  addMessageListener();
  setupStatus();

  hideID("shareButton")
}

async function getTabURL() {
  let currentTabs = await browser.tabs.query({ active: true });

  return currentTabs[0].url;
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
    text.textContent = "載入中...";
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
    console.warn("[Eison-Popup] Failed to reload cached data:", error);
  }
}

async function cacheSummaryResultFromPopup(titleText, summaryText, urlFromMessage) {
  try {
    const url = urlFromMessage || await getTabURL();

    if (!url) {
      console.warn("[Eison-Popup] No URL available to cache summary");
      return;
    }

    await saveData("ReceiptURL", url);
    await saveData("ReceiptTitleText", titleText);
    await saveData("ReceiptText", summaryText);

    await browser.runtime.sendMessage({
      command: "cacheSummaryResult",
      url,
      titleText,
      summaryText
    });
  } catch (error) {
    console.warn("[Eison-Popup] Failed to cache summary result:", error);
  }
}

/// 請求總結 - 新架構
async function sendRunSummaryMessage() {
  showArea("SummaryContent");
  summaryStatusText("請求中...");

  try {
    const response = await browser.runtime.sendMessage({
      command: "runSummary"
    });

    console.log("[Eison-Popup] Summary response:", response);

    if (response.cached) {
      displaySummaryResult(response.titleText, response.summaryText);
      return;
    }

    if (response.error) {
      summaryStatusText("錯誤：" + response.error);
      return;
    }

    if (response.status === 'started') {
      summaryStatusText(response.message || "處理中...");
      renderStreamingSummary("");
      // Start polling for status updates
      pollSummaryStatus();
    }

  } catch (e) {
    console.error("[Eison-Popup] Error requesting summary:", e);
    summaryStatusText("通信錯誤");
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
