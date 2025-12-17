const browser = globalThis.browser ?? globalThis.chrome;

browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
  const command =
    request && typeof request === "object" && "command" in request ? request.command : undefined;

  console.log(`[Eison-Content] Received command: ${command}`, { request, sender });

  if (command === "getArticleText") {
    console.log("[Eison-Content] Processing 'getArticleText' command...");

    let response;
    try {
      const article = new Readability(document.cloneNode(true), {}).parse();
      if (article && article.textContent) {
        const body = String(article.textContent ?? "").trim();
        response = { command: "articleTextResponse", title: article.title, body };
        console.log(
          `[Eison-Content] Successfully parsed article. Title: "${article.title}", Length: ${body.length}`,
        );
      } else {
        console.error("[Eison-Content] Readability parsing failed. Article or textContent is null.");
        response = { command: "articleTextResponse", error: "Could not parse article." };
      }
    } catch (err) {
      console.error("[Eison-Content] Error parsing article with Readability:", err);
      response = {
        command: "articleTextResponse",
        error: err?.message ? String(err.message) : String(err),
      };
    }

    try {
      sendResponse?.(response);
    } catch (err) {
      console.error("[Eison-Content] Failed to sendResponse:", err);
    }

    return response;
  }
});
