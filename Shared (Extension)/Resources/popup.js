function sendMessageToContent(message) {
  console.log("Popup: Sending message to background:", message);
  browser.runtime
    .sendMessage(message)
    .catch((e) => console.error("Error sending message from popup:", e));
}

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

function saveAPIConfig() {
  (async () => {
    let url = document.querySelector("#APIURL").value;
    let key = document.querySelector("#APIKEY").value;
    let model = document.querySelector("#APIMODEL").value;

    await saveData("APIURL", url);
    await saveData("APIKEY", key);
    await saveData("APIMODEL", model);

    document.querySelector(
      "#ReadabilityText"
    ).innerHTML = `${url} + ${key} + ${model} `;
  })();
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

function setupSettingsLink() {
  var settingsLink = document.getElementById("SettingsLink");

  if (settingsLink) {
    let href = browser.runtime.getURL("settings.html");
    settingsLink.href = href;
  }
}

function setupStatus() {
  let icon = document.getElementById("StatusIcon");
  let text = document.getElementById("StatusText");

  (async () => {
    let apiURL = await loadData("APIURL", "");
    let apiKey = await loadData("APIKEY", "");

    let bool = await setupGPT();
    if (bool) {
      text.innerHTML = "已設定";
      try {
        let response;
        // Check if using Google Gemini API
        if (apiURL.includes("generativelanguage.googleapis.com")) {
          let newURL = `${apiURL}/models?key=${apiKey}`;
          response = await fetch(newURL);
        } else {
          // Default case for OpenAI and others
          let newURL = `${apiURL}/models`;
          response = await fetch(newURL, {
            headers: {
              Authorization: "Bearer " + apiKey,
            },
          });
        }

        if (response.ok) {
          setStatus("normal");
          text.innerHTML = "通過測試";
        } else {
          const { status, statusText } = response;
          setStatus("error");
          text.innerHTML = "測試失敗 " + status + statusText;
        }
      } catch (error) {
        setStatus("warming");
        text.innerHTML = error;
      }
    } else {
      text.innerHTML = "請先設定 ChatGPT API";
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
  setupSettingsLink();
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
  let tabURL = await loadData("ReceiptURL", "");

  if (tabURL != (await getTabURL())) {
    return;
  }

  let receiptTitleText = await loadData("ReceiptTitleText", "");
  let receiptText = await loadData("ReceiptText", "");

  if (receiptText != "") {
    showArea("SummaryContent");

    document.getElementById("receiptTitle").innerHTML = receiptTitleText;
    document.getElementById("receipt").innerHTML = receiptText;

    // Ensure status reflects completion when cached data is shown
    summaryStatusText("總結完畢");
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
    
    if (response.error) {
      summaryStatusText("錯誤：" + response.error);
      return;
    }
    
    if (response.cached) {
      // Display cached result immediately
      displaySummaryResult(response.titleText, response.summaryText);
      return;
    }
    
    if (response.status === 'started') {
      summaryStatusText(response.message || "處理中...");
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
          summaryStatusText("總結失敗");
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
  document.getElementById("response").innerHTML = "";
  document.getElementById("receiptTitle").innerHTML = titleText;
  document.getElementById("receipt").innerHTML = summaryText;
  showID("shareButton");
  
  console.log("[Eison-Popup] Summary result displayed");
}

function summaryStatusText(msg) {
  let text = document.getElementById("response");
  text.innerHTML = msg;
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
