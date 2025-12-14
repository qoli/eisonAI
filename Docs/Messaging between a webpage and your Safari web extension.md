Messaging between a webpage and your Safari web extension
Configure your extension to enable messaging from webpages, and then update your extension to handle messages.
Overview
With messaging, you can allow a webpage to control features in your extension based on events or data, or you can allow a webpage to request and use data from your extension.
First, configure your web extension to receive messages from a list of webpages that you specify. Then, add functionality to handle messages that a webpage sends to your extension, and respond to that webpage.
Enable messaging from webpages in your manifest
To enable messaging from webpages, add externally_connectable to your extension’s manifest.json file. Include a list of webpages that you want to send messages to your extension in the matches attribute.
{
"externally_connectable": {
"matches": [ "*://*.apple.com/*" ]
}
}
If you don’t provide the matches attribute or you provide an empty list, no webpages can send messages to your extension.
Send messages from a webpage to your extension
Send a message from a webpage to your extension using browser.runtime.sendMessage. Provide your extension’s identifier, the message data, and a closure to handle the response from your extension.
browser.runtime.sendMessage("com.example.connectable-ext.Extension (team_identifier)", {greeting: "Hello!"}, function(response) {
console.log("Received response from the background page:");
console.log(response.farewell);
});
Your extension’s identifier is a string that consists of the bundle identifier for your extension, and your team identifier in parentheses. Find your team identifier in your developer account in the Membership tab under Account Settings. Note that extension identifiers can be different across browsers. For more information about finding the right extension identifier for Safari, see What’s new in Safari web extensions.
In your extension’s background page, listen for incoming messages webpages and send responses.
browser.runtime.onMessageExternal.addListener(function(message, sender, sendResponse) {
console.log("Received message from the sender:");
console.log(message.greeting);
sendResponse({farewell: "Goodbye from the background page!"});
});
Set up a port for messages between a webpage and your extension
If your extension needs to handle more continuous data from a webpage, establish a port connection between the webpage and your extension.
let port = browser.runtime.connect("extensionID");
In your extension’s background page, listen for incoming port connection requests.
browser.runtime.onConnectExternal.addListener(function(port) {
console.log("Connection request received!");
});
Then, use port.postMessage to send a message through the port, and port.onMessage to receive a message from the port.

# 網頁與 Safari 網路擴展之間的訊息傳遞

這篇文章解釋了如何在 Safari 網路擴展中實現網頁和擴展之間的訊息傳遞。

## 主要內容

- **啟用網頁訊息傳遞**

  - 在擴展的 `manifest.json` 檔案中添加 `externally_connectable` 屬性。
  - 指定允許傳送訊息的網頁列表（使用 `matches` 屬性）。
  - 如果未提供 `matches` 屬性或列表為空，則沒有網頁可以傳送訊息給擴展。

- **從網頁傳送訊息給擴展**

  - 使用 `browser.runtime.sendMessage` 方法。
  - 需要提供擴展的識別碼、訊息數據，以及一個處理擴展回應的回調函數。
  - 擴展識別碼由擴展的 bundle 識別碼和團隊識別碼組成。

- **在擴展中處理來自網頁的訊息**

  - 在擴展的背景頁面中，使用 `browser.runtime.onMessageExternal.addListener` 來監聽來自網頁的訊息。
  - 該監聽器會接收訊息、發送者資訊，並可以透過 `sendResponse` 函數向網頁傳送回應。

- **建立網頁與擴展之間的連接埠**
  - 如果需要處理更連續的數據流，可以建立一個連接埠（port）連接。
  - 在網頁中使用 `browser.runtime.connect("extensionID")` 建立連接。
  - 在擴展的背景頁面中，使用 `browser.runtime.onConnectExternal.addListener` 監聽傳入的連接埠請求。
  - 一旦建立連接，可以使用 `port.postMessage` 傳送訊息，並使用 `port.onMessage` 接收來自連接埠的訊息。

這份指南提供了在 Safari 網路擴展中實現網頁與擴展之間雙向通訊的詳細說明。
