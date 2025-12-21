# Key-point：兩個入口的行為說明

本文件整理「Key-point」的兩個入口與後續行為：

1) Safari Extension（popup）
2) App 的 Key-point from Clipboard

若需更細的 WebLLM/Readability/CSP 說明，另見：
- `Docs/popup.md`
- `Docs/content.js.md`
- `Docs/DEVELOPMENT.md`
- `Docs/database.md`

---

## 1) Safari Extension（popup）

### 入口
- `Shared (Extension)/Resources/manifest.json` 的 `action.default_popup` → `webllm/popup.html`
- UI / 行為主體：`Shared (Extension)/Resources/webllm/popup.js`

### 主要流程
1. 開啟 popup
2. 檢查 WebGPU（`navigator.gpu`）
3. 建立 worker + WebLLM engine
4. 讀取 system prompt（bundle `default_system_prompt.txt` 或內建預設）
5. 透過 content script 取得 active tab 正文
   - popup → `browser.tabs.sendMessage(..., { command: "getArticleText" })`
   - content script (`content.js`) 用 Readability 解析正文
6. 生成摘要（串流輸出）
   - 優先嘗試 Native Foundation Models（可用時）
   - 失敗時回退到 WebLLM
7. 生成完成後寫入 Raw Library（native messaging）

### 儲存
- popup 透過 `browser.runtime.sendNativeMessage({ command: "saveRawItem" })` 將結果寫入 Raw Library
- payload 內容：`url/title/articleText/summaryText/systemPrompt/userPrompt/modelId`
- 相關程式碼：`Shared (Extension)/Resources/webllm/popup.js`

---

## 2) App：Key-point from Clipboard

### 入口
- UI 入口：`iOS (App)/Features/Library/LibraryRootView.swift`
  - toolbar「+」→ `ClipboardKeyPointSheet`
- Sheet：`iOS (App)/Features/Clipboard/ClipboardKeyPointSheet.swift`
- ViewModel：`iOS (App)/Features/Clipboard/ClipboardKeyPointViewModel.swift`

### 主要流程
1. 開啟 Sheet 後自動 `run()`
2. 讀取剪貼簿
   - 若為 URL：使用 `ReadabilityWebExtractor` 擷取正文
   - 若為純文字：直接使用全文
3. 讀取 system prompt（bundle `default_system_prompt.txt`）
4. 產生 user prompt（標題 + 正文；正文最多 8000 字）
5. 生成摘要（串流輸出）
   - Foundation Models 可用時優先
   - 否則走 MLC 推理
6. 生成完成後寫入 Raw Library

### 儲存
- `RawLibraryStore.saveRawItem(...)`
- URL 會用 `sha256(url)__timestamp.json`；非 URL 用 `clipboard__timestamp.json`
- 相關程式碼：`iOS (App)/Shared/Stores/RawLibraryStore.swift`

---

## 共用資料：Raw Library

- 規格與路徑請見：`Docs/database.md`
- 兩個入口最終都寫入 `RawLibrary/Items/` 作為 source of truth
