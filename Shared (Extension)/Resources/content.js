browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
  console.log(`[Eison-Content] Received command: ${request.command}`, { request, sender });

  if (request.command === "getArticleText") {
    console.log("[Eison-Content] Processing 'getArticleText' command...");
    try {
      let article = new Readability(document.cloneNode(true), {}).parse();
      if (article && article.textContent) {
        console.log(`[Eison-Content] Successfully parsed article. Title: "${article.title}", Length: ${article.textContent.length}`);

        // Send response to background script instead of popup
        browser.runtime.sendMessage({
          command: "articleTextResponse",
          body: article.textContent,
          title: article.title,
        });

        sendResponse({ command: "articleTextResponse", status: "sent" });
      } else {
        console.warn("[Eison-Content] Readability parsing failed. Article or textContent is null.");
        browser.runtime.sendMessage({
          command: "articleTextResponse",
          error: "Could not parse article."
        });
        sendResponse({ command: "articleTextResponse", error: "Could not parse article." });
      }
    } catch (e) {
      console.error("[Eison-Content] Error parsing article with Readability:", e);
      browser.runtime.sendMessage({
        command: "articleTextResponse",
        error: e.message
      });
      sendResponse({ command: "articleTextResponse", error: e.message });
    }
    return true;
  }

  if (request.command === "processSummary") {
    console.log("[Eison-Content] Processing 'processSummary' command...");
    try {
      processSummaryRequest(request.articleText, request.articleTitle);
      sendResponse({ command: "processSummaryResponse", status: "started" });
    } catch (e) {
      console.error("[Eison-Content] Error starting summary processing:", e);
      browser.runtime.sendMessage({
        command: "summaryError",
        error: e.message
      });
      sendResponse({ command: "processSummaryResponse", error: e.message });
    }
    return true;
  }
});

// Process summary request with LLM API
async function processSummaryRequest(articleText, articleTitle) {
  console.log("[Eison-Content] Starting LLM summary processing...");

  try {
    // Reset GPT state
    messagesGroup = [];

    // Setup API configuration
    await setupGPT();

    // Build user message
    let userText = APP_PromptText + "<" + articleText + ">";

    // Setup messages
    setupSystemMessage();
    pushAssistantMessage("");
    pushUserMessage(userText);

    // Create a virtual response element for collecting the response
    let responseCollector = {
      innerText: "",
      innerHTML: ""
    };

    // Stream partial output back to background/popup
    let lastStreamAt = 0;
    responseCollector.onToken = (text) => {
      const now = Date.now();
      const STREAM_INTERVAL = 250;
      if (now - lastStreamAt < STREAM_INTERVAL) {
        return;
      }
      lastStreamAt = now;

      browser.runtime.sendMessage({
        command: "summaryStream",
        text
      });
    };

    // Call LLM API
    await apiPostMessage(responseCollector, () => {
      handleSummaryComplete(responseCollector.innerText, articleTitle);
    });

  } catch (error) {
    console.error("[Eison-Content] Error in LLM processing:", error);
    browser.runtime.sendMessage({
      command: "summaryError",
      error: error.message
    });
  }
}

// Handle summary completion
async function handleSummaryComplete(resultText, articleTitle) {
  try {
    console.log("[Eison-Content] Processing LLM response...");

    // Process the result text similar to original setupSummary
    let receiptTitleText = removeBR(extractSummary(resultText));

    let receiptText = excludeSummary(resultText)

    // Send completion message to background
    browser.runtime.sendMessage({
      command: "summaryComplete",
      titleText: receiptTitleText,
      summaryText: receiptText,
      originalTitle: articleTitle
    });

    console.log("[Eison-Content] Summary completion sent to background");

  } catch (error) {
    console.error("[Eison-Content] Error handling summary completion:", error);
    browser.runtime.sendMessage({
      command: "summaryError",
      error: error.message
    });
  }
}
