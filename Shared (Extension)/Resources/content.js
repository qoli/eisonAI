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
});
