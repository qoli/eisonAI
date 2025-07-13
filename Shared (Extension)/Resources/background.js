// background.js

// 監聽來自 content scripts 或 popup 的訊息
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  // 檢查訊息來源
  if (sender.tab) {
    // 訊息來自 content script (因為 sender 包含 tab 屬性)
    // 我們將它轉發給 popup
    console.log(`Background: Received from content script, forwarding to popup:`, message);
    browser.runtime.sendMessage(message).catch(e => console.error("Error sending to popup:", e));
  } else {
    // 訊息來自 popup (sender 沒有 tab 屬性)
    // 我們將它轉發給當前活動的分頁
    console.log(`Background: Received from popup, forwarding to active tab:`, message);
    browser.tabs.query({ active: true, currentWindow: true }).then(tabs => {
      if (tabs[0] && tabs[0].id) {
        browser.tabs.sendMessage(tabs[0].id, message).catch(e => console.error("Error sending to content script:", e));
      }
    });
  }
  // 返回 true 表示我們將異步發送響應
  return true;
});