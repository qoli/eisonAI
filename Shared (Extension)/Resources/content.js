browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
  console.log(`[Eison-Content] Received command: ${request.command}`, { request, sender });

  if (request.command === "getArticleText") {
    console.log("[Eison-Content] Processing 'getArticleText' command...");
    try {
      let article = new Readability(document.cloneNode(true), {}).parse();
      if (article && article.textContent) {
        console.log(`[Eison-Content] Successfully parsed article. Title: "${article.title}", Length: ${article.textContent.length}`);

        sendResponse({
          command: "articleTextResponse",
          title: article.title,
          body: article.textContent,
        });
      } else {
        console.error("[Eison-Content] Readability parsing failed. Article or textContent is null.");
        sendResponse({ command: "articleTextResponse", error: "Could not parse article." });
      }
    } catch (e) {
      console.error("[Eison-Content] Error parsing article with Readability:", e);
      sendResponse({ command: "articleTextResponse", error: e.message });
    }
    return true;
  }
});
