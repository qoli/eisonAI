// 儲存資料
async function saveData(key, data) {
  try {
    const obj = {};
    obj[key] = data;
    await browser.storage.local.set(obj);
    console.log(data);
    console.log(key + " ... save");
  } catch (error) {
    console.log(error);
  }
}

// 讀取資料
async function loadData(key, defaultValue) {
  try {
    const result = await browser.storage.local.get(key);
    const data = result[key];

    if (data === undefined) {
      if (defaultValue === undefined) {
        return "";
      } else {
        return defaultValue;
      }
    }

    return data;
  } catch (error) {
    console.log(error);
    return "";
  }
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

async function setupAPISettings() {
  await setupGPT();

  document.getElementById("APIURL").value = API_URL;
  document.getElementById("APIKEY").value = API_KEY;
  document.getElementById("APIMODEL").value = API_MODEL;
  document.getElementById("Prompt").innerText = APP_PromptText;
  document.getElementById("SystemText").innerText = APP_SystemText;
}

function checkAPI() {
  (async () => {
    let callbackText = document.getElementById("callbackText");

    let API_URL = document.getElementById("APIURL").value;
    let API_KEY = document.getElementById("APIKEY").value;
    let API_MODEL = document.getElementById("APIMODEL").value;

    if (API_URL == "") {
      callbackText.innerText = "URL empty.";
      return;
    }

    if (!API_URL.startsWith("https://")) {
      callbackText.innerText = "Please enter the HTTPS URL";
      return;
    }

    if (API_URL == "https://example.com/v1") {
      callbackText.innerText = "example.com is just an example.";
      return;
    }

    callbackText.innerText = "";

    messagesGroup = [];

    // setupSystemMessage();
    pushAssistantMessage("Ping");

    document.getElementById("SaveAPI").disabled = true;
    document.getElementById("CheckAPI").disabled = true;
    document.getElementById("CheckAPI").value = "...";

    try {
      await apiPostMessage(
        callbackText,
        function () {
          document.getElementById("SaveAPI").removeAttribute("disabled");
        },
        API_URL,
        API_KEY,
        API_MODEL
      );
    } finally {
      document.getElementById("CheckAPI").value = "Check";
      document.getElementById("CheckAPI").disabled = false;
    }
  })();
}

function saveAPI() {
  (async () => {
    let API_URL = document.getElementById("APIURL").value;
    let API_KEY = document.getElementById("APIKEY").value;
    let API_MODEL = document.getElementById("APIMODEL").value;

    await saveData("APIURL", API_URL);
    await saveData("APIKEY", API_KEY);
    await saveData("APIMODEL", API_MODEL);

    uiFocus(document.getElementById("SaveAPI"), 400);
  })();
}

function savePrompt() {
  (async () => {
    let systemText = document.getElementById("SystemText").value;
    let promptText = document.getElementById("Prompt").value;
    await saveData("APPSystemText", systemText);
    await saveData("APPPromptText", promptText);

    uiFocus(document.getElementById("SavePrompt"), 400);
  })();
}

// Mode selection handling
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

function selectMode(mode) {
  if (mode == "modeMiniIcon") {
    document.getElementById("ModeMiniIconBox").classList.add("selected");
  }

  if (mode == "modeHidden") {
    document.getElementById("ModeHiddenBox").classList.add("selected");
  }
}

async function setupModeSettings() {
  try {
    const currentMode = await loadData("AppMODE", "modeMiniIcon");
    selectMode(currentMode);
  } catch (error) {
    console.error("Error in setupModeSettings:", error);
  }
}

function saveMode() {
  (async () => {
    const selectedMode = document.querySelector(".modeSelectBox.selected");
    if (selectedMode) {
      const mode = selectedMode.getAttribute("data-params");
      await saveData("AppMODE", mode);
      uiFocus(document.getElementById("SaveMode"), 400);
    }
  })();
}

// run ...
document.addEventListener("DOMContentLoaded", async () => {
  addClickListeners();
  setupModeSelectBox();
  await setupAPISettings();
  await setupModeSettings();
});
