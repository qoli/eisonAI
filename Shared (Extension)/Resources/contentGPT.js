let lastReplyMessage = "";
let messagesGroup = [];

let API_URL = "";
let API_KEY = "";
let API_MODEL = "";
let APP_PromptText = "";
let APP_SystemText = "";

async function setupGPT() {
  let systemText = `你是幫助用戶理解網頁內容的專家。`;

  let thisPrompt = `為最後提供的文字內容進行按要求的總結。如果是其他語言，請翻譯到繁體中文。
請嚴格按照下面的格式進行輸出，在格式以外的地方，不需要多餘的文本內容。

這裡是格式指導：
總結：
簡短的一句話概括內容，此單獨佔用一行，記得輸出換行符號；
要點：
對文字內容提出多個要點內容，並每一個要點都附加一個裝飾用的 emoji，每一個要點佔用一行，注意記得輸出換行符號；

下面為需要總結的文字內容：`;

  API_URL = await loadData("APIURL", "");
  API_KEY = await loadData("APIKEY", "");
  API_MODEL = await loadData("APIMODEL", "gpt-3.5-turbo");
  APP_PromptText = await loadData("APPPromptText", thisPrompt);
  APP_SystemText = await loadData("APPSystemText", systemText);

  if (API_URL === "") {
    console.error("SetupGPT: Failed - Missing API URL");
    return false;
  }

  return true;
}

async function sendReplytext(text) {
  pushUserMessage(text);
  let elem = getMaxTimestampElem();

  await apiPostMessage(elem, function () {
    markdownMessage(elem);
  });
}

function resend() {
  (async () => {
    let elem = getMaxTimestampElem();

    if (elem == null) {
      reanswer();
    } else {
      await apiPostMessage(elem, function () {
        markdownMessage(elem);
      });
    }
  })();
}

function getMaxTimestampElem() {
  var elements = document.querySelectorAll('[id^="ReplyMessage"]');
  var maxTimestamp = -Infinity;
  var maxTimestampDiv = null;

  Array.from(elements).forEach(function (element) {
    var id = element.id;
    var timestamp = parseInt(id.replace("ReplyMessage", ""));
    if (timestamp > maxTimestamp) {
      maxTimestamp = timestamp;
      maxTimestampDiv = element;
    }
  });

  return maxTimestampDiv;
}

function pushAssistantMessage(text) {
  if (text.length <= 0) {
    return;
  }

  const messageWithRole = {
    role: "assistant",
    content: text,
  };

  messagesGroup.push(messageWithRole);
}

function pushUserMessage(text) {
  if (text.length <= 0) {
    return;
  }

  const messageWithRole = {
    role: "user",
    content: text,
  };

  console.log("UserMessage / length", text.length);

  messagesGroup.push(messageWithRole);
}

function setupSystemMessage() {
  let systemText = APP_SystemText;
  const systemMessage = {
    role: "system",
    content: systemText,
  };
  if (systemText.length > 0) {
    messagesGroup.push(systemMessage);
  }
}

// GPT 總結
async function callGPTSummary(inputText) {
  let responseElem = document.getElementById("response");
  lastReplyMessage = "";
  let assistantText = "";

  try {
    if (!inputText || inputText.length <= 0) {
      console.error("GPT Summary - Empty input text");
      typeSentence("錯誤：無法獲取頁面內容，請重新載入後再試", responseElem);
      return;
    }

    callLoading();
    showID("response");

    let userText = APP_PromptText + "<" + inputText + ">";
    setupSystemMessage();
    pushAssistantMessage(assistantText);
    pushUserMessage(userText);

    await apiPostMessage(responseElem, function () {
      hideID("response");
      hideLoading();
      setupSummary();
      showID("ReadabilityReanswer");
      uiFocus(document.getElementById("ReadabilityFrame"));
      lastURL = window.location.href;
    });
  } catch (error) {
    console.error("GPT Summary - Error:", error);
    typeSentence(
      "API 調用錯誤：" + error.message + "\n請檢查 API 設定或重試",
      responseElem
    );
    showID("ReadabilityErrorResend", "flex");
  } finally {
    if (!responseElem.innerText) {
      hideLoading();
    }
  }
}

async function apiPostMessage(
  responseElem,
  callback,
  appAPIUrl,
  appAPIKey,
  appAPIModel
) {
  if (appAPIUrl === undefined) {
    appAPIUrl = API_URL;
  }

  if (appAPIKey === undefined) {
    appAPIKey = API_KEY;
  }

  if (appAPIModel === undefined) {
    appAPIModel = API_MODEL;
  }

  if (!appAPIUrl) {
    console.error("API Post - Missing API URL");
    typeSentence("錯誤：API 設定不完整，請檢查 API URL 設定。", responseElem);
    showID("ReadabilityErrorResend", "flex");
    return;
  }

  lastReplyMessage = ""; //reset LastMessage

  // toggleClass(responseElem, "ReadabilityMessageTyping");

  try {
    // Handle different API endpoints
    let fetchURL = `${appAPIUrl}/chat/completions`;
    let headers = {
      Authorization: "Bearer " + appAPIKey,
      "Content-Type": "application/json",
    };
    let requestBody = {};

    // Check if using Gemini API
    if (appAPIUrl.includes("generativelanguage.googleapis.com")) {
      // Adjust for Gemini API format
      fetchURL = `${appAPIUrl}/models/${appAPIModel}:streamGenerateContent`;
      headers = {
        "Content-Type": "application/json",
        "x-goog-api-key": appAPIKey,
      };

      // Convert message format for Gemini
      // Filter out system messages and map roles
      let geminiContents = messagesGroup
        .filter((msg) => msg.role !== "system") // Remove system message
        .map((msg) => ({
          role: msg.role === "assistant" ? "model" : msg.role, // Convert assistant to model
          parts: [{ text: msg.content }],
        }));

      // Gemini requires the conversation history to end with a 'user' role message.
      // If the last message is 'model', remove it.
      if (
        geminiContents.length > 0 &&
        geminiContents[geminiContents.length - 1].role === "model"
      ) {
        geminiContents.pop(); // Remove the last message if it's from the model
      }

      // Ensure not sending empty contents after filtering
      if (geminiContents.length === 0) {
        // Add a test user message if contents are empty
        geminiContents.push({
          role: "user",
          parts: [{ text: "Hello" }],
        });
        console.log("Added test message to empty Gemini contents");
      }

      // Ensure the last message is from the user (Gemini requirement)
      if (
        geminiContents.length > 0 &&
        geminiContents[geminiContents.length - 1].role === "model"
      ) {
        // Add a dummy user message if the last message is from the model
        geminiContents.push({
          role: "user",
          parts: [{ text: "Please continue" }],
        });
        console.log(
          "Added continuation prompt since last message was from model"
        );
      }

      requestBody = {
        contents: geminiContents,
        tools: [
          {
            google_search: {},
          },
        ],
        generationConfig: {
          temperature: 0.5,
        },
      };
    } else {
      // Standard OpenAI/compatible API format
      requestBody = {
        stream: true,
        model: appAPIModel,
        messages: messagesGroup,
        temperature: 0.5,
      };

      // Add plugins if using OpenRouter
      if (appAPIUrl.startsWith("https://openrouter.ai")) {
        requestBody.plugins = [{ id: "web" }];
      }
    }

    const response = await fetch(fetchURL, {
      method: "POST",
      headers: headers,
      body: JSON.stringify(requestBody),
    });

    const reader = response.body
      ?.pipeThrough(new TextDecoderStream())
      .getReader();

    if (!reader) {
      typeSentence("pipeThrough getReader is nil", responseElem);
      return;
    }

    let geminiBuffer = ""; // Buffer for accumulating Gemini response data

    while (true) {
      // eslint-disable-next-line no-await-in-loop
      const { value, done } = await reader.read();
      if (done) break;
      let dataDone = false;

      // Handle different API formats differently
      if (appAPIUrl.includes("generativelanguage.googleapis.com")) {
        // Gemini streaming format handling
        geminiBuffer += value;

        // Process complete JSON objects in the buffer
        try {
          // Look for complete JSON objects that might be in the buffer
          const jsonObjects = extractJsonObjects(geminiBuffer);

          for (const jsonData of jsonObjects) {
            if (
              jsonData.candidates &&
              jsonData.candidates[0] &&
              jsonData.candidates[0].content
            ) {
              const content = jsonData.candidates[0].content;

              if (content.parts && content.parts.length > 0) {
                content.parts.forEach((part) => {
                  if (part.text) {
                    typeSentence(part.text, responseElem);
                  }
                });
              }

              if (jsonData.candidates[0].finishReason === "STOP") {
                dataDone = true;
              }
            }
          }

          // Clean buffer after processing
          if (jsonObjects.length > 0) {
            const lastJsonEndPos = geminiBuffer.lastIndexOf("}") + 1;
            geminiBuffer = geminiBuffer.substring(lastJsonEndPos);
          }
        } catch (error) {
          console.error("Error processing Gemini streaming response:", error);
        }
      } else {
        // OpenAI-like streaming format (line-based)
        const arr = value.split("\n");

        arr.forEach((data) => {
          if (data.length === 0) return; // ignore empty message
          if (data.startsWith(":")) return; // ignore sse comment message
          if (data.startsWith("id")) return; //

          if (!data.startsWith("data")) {
            try {
              let errorJSON = JSON.parse(data);
              typeSentence(
                "\nError: " +
                  (errorJSON.error?.message || JSON.stringify(errorJSON)),
                responseElem
              );

              showID("ReadabilityErrorResend", "flex");
              return;
            } catch (error) {}
          }

          if (data === "data: [DONE]") {
            dataDone = true;
            return;
          }

          try {
            const jsonData = JSON.parse(data.substring(6));
            let choice = jsonData.choices[0];
            let token = choice.delta?.content;

            if (token !== undefined) {
              typeSentence(token, responseElem);
            }

            if (choice.finish_reason === "stop") {
              dataDone = true;
            }
          } catch (error) {
            console.error("Error parsing OpenAI streaming response:", error);
          }
        });
      }

      if (dataDone) {
        console.log("#dataDone", dataDone);
        pushAssistantMessage(lastReplyMessage);

        // 在适当的时候调用回调函数
        if (callback && typeof callback === "function") {
          callback();
        }
        break;
      }
    }

    // Helper function to extract complete JSON objects from a string
    function extractJsonObjects(str) {
      const results = [];
      let startPos = str.indexOf("{");

      while (startPos !== -1) {
        try {
          // Find a potential complete JSON object
          let openBraces = 0;
          let endPos = startPos;

          for (let i = startPos; i < str.length; i++) {
            if (str[i] === "{") openBraces++;
            else if (str[i] === "}") openBraces--;

            if (openBraces === 0) {
              endPos = i + 1;
              break;
            }
          }

          if (openBraces !== 0) {
            // Incomplete JSON, wait for more data
            break;
          }

          // Extract the JSON string and parse it
          const jsonStr = str.substring(startPos, endPos);
          const jsonObj = JSON.parse(jsonStr);
          results.push(jsonObj);

          // Move to the next potential JSON object
          startPos = str.indexOf("{", endPos);
        } catch (e) {
          // If parsing fails, move to the next opening brace
          startPos = str.indexOf("{", startPos + 1);
        }
      }

      return results;
    }

    if (!response.ok) {
      showID("ReadabilityErrorResend", "flex");
      typeSentence("Status: " + response.status, responseElem);
    }
  } catch (error) {
    showID("ReadabilityErrorResend", "flex");
    typeSentence("Error: " + error.message, responseElem);
  } finally {
    removeClass(responseElem, "ReadabilityMessageTyping");
  }
}

function markdownMessage(elementReference) {
  elementReference.innerHTML = marked.parse(postProcessText(lastReplyMessage));
}

function typeSentence(sentence, elementReference) {
  if (sentence === undefined) return;

  lastReplyMessage += sentence;
  if (elementReference) {
    elementReference.innerText = lastReplyMessage;
    if (typeof elementReference.onToken === "function") {
      elementReference.onToken(lastReplyMessage);
    }
  }

  return;
}

function removeBR(text) {
  return text.trim().replaceAll("<br>", "");
}

function extractSummary(text) {
  const regex = /總結：([\s\S]+?)要點：/;
  const match = text.match(regex);
  if (match && match.length >= 2) {
    return match[1];
  }
  return "";
}

function excludeSummary(text) {
  const regex = /總結：([\s\S]+?)要點：/;
  const excludedText = text.replace(regex, "");
  return excludedText;
}

function formatMarkdown(inputString) {
  return inputString.replace(/^(<p><br>)/, "<p>").replace(/<br><br>/g, "<br>");
}

function callLoading() {
  document.querySelector("#ReadabilityLoading").style.display = "flex";
  document.querySelector("#ReadabilityLoading").classList.remove("fadeOut");
  document.querySelector("#ReadabilityLoading").classList.add("fadeIn");
}

function hideLoading() {
  document.querySelector("#ReadabilityLoading").classList.remove("fadeIn");
  document.querySelector("#ReadabilityLoading").classList.add("fadeOut");

  setTimeout(() => {
    document.querySelector("#ReadabilityLoading").style.display = "none";
  }, 800);
}

function hideID(idName) {
  try {
    document.querySelector("#" + idName).style.display = "none";
  } catch (error) {}
}

function showID(idName, display) {
  if (display === undefined) {
    display = "block";
  }
  try {
    document.querySelector("#" + idName).style.display = display;
  } catch (error) {}
}

function uiFocus(responseElem, delayMS) {
  if (delayMS === undefined) {
    delayMS = 1600;
  }

  responseElem.classList.add("readabilityDone");
  setTimeout(() => {
    responseElem.classList.remove("readabilityDone");
  }, delayMS);
}

function toggleClass(element, className) {
  if (element && element.classList) {
    if (element.classList.contains(className)) {
      element.classList.remove(className);
    } else {
      element.classList.add(className);
    }
  }
}

function removeClass(element, className) {
  if (element && element.classList && element.classList.contains(className)) {
    element.classList.remove(className);
  }
}

function removeReadabilityReplies() {
  var elements = document.getElementsByClassName("readabilityReply");

  while (elements.length > 0) {
    elements[0].parentNode.removeChild(elements[0]);
  }
}

function postProcessText(text) {
  return text
    .trim()
    .replaceAll("  ", "")
    .replaceAll("\t", "")
    .replaceAll("\n\n", "")
    .replaceAll(",,", "")
    .replaceAll("undefined", "");
}

// 儲存資料
async function saveData(key, data) {
  try {
    const obj = {};
    obj[key] = data;
    await browser.storage.local.set(obj);
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
    return defaultValue;
  }
}

async function isURLReachable(url) {
  try {
    const response = await fetch(url, { method: "POST" });
    if (response.ok) {
      return { reachable: true };
    } else {
      return { reachable: false, error: `HTTP Error ${response.status}` };
    }
  } catch (error) {
    return { reachable: false, error: "Error occurred" };
  }
}
