# 重構計劃 Spec：本地 LLM（AnyLanguageModel + Qwen3-0.6B CoreML）

參考：https://huggingface.co/blog/anylanguagemodel

## 1. 背景與目標

### 1.1 現況（as-is）

- 內容擷取：`content.js` 使用 `Readability` 從頁面 DOM 提取正文。
- 協調：iOS Safari（MV3）下本期由 `popup.js` 直接管控「提取 → Native → 快取」；`background.js` 保留狀態查詢等輔助能力。
- LLM：目前由 `contentGPT.js` 走遠端 API，並以 fetch 串流輸出（此重構會移除遠端路徑）。
- UI：`popup.js` 顯示總結與串流更新，並將結果快取在 `browser.storage.local`。

### 1.2 重構目標（to-be）

1. 引入 `AnyLanguageModel`（native / Swift）作為本地推理框架。
2. 以 `Qwen3-0.6B`（CoreML，MLProgram）作為預設本地 LLM，用於「網頁總結」。
3. 在不改變既有 UI 互動（包含串流體驗）的前提下，把 LLM 呼叫從 JS 遠端 API 轉移到 native 本地推理。
4.（未來，M10）追加一套「Share Extension + App Intent」入口，讓 Safari 以外的分享/捷徑也能呼叫同一套本地總結能力。

### 1.4 平台範圍（本期）

- 本期（M2）以 **iOS 發佈** 為主；不再以 macOS App 為交付目標。
- Safari Web Extension 仍運行於 iOS Safari（由 iOS App 承載與提供 native messaging）。
- 本期最低版本提升到 **iOS 18**（CoreML MLProgram + stateful KV cache 需求）。

### 1.3 非目標（non-goals）

- 不在本次重構中完善「多輪對話」的長記憶與向量檢索（可留做後續）。
- 不在本次重構中追求支援多模型任意切換；先把單一預設模型跑通，保留擴充點即可。
- 不在本次重構中處理所有網站的反爬/動態渲染極端情形（仍以 Readability 成功率為主）。

## 2. 功能需求

### 2.1 Safari Extension 總結

- 觸發方式：沿用 popup「自動 / 手動」觸發（現有 `runSummary` 流程）。
- 輸入：`{ url, title, articleText }`
- 輸出（延用既有格式，Markdown 純文字）：
  - `總結：` 一行
  - `要點：` 多行（每行一個要點，包含 emoji）
- 串流：UI 能看到逐步生成（token / chunk）更新。
- 快取：沿用 `browser.storage.local` 以 URL 為鍵的快取策略（至少維持與現況等效）。
- 失敗處理：顯示可理解錯誤，且 state 可回復到 idle。

### 2.2（未來，M10）Share Extension + App Intent 總結

- Share Extension（分享選單）：
  - 可從 Safari/其他 App 分享 `URL` 或 `文字` 到 EisonAI。
  - 顯示「生成中」→「結果」畫面，可一鍵複製/分享結果。
- App Intent（Shortcuts / Siri）：
  - Intent 形式：`SummarizeTextIntent(text)`、`SummarizeURLIntent(url)`
  - 回傳結果文字（同樣格式），並支援捷徑後續串接。
  - prompt 選擇：
    - `SummarizeURLIntent(url)`：依 `url` 套用網站客製 prompt（見 7.4）
    - `SummarizeTextIntent(text)`：無 `url` 時使用 default prompt

## 3. 架構設計

### 3.1 元件分工（最小改動）

**Extension（JS）**

- `content.js`：只負責提取文章內容（不再做 LLM 呼叫）。
- `background.js`：統一協調工作流程與狀態；負責呼叫 native 取得摘要（取代對 content script 的 `processSummary` 呼叫）。
- `popup.js`：維持 UI 與串流顯示；不直接碰 LLM。
- `contentGPT.js`：本次重構後不再使用（移除遠端 fallback 以降低複雜度）。
- `contentReadability.js`、`contentMarked.js`：維持現狀。

**Native（Swift）**

- `SafariWebExtensionHandler.swift`：負責接收 `browser.runtime.sendNativeMessage` 訊息、轉交到本地 LLM Service，再把結果回傳 extension。（`connectNative` 可留作未來串流路徑）
- 新增 shared module（建議以 Swift Package / Shared sources 實作）：`LocalLLMService`
  - 模型下載/安裝/版本管理
  - 推理與串流 callback
  - 長文 chunking / map-reduce 摘要管線
  - 快取（App Group 容器，可選）

### 3.2 資料流程（Safari Extension）

1. `popup.js` → `content.js`：`getArticleText`
2. `content.js` → `popup.js`：`articleTextResponse { title, body }`
3. `popup.js` → Native：`summarize.start { url, title, text }`（若 payload 過大則改用 `summarize.begin/chunk/end`）
4. Native → `popup.js`：`summarize.done { result }`（本期先採一次性回傳，非串流）
5. `popup.js`：將結果寫入 `browser.storage.local`（URL 作為快取 key）

### 3.3（未來，M10）資料流程（Share Extension / Intent）

- Share Extension / App Intent 直接呼叫 `LocalLLMService`，不經過 Safari extension message broker。
- 模型與快取建議放 App Group，避免重複下載與多份佔用（見 7.2）。

## 4. Native ↔︎ Extension 通訊協定

### 4.1 通訊方式

本期實作（iOS Safari 優先、最穩定）：

- 使用 `browser.runtime.sendNativeMessage(message, callback)` 呼叫 containing app 的 native app extension。
- 若 payload 過大，改用 `summarize.begin/chunk/end` 分段傳輸（避免 message size 限制）。
- 先採「一次性回傳」（非串流）；串流可留待後續確認 `connectNative` 可用性後再加。

未來方案（若目標平台確認可用）：

- `browser.runtime.connectNative(hostName)`：建立長連線 port，native 推送 `stream/done/error`。
- 若 `connectNative` 不穩定，才考慮 `summarize.poll`。

### 4.2 Message Envelope（通用外層）

所有 native messaging 都採用以下 envelope（便於版本控管與除錯）：

```json
{
  "v": 1,
  "id": "uuid",
  "type": "request|event|response",
  "name": "summarize.start",
  "payload": {}
}
```

### 4.3 summarize.start（request）

```json
{
  "v": 1,
  "id": "uuid",
  "type": "request",
  "name": "summarize.start",
  "payload": {
    "url": "https://example.com/a",
    "title": "Page title",
    "text": "article text...",
    "options": {
      "language": "zh-Hant",
      "format": "eison.summary.v1",
      "stream": true,
      "temperature": 0.4,
      "maxOutputTokens": 512
    }
  }
}
```

回應（response）：

```json
{
  "v": 1,
  "id": "uuid",
  "type": "response",
  "name": "summarize.started",
  "payload": { "requestId": "uuid" }
}
```

### 4.4 summarize.stream（event）

```json
{
  "v": 1,
  "id": "uuid",
  "type": "event",
  "name": "summarize.stream",
  "payload": { "requestId": "uuid", "delta": "..." }
}
```

### 4.5 summarize.done（event）

```json
{
  "v": 1,
  "id": "uuid",
  "type": "event",
  "name": "summarize.done",
  "payload": {
    "requestId": "uuid",
    "result": {
      "titleText": "總結：...",
      "summaryText": "要點：...",
      "raw": "完整原始輸出（可選）"
    }
  }
}
```

### 4.6 summarize.cancel（request，可選）

```json
{
  "v": 1,
  "id": "uuid",
  "type": "request",
  "name": "summarize.cancel",
  "payload": { "requestId": "uuid" }
}
```

### 4.7 summarize.poll（request，僅相容方案使用）

> 僅在無法使用 `connectNative` 串流時啟用。

```json
{
  "v": 1,
  "id": "uuid",
  "type": "request",
  "name": "summarize.poll",
  "payload": { "requestId": "uuid" }
}
```

回應（response）：

```json
{
  "v": 1,
  "id": "uuid",
  "type": "response",
  "name": "summarize.polled",
  "payload": {
    "requestId": "uuid",
    "done": false,
    "delta": "可選：本次新增輸出",
    "error": null
  }
}
```

### 4.8 error（event/response）

```json
{
  "v": 1,
  "id": "uuid",
  "type": "event",
  "name": "error",
  "payload": {
    "requestId": "uuid",
    "code": "MODEL_NOT_READY|INVALID_INPUT|INFERENCE_FAILED|CANCELLED",
    "message": "human readable message"
  }
}
```

### 4.9 model.getStatus（request，可選但建議）

用途：

- popup/settings 顯示「模型是否已安裝」與版本資訊
- Share Extension / Intent 在執行前快速 fail-fast（避免進到推理才報 `MODEL_NOT_READY`）

```json
{
  "v": 1,
  "id": "uuid",
  "type": "request",
  "name": "model.getStatus",
  "payload": {}
}
```

回應（response）：

```json
{
  "v": 1,
  "id": "uuid",
  "type": "response",
  "name": "model.status",
  "payload": {
    "state": "notInstalled|downloading|verifying|ready|failed",
    "repoId": "hf-repo-id",
    "revision": "commit-hash",
    "progress": 0.0,
    "error": null
  }
}
```

## 5. 本地摘要管線（LocalLLMService）

### 5.1 Prompt/輸出格式

沿用現有產品的摘要格式要求（並以 Spec 固化），抽象成 `format = eison.summary.v1`：

- prompt 套用：native 端在推理前會依 `url` 選擇對應的 `PromptProfile`（見 7.4），再將內容代入模板生成最終 prompt。
- 輸出必須包含兩段：
  - `總結：`（單行）
  - `要點：`（多行，每行一個要點，含 emoji）
- 若輸入非中文：翻譯為繁體中文後再輸出。
- 除格式外不輸出多餘文字。

### 5.2 長文處理（chunking + reduce）

由於 0.6B 模型可用 context 較小，必須避免直接塞入整篇長文：

1. 將 `articleText` 依「段落/句子」切分成 chunk（以 tokens/字元估算，先用字元上限近似亦可）。
2. 對每個 chunk 產生「局部要點」：
   - 只產出要點列表（短、可合併）
3. 把所有局部要點彙整後，再做一次「最終總結」生成 `總結 + 要點`。

最小落地版本（MVP）可以先採用「字元長度」切分（例如每 chunk 6k–10k 字元），後續再換成 tokenizer-based。

### 5.3 串流策略

- native 在推理過程每產生一段 `delta` 即發 `summarize.stream`。
- Extension 端負責節流（例如 150–300ms）以避免 UI 過度更新。

## 6. Extension 端重構點

### 6.1 background.js

- iOS Safari（MV3）下 `background.service_worker` 的 native messaging 不穩定，本期採用 **`popup.js` 直接呼叫 native** 作為主路徑。
- `background.js` 保留既有：
  - state machine、timeout、tab navigation 監控
  - cache 存取（`ReceiptURL`/`ReceiptTitleText`/`ReceiptText`）
  - `getSummaryStatus`（供 popup polling）
- （未來）若改回 background orchestrator，再補上 `requestId`/cancel 與 stream 轉送。

### 6.2 content.js

- 維持 `getArticleText`，輸出 `articleTextResponse`。
- 移除/停用 `processSummary` 分支（總結一律由 `background.js` 呼叫 native 執行）。

### 6.3 popup.js

- 維持既有：
  - 接收 `summaryStream` / `summaryStatusUpdate`
  - 顯示與快取
- 本期新增/調整：
  - 直接呼叫 native `summarize.start`（或 fallback `summarize.begin/chunk/end`）以完成摘要
  - 額外呼叫 `model.getStatus` 顯示「模型是否已就緒」
- 可選新增：
  - 顯示「模型狀態」（下載中/可用/錯誤），以提升可用性（見 7.2）。

### 6.4 contentGPT.js

- 本次重構目標為「本地模型單一路徑」：移除遠端 API fallback，以降低維護與狀態分歧。
- 後續處置（擇一）：
  - A：從 `manifest.json` 的 `content_scripts` / popup 引用中移除，檔案保留但不載入（便於回溯）。
  - B：確認無引用後刪除檔案（最乾淨，但需同步清理文件與引用）。

### 6.5 settings.js / settings.html（移除）

- 本次重構採用「本地模型單一路徑 + 主 App 統一管理」：放棄 extension 內的 `settings.html` 面板，以降低複雜度與設定分歧。
- extension 端行為：
  - 不再維護遠端 API 設定（`APIURL`/`APIKEY`/`APIMODEL`）。
  - 不再維護 prompt 設定（由主 App 管理，見 7.4）。
  - 僅在 popup 顯示必要狀態：
    - 本地模型狀態：透過 `model.getStatus` 顯示 `notInstalled/downloading/ready/failed`。
    - 下載導引：顯示「請開啟主 App 下載模型」說明（下載不在 extension 內執行，見 7.2.5）。

## 7. Native 端重構點

### 7.1 SafariWebExtensionHandler.swift

目標行為：

- 解析 envelope（`v/id/type/name/payload`）
- 將 `summarize.start/cancel/(poll)` 轉交 `LocalLLMService`
- 回傳：
  - `summarize.started` response
  - （可選）streaming events（若採 connectNative）
  - done/error

### 7.2 模型管理（下載、存放、更新）

建議採用 App Group（例如 `group.com.qoli.eisonAI`，實際以專案為準）：

- 路徑：`AppGroup/Models/XDGCC/coreml-Qwen3-0.6B/<revision>/Qwen3-0.6B.mlmodelc/...`
- metadata：`model.json`（版本、hash、來源、大小、最後使用時間）
- 啟動策略：
  - 第一次使用：若模型不存在，回傳 `MODEL_NOT_READY` 並提示使用者到 App/設定頁觸發下載。
  - 下載完成後：再允許 summarize。

MVP（若先求可跑）可先把模型打包進 App（但需評估 App 體積與審核風險），後續再改為下載。

#### 7.2.1 模型下載工具：swift-huggingface

本專案預計使用 `https://github.com/huggingface/swift-huggingface.git` 作為 Hugging Face Hub 檔案下載工具，並在其上包一層 `ModelDownloader`，把「模型挑選、檔案清單、下載、校驗、落盤、進度回報」收斂成穩定 API，供 `LocalLLMService` / Share Extension / App Intent 共用。

> 注意：iOS/macOS 下載行為需要網路；extension 進程不一定適合做大型下載，建議「由主 App 負責下載」，extension 僅做 ready check 與推理。

M2 實作備註：

- `swift-huggingface` 在 iOS 專案中可能因平台 API 不相容而無法編譯/整合（例如 `homeDirectoryForCurrentUser`），因此 M2 先採用 `URLSession` 直接下載 `https://huggingface.co/<repoId>/resolve/<revision>/<file>` 來完成「下載 + 進度 + 落盤」的最小閉環；後續再替換為 `swift-huggingface` 的 `downloadFile` / `downloadSnapshot`。

#### 7.2.2 固定模型來源（M2 定案）

本期固定使用下列模型（repo + revision 固定，避免上游變更導致不可重現）：

- `repoId`: `XDGCC/coreml-Qwen3-0.6B`
- `revision`（固定 commit）: `fc6bdeb0b02573744ee2cba7e3f408f2851adf57`
- 平台需求：iOS 18.0+ / macOS 15.0+（CoreML MLProgram + stateful KV cache）
- license: 以該 repo README / metadata 為準（下載前需再次確認）

需要下載的檔案（全量，排除 `.gitattributes`/`README.md`）：

- `tokenizer.json`
- `tokenizer_config.json`
- `config.json`
- `Qwen3-0.6B.mlmodelc/metadata.json`
- `Qwen3-0.6B.mlmodelc/model.mil`
- `Qwen3-0.6B.mlmodelc/coremldata.bin`
- `Qwen3-0.6B.mlmodelc/analytics/coremldata.bin`
- `Qwen3-0.6B.mlmodelc/weights/weight.bin`

#### 7.2.2 Model Descriptor（可配置、可版本化）

以 `model.json`（或 embedded defaults + 可更新的 json）描述要下載的模型：

- `repoId`：Hugging Face repo
- `revision`：例如 `main` / 指定 commit hash（推薦固定 hash 以利可重現）
- `files`：需要的檔名清單（例如 tokenizer/config/weights 等）
- `sha256`（可選但建議）：每個檔案的 checksum
- `requiredFreeSpaceBytes`：下載前做磁碟空間檢查（避免半路失敗）

#### 7.2.3 下載流程（原子落盤 + 可續傳）

目標特性：

- 可續傳（resume）與斷線重試
- 下載到暫存目錄，全部完成且校驗通過後再 atomic move 到最終目錄
- 支援併發限制（同時 1 個模型下載；避免多處同時觸發）

建議落盤結構：

- `AppGroup/Models/<repoId>/<revision>/`
  - `manifest.json`（repoId/revision/files/sha256/size/installedAt）
  - `tmp/`（下載暫存與 partial）

#### 7.2.4 進度與狀態（UI/Extension 需要）

需要一個統一的狀態機（shared）：

- `notInstalled`：未下載
- `downloading(progress)`：下載中（0.0–1.0）
- `verifying`：校驗中
- `ready`：可用
- `failed(error)`：失敗（含可重試資訊）

主 App 應提供「下載/取消/重試」入口（例如在設定頁），並顯示模型大小、剩餘空間檢查、下載進度。

#### 7.2.5 Extension/Intent 的行為約束（重要）

- Safari Extension / Share Extension / App Intent **不主動下載大型模型**：若模型未就緒，一律回傳 `MODEL_NOT_READY`，並提示使用者開啟主 App 下載。
- 僅在 macOS（限制較少）且使用者允許時，可考慮讓 App Extension 觸發下載；但仍需有全域鎖避免重入。

### 7.3（未來，M10）共用本地能力（Share Extension / Intent）

新增 target（規劃）：

- iOS：Share Extension（UIExtension）
- iOS/macOS：App Intents（可共用一套 LocalLLMService）

關鍵點：

- Share Extension 與主 App/Extension 共用同一份模型檔（App Group）。
- Intent 執行需控制時間/資源，必要時提供「快速模式」（較短輸出 tokens）。

### 7.4 Prompt 管理（主 App / App Group）

目標：

- 支援「每個網站可客製」的摘要 prompt。
- extension / share extension / intents 不負責管理 prompt，僅提供 `url`（若有）給 native 端進行匹配與套用。

#### 7.4.1 儲存位置與資料結構

- 儲存於 App Group（與模型共用同一容器），例如：`AppGroup/Config/prompts.json`
- 核心概念：
  - `PromptProfile`：一組 `{ systemText, userTemplate }`
  - `Rule`：一條「用 regex 去匹配 URL」→ 選擇 `PromptProfile`
  - `defaultProfileId`：沒有命中任何 Rule 時使用

#### 7.4.2 規則匹配（永遠是 regex）

- 匹配目標：一律對 `url.absoluteString`（完整 URL）做 regex match。
- 決策順序：依 `priority` 由大到小比對，第一個命中即採用；若同 priority，依 `updatedAt` 新者優先（或以 id 排序，需固定為 deterministic）。

#### 7.4.3 單一輸入框（根域名簡寫 / 正則）

主 App 的 UI 僅提供 1 個 pattern 輸入框，提示「可輸入根域名或正則」：

- 若使用者輸入看起來是「裸域名」（例如 `example.com`），視為「根域名簡寫」：
  - 行為仍是 regex：系統自動把它轉成 regex 並編譯儲存
  - 規則：不處理子域名（`www.example.com` 不會命中）
  - 協定：同時匹配 `http`/`https`
  - 轉換結果（示意）：
    - `example.com` → `^https?://example\\.com(?::\\d+)?(?:/|$)`
- 否則視為「正則」：
  - 直接以使用者輸入作為 regex pattern（仍匹配完整 URL）
  - 若要匹配 `www.` 或其他子域名，需由使用者自行寫 regex

#### 7.4.4 校驗與安全護欄

- 存檔前必須先 compile regex；失敗就拒存並顯示錯誤。
- 限制：
  - pattern 最大長度（避免極端 regex）
  - rule 數量上限（避免匹配成本爆炸）
- 建議提供「測試 URL」功能：輸入一個 URL 即時顯示 match / no match，降低規則踩雷率。

## 8. 決策點與風險

### 8.1 移除遠端 LLM fallback 的影響

- 優點：移除兩套推理路徑（local/remote）的分歧，降低狀態、錯誤型態、設定與測試矩陣。
- 代價：模型未就緒/下載失敗時，無法自動改走遠端；必須靠明確的 `MODEL_NOT_READY` 提示與「到主 App 下載」流程來保障可用性。

### 8.2 Native messaging 串流可行性

- 若 `connectNative` 在目標 Safari/iOS/macOS 版本上不可用或不穩定，本期維持 `sendNativeMessage`（一次性回傳 + 分段上傳）路徑。
- poll 模式會讓串流更「塊狀」，但仍能維持進度感。

### 8.3 模型大小與首用體驗

- 0.6B 4bit 仍可能是數百 MB 等級：需設計下載引導、進度與失敗重試。
- iOS extension 記憶體限制：需在 native 端採「單例+懶載入」並避免在多處重複載入模型。

### 8.4 Hugging Face 來源與授權/合規

- 需確認最終使用的 `repoId`、`revision` 與授權條款（包含商用、再散佈、以及是否需要顯示 attribution）。
- 下載來源若受地區/網路限制，需提供替代方案（例如手動匯入模型檔到 App Group）。
- 建議以固定 `revision = commit hash`，避免上游變更造成不可重現或輸出漂移。

## 9. 里程碑（建議）

1. **M0：協定與最小回路**
   - `background.js` 能呼叫 native `summarize.start` 並拿到 `done`（先不串流也可）。
2. **M1：本地推理 + 串流**
   - 先完成 native messaging 的端到端管線與資料對齊：native 端暫時「回傳 Readability 正文」作為結果（用於驗證通訊、狀態機、UI 顯示與錯誤處理）。
   - 後續再把 native 回傳內容替換為真正的本地推理輸出（仍沿用同一套協定與 UI 流程）。
3. **M2：模型管理**
   - App Group 存放、下載/更新、錯誤提示與重試（使用 `swift-huggingface` 實作下載與 resume）。
4. **M10：Share Extension + App Intent（未來實現）**
   - 新入口共用同一套摘要能力，完成端到端體驗。
