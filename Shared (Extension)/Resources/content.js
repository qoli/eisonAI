const MAX_TOKEN = 8000;
let lastURL = "";
let APP_MODE = "";

browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
  console.log("Content: Message received", request);

  if (request.command === "getDebugText") {
    let article = new Readability(document.cloneNode(true), {}).parse();
    sendResponse({
      command: "debugTextResponse",
      body: article.textContent,
    });
    return true; //  Indicates that the response is sent asynchronously.
  }

  // You can add other commands here using if/else if
  // For example:
  // if (request.command === "runSummary") { ... }

  // Fallback for old string-based requests for now
  switch (request) {
    case "runSummary":
      runSummary();
      sendResponse({ callback: "runSummary-ok" });
      break;
    case "setMode":
      ReadabilityBarMode();
      sendResponse({ callback: "setMode-ok" });
      break;
    default:
      // Handle unexpected requests if needed
      break;
  }
  return true;
});

if (document.readyState !== "loading") {
  ready();
} else {
  document.addEventListener("DOMContentLoaded", function () {
    ready();
  });
}

function sendMessage(obj) {
  browser.runtime.sendMessage(obj);
}

// ready ...

function ready() {
  (async () => {
    let bool = await setupGPT();

    if (bool) {
      insertHtml();
    }
  })();
}

function insertHtml() {
  var readabilityBar = document.querySelector("#ReadabilityBar");

  if (readabilityBar) {
    return;
  }

  var htmlReadabilityBarCode = `
  <div id="ReadabilityBar" style="display: none;" >
  <div id="viewBar">
      <a href="javascript:void(0)" id="ReadabilityButton">
      <svg width="20" height="18" viewBox="0 0 20 18" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path
          d="M0 6.66667C0 2.98477 2.98477 0 6.66667 0H11.1111C14.793 0 17.7778 2.98477 17.7778 6.66667V11.1111C17.7778 14.793 14.793 17.7778 11.1111 17.7778H1.66667C0.746192 17.7778 0 17.0316 0 16.1111V6.66667Z"
          fill="#FFD86D" />
      <circle cx="8.88888" cy="7.22225" r="2.77778" stroke="black" stroke-width="1.11111" />
      <circle cx="16.6666" cy="7.22225" r="2.77778" stroke="black" stroke-width="1.11111" />
      <path d="M9.44446 6.94458V8.05569" stroke="black" stroke-width="1.11111" stroke-linecap="round" />
      <path d="M13.4722 6.66675H12.2222" stroke="black" stroke-width="1.11111" stroke-linecap="round" />
      <path d="M16.1111 6.94458V8.05569" stroke="black" stroke-width="1.11111" stroke-linecap="round" />
      <path d="M10.5555 12.959V12.959C12.1488 13.2533 13.7949 12.9934 15.22 12.2224V12.2224"
          stroke="black" stroke-width="1.11111" stroke-linecap="round" />
  </svg>
      </a>
  </div>
  </div>
  <!-- ReadabilityBar / End  -->
  `;

  var htmlReadabilityBoxFrameCode = `
<div id="ReadabilityBoxFrame">
<div class="readabilityBlurBox"></div>
<div id= "ReadabilityBlurBackgroundBox" class="readabilityBlurBackgroundBox"></div>
<div id="ReadabilityBox" class="ReadabilityFont" >

<div id="ReadabilityKeyboard" class="ReadabilityStyle morePadding">
<div class="readabilityInput fixMorePadding">
    <textarea id="ReadabilityTextarea" placeholder="Reply (Enter for Send)" rows="1" class="readabilityInsideStyle"></textarea>

    <div id="ReadabilityClose" class="readabilityCursorPointer readabilityInsideStyle">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M12 4L4 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"
                stroke-linejoin="round" data-noir-inline-color="">
            </path>
            <path d="M4 4L12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"
                stroke-linejoin="round" data-noir-inline-color="">
            </path>
        </svg>
    </div>

    <div id="ReadabilitySend" class="readabilityCursorPointer readabilityInsideStyle" style="display: none">
        <svg width="16" height="16" fill="none" stroke="currentColor" stroke-linecap="round"
            stroke-linejoin="round" stroke-width="2" viewBox="0 0 24 24"
            xmlns="http://www.w3.org/2000/svg">
            <path d="M10 14 21 3"></path>
            <path d="m21 3-6.5 18a.55.55 0 0 1-1 0L10 14l-7-3.5a.55.55 0 0 1 0-1L21 3Z"></path>
        </svg>
    </div>

    <div id="ReadabilityErrorResend" class="readabilityCursorPointer readabilityInsideStyle readabilityError"
    style="display: none;">
    <svg width="16" height="16" fill="none" stroke="currentColor" stroke-linecap="round"
        stroke-linejoin="round" stroke-width="3" viewBox="0 0 24 24"
        xmlns="http://www.w3.org/2000/svg">
        <path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z"></path>
        <path d="M12 8h.01"></path>
        <path d="M11 12h1v4h1"></path>
    </svg>

    <span>Retry</span>
    </div>
</div>
</div>
<!-- ReadabilityKeyboard / End  -->

<div id="ReadabilityMessageGroup">
<div id="ReadabilityFrame" class="ReadabilityStyle morePadding">
    <div id="ReadabilityLoading">
        <span>Eison · 愛省流君</span>
    </div>
    <div id="response" class="typing"></div>
    <div id="receiptTitle"></div>
    <div id="receipt"></div>
</div>

<div id="ReadabilityMessageButtons">
<div id="ReadabilityReanswer" class="readabilityMessageButton ReadabilityStyle">
    Reanswer
</div>
</div>
<!-- ReadabilityMessageButtons / End -->

</div>
<!-- ReadabilityMessageGroup / End  -->

<div id="ReadabilityUserinfo" class="ReadabilityStyle morePadding">
<div class="safariExtensionUserInfo">
    <p class="safariExtensionTitle" id="ReadabilityTitle">Title</p>
    <p class="safariExtensionHost readabilityTips" id="ReadabilityHost">
        www
    </p>
</div>
</div>
<!-- ReadabilityUserinfo / End  -->

<div style="padding-top: 150px;" ></div>

</div>
<!-- ReadabilityBox / End  -->
</div>
`;

  document.body.insertAdjacentHTML(
    "beforeend",
    htmlReadabilityBarCode + htmlReadabilityBoxFrameCode
  );

  document
    .querySelector("#ReadabilityButton")
    .addEventListener("click", runSummary);

  document
    .querySelector("#ReadabilityClose")
    .addEventListener("click", hideView);

  document
    .querySelector("#ReadabilityBlurBackgroundBox")
    .addEventListener("click", hideView);

  document
    .querySelector("#ReadabilitySend")
    .addEventListener("click", sendReply);

  document
    .querySelector("#ReadabilityReanswer")
    .addEventListener("click", reanswer);

  document
    .querySelector("#ReadabilityErrorResend")
    .addEventListener("click", resend);

  hideID("ReadabilityReanswer");

  const textArea = document.getElementById("ReadabilityTextarea");
  textArea.addEventListener("input", () => {
    let ln = textArea.value.length;
    if (ln != 0) {
      hideClose();
    } else {
      showClose();
    }
  });

  textArea.addEventListener("keydown", function (event) {
    if (event.keyCode === 13 && !event.shiftKey) {
      event.preventDefault(); // 防止換行
      sendReply();
    }
  });

  ReadabilityBarMode();
}

function ReadabilityBarMode() {
  (async () => {
    APP_MODE = await loadData("AppMODE", "modeMiniIcon");

    if (APP_MODE == "modeMiniIcon") {
      showID("ReadabilityBar");
    }

    if (APP_MODE == "modeHidden") {
      hideID("ReadabilityBar");
    }
  })();
}

function reanswer() {
  removeReadabilityReplies();
  resetGPT();
  runSummary();
}

// userReply:Bool
function insertMessage(message, userReply) {
  var parentDiv = document.getElementById("ReadabilityMessageGroup");

  // 创建新的 div 元素
  var newDiv = document.createElement("div");
  var timestamp = Date.now(); // 获取当前时间戳
  newDiv.id = "ReplyMessage" + timestamp;

  if (userReply) {
    newDiv.className =
      "ReadabilityStyle morePadding readabilityReply readabilityUserReply";
  } else {
    newDiv.className = "ReadabilityStyle morePadding readabilityReply";
  }

  newDiv.innerText = message;

  parentDiv.appendChild(newDiv);

  document.getElementById("ReadabilityTextarea").value = "";
  showClose();
}

function sendReply() {
  let textValue = document.getElementById("ReadabilityTextarea").value;

  if (textValue.length <= 0) {
    return;
  }

  insertMessage(textValue, true);
  setTimeout(() => {
    insertMessage("", false);
    sendReplytext(textValue);
  }, 500);
}

function showClose() {
  document.querySelector("#ReadabilityClose").style.display = "flex";
  document.querySelector("#ReadabilitySend").style.display = "none";
}

function hideClose() {
  document.querySelector("#ReadabilityClose").style.display = "none";
  document.querySelector("#ReadabilitySend").style.display = "flex";
}

function hideView() {
  document.body.style.overflow = "auto";

  document.querySelector("#ReadabilityBoxFrame").style.display = "none";
  if (APP_MODE == "modeMiniIcon") {
    showID("ReadabilityBar", "flex");
  }
}
function runSummary() {
  document.querySelector("#ReadabilityBoxFrame").style.display = "flex";
  document.querySelector("#ReadabilityBar").style.display = "none";
  document.body.style.overflow = "hidden";
  callGPT();
}

function resetGPT() {
  messagesGroup = [];
}

function callGPT() {
  console.log("Content: Starting callGPT function");
  let article = new Readability(document.cloneNode(true), {}).parse();

  if (!article) {
    console.log("Content: No article content found");
    return;
  }

  // reset
  if (lastURL != window.location.href) {
    console.log("Content: URL changed, resetting GPT");
    resetGPT();
  }

  if (messagesGroup.length > 0) {
    console.log("Content: Messages group not empty, skipping");
    return;
  }

  document.querySelector("#response").innerHTML = "";
  let articleText = postProcessText(article.textContent);
  console.log("Content: Article text processed, length:", articleText.length);

  document.querySelector("#receiptTitle").innerHTML = "";
  document.querySelector("#receipt").innerHTML = "";
  document.querySelector("#ReadabilityTitle").innerHTML = article.title;
  document.querySelector(
    "#ReadabilityHost"
  ).innerHTML = `${window.location.host} / ${API_MODEL}`;

  console.log("Content: Calling GPT Summary");
  callGPTSummary(articleText);
}
