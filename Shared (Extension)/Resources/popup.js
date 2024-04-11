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
function sendRunSummaryMessage() {
  sendMessageToContent("runSummary");
  uiFocus(document.getElementById("SendRunSummaryMessage"), 400);
}

function selectMode(modeName) {
  console.log("select", modeName);
}

function openSettings() {
  console.log("openSettings");
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

function setupModeSelectBox() {
  function handleModeSelectBoxClick() {
    const modeSelectBoxes = document.querySelectorAll(".modeSelectBox");

    modeSelectBoxes.forEach((box) => {
      box.classList.remove("selected");
    });

    this.classList.add("selected");
  }

  const modeSelectBoxes = document.querySelectorAll(".modeSelectBox");
  modeSelectBoxes.forEach((box) => {
    box.addEventListener("click", handleModeSelectBoxClick);
  });
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
  let icon = document.getElementById("StatusIcon");
  let text = document.getElementById("StatusText");

  (async () => {
    let apiURL = await loadData("APIURL", "");
    let apiKey = await loadData("APIKEY", "");

    let newURL = apiURL.replace("v1/chat/completions", "v1/models");

    let bool = await setupGPT();
    if (bool) {
      text.innerHTML = "已設定";
      try {
        const response = await fetch(newURL, {
          headers: {
            Authorization: "Bearer " + apiKey,
          },
        });

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

function mainApp() {
  setupModeSelectBox();
  setupButtonBarActions();
  addClickListeners();

  //runtime only
  addMessageListener();
  setupSettingsLink();
  setupStatus();
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

// Run app
mainApp();

setTimeout(() => {
  delayCall();
}, 250);
