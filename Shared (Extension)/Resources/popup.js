function sendMessageToContent(message) {
  browser.tabs.query({ active: true }).then(function (currentTabs) {
    if (currentTabs[0].id >= 0) {
      browser.tabs.sendMessage(currentTabs[0].id, message);
    }
  });
}

function getDebugText() {
  sendMessageToContent("getDebugText");
}

function addMessageListener() {
  browser.runtime.onMessage.addListener(function (
    request,
    sender,
    sendResponse
  ) {
    console.log("MessageListener", request);

    if (request.message) {
      if (request.message == "debugText") {
        document.querySelector("#ReadabilityText").innerHTML = request.body;
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

//

function getHostFromUrl(url) {
  const parsedUrl = new URL(url);
  return parsedUrl.host;
}

function saveAPIConfig() {
  (async () => {
    let url = document.querySelector("#APIURL").value;
    let key = document.querySelector("#APIKEY").value;
    let model = document.querySelector("#APIMODEL").value;
    let advModel = document.querySelector("#APIADVMODEL").value;

    await saveData("APIURL", url);
    await saveData("APIKEY", key);
    await saveData("APIMODEL", model);
    await saveData("APIADVMODEL", advModel);

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

function setupSettingsLink() {
  var settingsLink = document.getElementById("SettingsLink");

  if (settingsLink) {
    let href = browser.runtime.getURL("settings.html");
    settingsLink.href = href;
  }
}

function setupStatus() {
  let text = document.getElementById("StatusText");

  (async () => {
    let apiURL = await loadData("APIURL", "");
    let apiKey = await loadData("APIKEY", "");

    let bool = await setupGPT();
    if (bool) {
      text.innerHTML = "";
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
        } else {
          const { status, statusText } = response;
          setStatus("error");
          text.innerHTML = "Failed " + status + statusText;
        }
      } catch (error) {
        setStatus("warming");
        text.innerHTML = error;
      }
    } else {
      text.innerHTML = "Please setup API";
    }
  })();
}

function mainApp() {
  setupButtonBarActions();
  addClickListeners();
  setPlatformClassToBody();

  //runtime only
  addMessageListener();
  setupSettingsLink();
  setupStatus();
  sendMessageToContent("runSummary");
}

// async ...
function delayCall() {
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
  delayCall();
}, 250);
