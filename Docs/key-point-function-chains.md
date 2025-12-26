# Key-point 函數鏈路總覽（含長文 Pipeline Spec）

本文件依據 `Docs/key-point.md` 並整合 `Spec/LONG_DOCUMENT_READING_PIPELINE.md`，整理 Key-point 相關功能在專案中的**主要函數鏈路**（Safari Extension popup 與 iOS App），包含長文 Pipeline 的分流、分段與保存流程。

> 範圍：與 Key-point 產生摘要/閱讀錨點、儲存 Raw Library、顯示結果直接相關的鏈路。

---

## A. Safari Extension（popup）函數鏈路

### A1. 入口與自動摘要主鏈路
1. `Shared (Extension)/Resources/manifest.json`
   - `action.default_popup` → `webllm/popup.html`
2. `Shared (Extension)/Resources/webllm/popup.js`
   - 入口：`autoSummarizeActiveTab()`（檔案尾端直接呼叫）
   - 主要流程：
     1) `refreshSystemPromptFromNative()`
        - native message：`getSystemPrompt` → `SafariWebExtensionHandler.loadSystemPrompt()`
     2) `prepareSummaryContextWithRetry()` → `prepareSummaryContext()`
        - `getArticleTextFromContentScript()`
        - `browser.tabs.sendMessage(..., { command: "getArticleText" })`
        - `content.js` 解析正文（見 A2）
        - `estimateTokensWithTokenizer(text)`（見 A3）
     3) 依 token 分流
        - `tokenEstimate > LONG_DOCUMENT_TOKEN_THRESHOLD` → `runLongDocumentPipeline()`（見 A4）
        - 否則進入短文摘要（見 A5）
     4) `saveRawHistoryItem()` → `saveRawItem`（見 A6）

### A2. Content Script 取正文鏈路
`Shared (Extension)/Resources/content.js`
1. `browser.runtime.onMessage.addListener()`
2. `command === "getArticleText"`
3. `new Readability(document.cloneNode(true)).parse()`
4. 回傳 `{ command: "articleTextResponse", title, body }`

### A3. Token 估算 / 切段（Tokenizer in Popup）
`Shared (Extension)/Resources/webllm/popup.js`
- `estimateTokensWithTokenizer(text)`
  - 使用 `gpt-tokenizer`（由設定決定，預設 `cl100k_base`）估算 token
  - tokenizer 初始化失敗時 fallback 回 heuristic
  - encoding 由 native messaging 讀取（`getTokenEstimatorEncoding`）

長文切段：
`popup.js` → `chunkByTokens(text, chunkTokenSize)`
- 以選定 tokenizer 切段（預設 `cl100k_base`）
- `chunkTokenSize = 設定值`（2200/2600/3000/3200，預設 2600；最多段數由設定決定，超過則丟棄）
- tokenizer 未就緒時改用 `chunkByEstimatedTokens()`（heuristic）
- 不再走 native messaging 的 `token.estimate` / `token.chunk`

### A4. 長文 Pipeline（Popup）
`Shared (Extension)/Resources/webllm/popup.js` → `runLongDocumentPipeline(ctx)`
1. **Step 0 分流**：`tokenEstimate` 由 tokenizer 估算
2. **Step 1 切段**：`chunkByTokens()`（popup 內部 tokenizer）
3. **Step 2 閱讀錨點**（逐段）
   - `buildReadingAnchorSystemPrompt()`
   - `buildReadingAnchorUserPrompt()`
   - 生成：
     - Foundation Models：`generateTextWithFoundationModels()` → `fm.prewarm`/`fm.stream.start`/`fm.stream.poll`
     - 或 WebLLM：`generateTextWithWebLLM()` → `engine.chat.completions.create()`
   - 收集：`lastReadingAnchors[]`
4. **Step 3 展示用摘要**
   - `buildSummaryUserPromptFromAnchors(lastReadingAnchors)`
   - `getDefaultSystemPromptFallback()`（bundle `default_system_prompt.txt`）
   - 生成：Foundation Models / WebLLM
5. **保存**：`saveRawHistoryItem()` → native `saveRawItem`

### A5. 短文摘要鏈路（Popup）
`Shared (Extension)/Resources/webllm/popup.js`
- `streamSummaryWithFoundationModels(ctx)`
  - `fm.prewarm` → `fm.stream.start` → `fm.stream.poll` → `fm.stream.cancel`（中斷時）
- 或 `streamChatWithRecovery(buildSummaryMessages(ctx))`
  - `ensureWebLLMEngineLoaded()` → `loadEngine()`
  - `streamChat()` → `engine.chat.completions.create()`
- 完成後：`saveRawHistoryItem()`

### A6. Raw Library 儲存（Extension）
`popup.js` → `saveRawHistoryItem()`
- `browser.runtime.sendNativeMessage({ command: "saveRawItem", payload })`
- payload 內含：`url/title/articleText/summaryText/systemPrompt/userPrompt/modelId`
  - 長文追加：`readingAnchors/tokenEstimate/tokenEstimator/chunkTokenSize/routingThreshold/isLongDocument`

`Shared (Extension)/SafariWebExtensionHandler.swift`
- `case "saveRawItem":`
  - `saveRawHistoryItem(...)` 寫入 App Group `RawLibrary/Items/`
  - 設定檔案名稱 `sha256(url)__timestamp.json`

### A7. 其他（Popup 內部功能）
- 手動 prompt：`runButton` → `streamChatWithRecovery([{ role:"user" }])`
- 複製系統/用戶提示詞：`copySystemButton`/`copyUserButton` → `refreshSystemPromptFromNative()` + `prepareSummaryContextWithRetry()`

---

## B. App：Key-point from Clipboard / Share 函數鏈路

### B1. 入口 UI 鏈路（Clipboard）
1. `iOS (App)/Features/Library/LibraryRootView.swift`
   - `ToolbarItem`「＋」 → `activeKeyPointInput = .clipboard`
   - `.sheet(item:)` → `ClipboardKeyPointSheet`
2. `iOS (App)/Features/Clipboard/ClipboardKeyPointSheet.swift`
   - `.task { model.run() }` 自動啟動
3. `iOS (App)/Features/Clipboard/ClipboardKeyPointViewModel.swift`
   - `run()` 主流程

### B2. 入口 UI 鏈路（Share Extension）
1. `iOS (Share Extension)/ShareViewController.swift`
   - `viewDidAppear` → `handleShare()`
   - 讀取 `NSExtensionItem` 的 URL / plainText / title
   - `SharePayload(id,url,text,title)` → `SharePayloadStore.save()` 寫入 App Group `SharePayloads/`
   - `openHostApp(with: id)` → `eisonai://share?id=<payloadId>`
2. `iOS (App)/Features/Library/LibraryRootView.swift`
   - `onOpenURL` → `handleShareURL(_:)`
   - `SharePayloadStore.loadAndDelete(id)` 取出 payload
   - `activeKeyPointInput = .share(payload)` → `ClipboardKeyPointSheet`
3. （可選輪詢）`LibraryRootView.refreshPolling()`
   - 若 `sharePollingEnabled`，使用 `SharePayloadStore.loadNextPending()`
   - 取到 payload 後同樣走 `ClipboardKeyPointSheet`

### B3. 輸入準備鏈路
`ClipboardKeyPointViewModel.run()`
- `prepareInput(from:)`
  - 若為 URL：`ReadabilityWebExtractor.extract(from:)`
    - `WKWebView` 加載 → `contentReadability.js` → `Readability(document).parse()`
  - 若為純文字：直接使用
- Share 入口：`prepareInput(fromSharePayload:)`

### B4. Token 估算與分流（App）
`ClipboardKeyPointViewModel.run()`
- `tokenEstimator.estimateTokenCount(for:)` → `SwiftikToken`（由設定決定，預設 `cl100k_base`）
- `SwiftikToken` 由 App main bundle 載入選定 `.tiktoken` 檔
- `tokenEstimate > longDocumentRoutingThreshold (3200)` → 長文 Pipeline
- 否則 → 單次摘要

### B5. 長文 Pipeline（App）
`ClipboardKeyPointViewModel.runLongDocumentPipeline()`
1. **Step 1 切段**：`tokenEstimator.chunk(text:chunkTokenSize:)`（`chunkTokenSize = 設定值`，預設 2600；最多段數由設定決定，超過則丟棄）
2. **Step 2 閱讀錨點**（逐段）
   - `buildReadingAnchorSystemPrompt()`
   - `buildReadingAnchorUserPrompt()`
   - 生成：
     - `FoundationModelsClient.streamChat()`（可用時）
     - 或 `MLCClient.streamChat()`
3. **Step 3 展示用摘要**
   - `buildSummaryUserPrompt(from: readingAnchors)`
   - `AppConfig.defaultSystemPrompt`
   - 生成：Foundation Models / MLC
4. **保存**：`RawLibraryStore.saveRawItem(...)`

### B6. 單次摘要（App）
`ClipboardKeyPointViewModel.runSingleSummary()`
- `loadKeyPointSystemPrompt()` → bundle `default_system_prompt.txt`
- `buildUserPrompt(title:text)`
- Foundation Models：`FoundationModelsClient.prewarm()` + `streamChat()`
- 或 MLC：`MLCClient.loadIfNeeded()` + `streamChat()`
- 保存：`RawLibraryStore.saveRawItem(...)`

### B7. Raw Library 儲存（App）
`iOS (App)/Shared/Stores/RawLibraryStore.swift`
- `saveRawItem(...)`
  - URL 來源：`sha256(url)__timestamp.json`
  - 純文字：`clipboard__timestamp.json`
  - 寫入 `RawLibrary/Items/`

### B8. UI 顯示閱讀錨點
`iOS (App)/Features/Library/LibraryItemDetailView.swift`
- `outputs(item:)` 讀取 `readingAnchors` 顯示 `Chunk N (tokenCount)`
- `summaryText` 仍顯示為摘要（Markdown）

---

## C. Raw Library Schema（長文欄位對應）

`iOS (App)/Features/History/HistoryModels.swift`
- `RawHistoryItem.readingAnchors`：閱讀錨點陣列
- `tokenEstimate/tokenEstimator/chunkTokenSize/routingThreshold/isLongDocument`

`Shared (Extension)/SafariWebExtensionHandler.swift`
- `RawHistoryItem` 結構體包含對應欄位

---

## D. 長文閱讀 Pipeline Spec（整理 + 對應實作）

### D1. 目的（Spec 核心）
- 手機端、小模型（qwen3-0.6B）
- 超長文本可預期、低幻覺
- 分離「閱讀錨點」與「展示摘要」責任

### D2. 規格步驟（Spec → 實作）
**Step 0 Token 估算與分流**
- Spec：`tokenEstimator` encoding 估算（預設 `cl100k_base`），門檻 3200
- Extension：`estimateTokensWithTokenizer()`（popup 內 `gpt-tokenizer`）
- App：`tokenEstimator.estimateTokenCount()`（`SwiftikToken`）

**Step 1 Chunk 切割**
- Spec：固定切段（`chunkTokenSize = 設定值`，預設 2600；最多段數由設定決定，超過則丟棄）
- Extension：`chunkByTokens()`（popup 內 tokenizer）
- Extension tokenizer 不可用時改用 `chunkByEstimatedTokens()`
- App：`tokenEstimator.chunk(text:chunkTokenSize:)`

**Step 2 Chunk 級閱讀錨點**
- Spec：`buildReadingAnchorSystemPrompt` + `buildReadingAnchorUserPrompt`
- Extension：`runLongDocumentPipeline()` → `generateTextWithFoundationModels()` / `generateTextWithWebLLM()`
- App：`runLongDocumentPipeline()` → `FoundationModelsClient` / `MLCClient`

**Step 3 展示用摘要**
- Spec：使用 `AppConfig.defaultSystemPrompt`
- Extension：`getDefaultSystemPromptFallback()`（bundle `default_system_prompt.txt`）
- App：`summarySystemPrompt = AppConfig.defaultSystemPrompt`

### D3. Spec 建議欄位（已實作）
- `readingAnchors[]` + `tokenEstimate` + `tokenEstimator` + `chunkTokenSize` + `routingThreshold` + `isLongDocument`
- Extension `saveRawItem` payload 與 App `saveRawItem` 皆已帶入

---

## E. 參考檔案（關鍵節點）
- `Docs/key-point.md`
- `Spec/LONG_DOCUMENT_READING_PIPELINE.md`
- `Shared (Extension)/Resources/webllm/popup.js`
- `Shared (Extension)/Resources/content.js`
- `Shared (Extension)/SafariWebExtensionHandler.swift`
- `iOS (App)/Features/Clipboard/ClipboardKeyPointViewModel.swift`
- `iOS (App)/Shared/Web/ReadabilityWebExtractor.swift`
- `iOS (App)/Shared/TokenEstimation/GPTTokenEstimator.swift`
- `iOS (App)/Shared/Stores/RawLibraryStore.swift`
- `iOS (App)/Features/History/HistoryModels.swift`
- `iOS (App)/Features/Library/LibraryItemDetailView.swift`
