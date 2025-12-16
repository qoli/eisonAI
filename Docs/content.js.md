# Content Script：`content.js`

本專案的 content script **只負責「擷取頁面正文」**，不做推理、不插 UI、不做遠端 API。

對應檔案：

- `Shared (Extension)/Resources/contentReadability.js`：提供 `Readability`
- `Shared (Extension)/Resources/content.js`：接收訊息並回傳文章文本

## 載入方式（manifest）

`Shared (Extension)/Resources/manifest.json` 會在 `content_scripts` 依序載入：

1. `contentReadability.js`
2. `content.js`

並附帶 `readability.css`（Readability 相關樣式）。

## 訊息協定（popup → content script）

### Request

```js
{ command: "getArticleText" }
```

### Response（成功）

```js
{
  command: "articleTextResponse",
  title: "<Readability title>",
  body: "<Readability textContent>"
}
```

### Response（失敗）

```js
{ command: "articleTextResponse", error: "<message>" }
```

## 行為說明

- 使用 `Readability(document.cloneNode(true)).parse()` 解析正文，避免直接修改原 DOM。
- 透過 `browser.runtime.onMessage.addListener` 監聽 popup 的請求。
- 會在 console 輸出 `[Eison-Content] ...` 前綴 log，方便在 Safari Develop 工具中定位。

## 如何擴充新的 command

1. 在 `Shared (Extension)/Resources/content.js` 新增 `request.command === "<newCommand>"` 分支。
2. 在 popup 端（`Shared (Extension)/Resources/webllm/popup.js`）呼叫 `browser.tabs.sendMessage(tabId, { command: "<newCommand>" })`。
3. 保持 response 物件足夠小（避免 Safari message size 限制）。
