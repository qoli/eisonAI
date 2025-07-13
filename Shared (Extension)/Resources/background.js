browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  // 監聽來自 popup 的請求
  if (message.command && !sender.tab) {
    console.log(`[Eison-Background] Forwarding command '${message.command}' from popup to content script.`);
    
    // 轉發訊息到當前的 tab
    browser.tabs.query({ active: true, currentWindow: true }).then(tabs => {
      if (tabs[0] && tabs[0].id) {
        // 發送訊息給 content script，並等待它的回應 (sendResponse)
        browser.tabs.sendMessage(tabs[0].id, message)
          .then(response => {
            // 收到了 content script 的回應，現在把它回傳給 popup
            console.log(`[Eison-Background] Received response from content script, sending back to popup.`, response);
            sendResponse(response);
          })
          .catch(e => {
            console.error("[Eison-Background] Error forwarding message to content script or receiving response:", e);
            sendResponse({ error: e.message });
          });
      } else {
        console.error("[Eison-Background] No active tab found.");
        sendResponse({ error: "No active tab found." });
      }
    });

    // 返回 true 是至關重要的，因為我們是異步地發送回應
    return true;
  }
});