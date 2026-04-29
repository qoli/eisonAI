# Safari Extension 原本長文流程

本文記錄破壞性重構前的 Safari Extension 長文系統行為。基準點為 `1c3a3413^`，也就是 `♻️ refactor(inference): migrate local runtime to AnyLanguageModel MLX` 之前的實作與文件。

原本長文系統不是「把全文截短後摘要」，而是本地模型專用的 map-reduce 式閱讀流程：先切段、逐段產生 reading anchors，最後只用 anchors 生成展示摘要。

## 1. Popup 啟動與頁面內容準備

Safari popup 啟動 `autoSummarizeActiveTab()`。

啟動後會先讀取 native 設定：

- system prompt
- chunk prompt
- tokenizer encoding
- generation backend
- BYOK 設定
- Auto strategy 設定
- long document settings

接著 popup 透過 content script 對目前頁面執行：

```js
new Readability(document.cloneNode(true)).parse()
```

content script 回傳 `title`、`body`、`url`。popup 再用 JS tokenizer 估算 token，預設 encoding 是 `cl100k_base`。如果 tokenizer 不可用，會 fallback 為 heuristic 估算：CJK 約 1 字 1 token，非 CJK 約 4 字 1 token。

## 2. Backend 分流

原本不是單純依 token 數決定是否進長文，而是先決定實際 execution backend。

- `byok`：永遠不進長文 pipeline，只做 single-shot streaming。
- `local`：可以進長文 pipeline。
- `auto`：先用 Auto strategy threshold 決定實際執行類型是 `local` 還是 `byok`。

破壞性重構前的主要預設值：

- `autoStrategyThreshold = 1792`
- `longDocumentRoutingThreshold = 2048`
- `chunkTokenSize = 1792`
- `maxChunks = 5`，允許值為 `4/5/6/7`

## 3. 長文 Pipeline 觸發條件

原本長文 pipeline 只在以下條件同時成立時啟動：

```js
executionType === "local" && tokenEstimate > routingThreshold
```

如果 execution backend 是 `byok`，即使 token 數超過 `routingThreshold`，也不會進入 chunk / reading anchors 流程。BYOK 的責任是強模型直出。

## 4. Step 1：Token 切段

長文流程會使用：

```js
chunkByTokens(text, chunkTokenSize)
```

切段方式是先 encode 全文，再依 `chunkTokenSize` 切 token slice，最後 decode 回 chunk text。

每個 chunk 會保存：

- `index`
- `tokenCount`
- `text`
- `startUTF16`
- `endUTF16`

Extension 端的 `startUTF16/endUTF16` 是依 chunk text 長度推算的 best-effort 值。最多只處理 `maxChunks` 段，超過的 token 會被截掉。若 tokenizer 不可用，則改用 heuristic 切段。

## 5. Step 2：逐段 Reading Anchors

每個 chunk 會單獨送進模型，生成該段的 reading anchor。這一步不是最終摘要，而是逐段閱讀錨點。

system prompt 由兩段組成：

- native 載入的 `ChunkPromptStore().loadWithLanguage()`，預設來自 `default_chunk_prompt.txt`
- `reading_anchor_system_suffix.txt`，用來標明目前是第幾段

user prompt 來自 `reading_anchor_user_prompt.txt`，基本形式是：

```text
CONTENT
{{content}}
```

每段輸出會清掉 thinking / `<think>` 類內容，再放入 `lastReadingAnchors[]`。

## 6. Step 3：用 Anchors 生成展示摘要

最終摘要不再拿全文送模型，而是只使用 Step 2 的 reading anchors。

popup 會用 `reading_anchor_summary_item.txt` 把 anchors 串成類似：

```text
Chunk 1
...

Chunk 2
...
```

Safari Extension 的長文 Step 3 固定使用 bundle 內的 `default_system_prompt.txt`，不套用使用者自訂 system prompt。這裡產生的 `summaryText` 是 UI 展示用摘要；真正高可信的閱讀資料是 `readingAnchors`。

## 7. 保存 Raw Library

長文完成後，popup 呼叫 native `saveRawItem` 保存到 Raw Library。

payload 會包含：

- `articleText`
- `summaryText`
- `systemPrompt`
- `userPrompt`
- `modelId`
- `readingAnchors`
- `tokenEstimate`
- `tokenEstimator`
- `chunkTokenSize`
- `routingThreshold`
- `isLongDocument`

native 端寫入 App Group 的 `RawLibrary/Items/`。Library detail 之後可以顯示展示摘要，也可以顯示逐段 reading anchors。

## 修復邊界

修復 2.8 之後的錯誤邏輯時，重點不是恢復 WebLLM。WebLLM 被移除是符合預期的，當前 Safari Extension backend 只需要保留 Apple Intelligence 與 BYOK。

需要恢復的是原本長文系統的語義：

- 先解析 execution backend，再判斷是否能進長文。
- BYOK 永遠不進長文 pipeline。
- 只有 Apple Intelligence 這類 local backend 才能使用長文 pipeline。
- 長文 pipeline 保持「切段 → reading anchors → anchors summary」的三段式流程。
- 長文 prompt 模板、anchor cleanup、Raw Library 長文欄位保存要與原始流程一致。
