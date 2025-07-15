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

function mainApp() {
  setupButtonBarActions();
  addClickListeners();
  setPlatformClassToBody();

  //runtime only
  addMessageListener();
  setupSettingsLink();
  setupStatus();
}

// async ...
function delayRun() {
  (async () => {
    let currentTabs = await browser.tabs.query({ active: true });

    document.querySelector("#currentHOST").innerHTML = getHostFromUrl(
      currentTabs[0].url
    );
  })();
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
}, 250);

/// Pre-處理總結內容
async function sendRunSummaryMessage() {
  resetGPT();

  showArea("SummaryContent");

  summaryStatusText("讀取中");

  try {
    const response = await browser.runtime.sendMessage({
      command: "getArticleText",
    });

    console.log(response);

    handleArticleTextResponse(response);
  } catch (e) {
    console.error("[Eison-Popup] Error sending 'getArticleText' command:", e);

    summaryStatusText("通信錯誤");
  }
}

/// 處理總結內容
async function handleArticleTextResponse(response) {
  summaryStatusText("總結中");

  var assistantText = "";

  try {
    let userText = APP_PromptText + "<" + response.body + ">";

    await setupGPT(); // 確保 API 金鑰等已載入

    setupSystemMessage();
    pushAssistantMessage(assistantText);
    pushUserMessage(userText);

    let responseReceiver = document.getElementById("response");

    // 呼叫 API
    await apiPostMessage(responseReceiver, async () => {
      setupSummary();
    });
  } catch (error) {
    summaryContainer.innerHTML = `<p class="error">總結失敗：${error.message}</p>`;
  }
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
  messagesGroup = [];
  document.querySelector("#response").innerHTML = "";
  document.querySelector("#receiptTitle").innerHTML = "";
  document.querySelector("#receipt").innerHTML = "";
}
