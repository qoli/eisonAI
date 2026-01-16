# 長文閱讀 Pipeline（實作文件）

本文檔描述 eisonAI **目前已實現的長文閱讀 Pipeline**，內容來自代碼實作而非未來規格，作為維護與協作參考。

## 1. 範圍與目標

- 全流程在裝置端執行（MLC / Apple Intelligence / WebLLM / Foundation Models）。
- 提供超長文本的穩定閱讀輔助，降低幻覺風險。
- 嚴格區分「閱讀錨點」（高可信）與「展示摘要」（低風險 UI 用）。
- BYOK **不進入長文 pipeline**，僅走單次摘要 / streaming。

## 2. 高層流程

```
原文
  -> Step 0：Token 估算與分流
  -> Step 1：Chunk 切割
  -> Step 2：逐段閱讀錨點
  -> Step 3：基於錨點的展示摘要
輸出：readingAnchors + summary
```

## 3. Step 0：Token 估算與分流

### Token 估算
- 編碼由 `tokenEstimatorEncodingKey` 決定（Shared defaults）。
- 預設編碼：`cl100k_base`。
- iOS App：`SwiftikToken`（實際 tokenizer）。
- Safari Extension：JS tokenizer（對應 encoding）。失敗時 fallback 為 heuristic（CJK=1 字元、非 CJK=4 字元）。

### 分流規則
- `executionType` 由後端設定（auto/local/byok）決定。
- Auto 模式先以 **固定門檻 1792** 判斷 local / byok。
- 長文 pipeline 只在 `executionType == local` 時啟動。
- 長文 routingThreshold 固定為 **2048**。
  - `<= 2048`：走單次摘要。
  - `> 2048`：進長文 pipeline。

### Safari Extension fallback（native messaging 不可用）
- `routingThreshold = 2048`
- `chunkTokenSize = 1792`
- `maxChunks = 5`

## 4. Step 1：Chunk 切割

### 參數
- `chunkTokenSize`：允許值 `[1792]`（預設 1792）。
- `maxChunks`：允許值 `[4, 5, 6, 7]`（預設 5）。

### 平台差異
- **iOS App**
  - 以真實 tokenizer 計數，透過二分搜尋找 chunk 邊界。
  - `startUTF16/endUTF16` 由原文偏移保留。
- **Safari Extension**
  - tokenizer 可用：全文 encode，再依 token 切片，decode 成 chunk 文本。
  - tokenizer 不可用：heuristic 逐字累積切段。
  - `startUTF16/endUTF16` 以 chunk 文字長度推算（best-effort，可能不精準）。

### Context window fallback
- Apple Intelligence / Foundation Models 在超窗時會嘗試降 chunk size。
- 目前允許值只有 1792，**實際上通常沒有更小可降級**。

## 5. Step 2：閱讀錨點（Reading Anchors）

### Prompt 組合
- System prompt：`ChunkPromptStore().loadWithLanguage()` + `reading_anchor_system_suffix`
- User prompt：`reading_anchor_user_prompt`

### 預設模板
```
default_chunk_prompt.txt
You are a text organizer.

Your task is to help the user fully read very long content.

- Extract the key points from this article

reading_anchor_system_suffix.txt
- This is a paragraph from the source (chunk {{chunk_index}} of {{chunk_total}})

reading_anchor_user_prompt.txt
CONTENT
{{content}}
```

### 行為預期
- 僅整理當前 chunk。
- 提取原文內容，不做外推。

## 6. Step 3：展示摘要（Presentation Summary）

### 輸入
- `readingAnchors[]`

### Prompt
- User prompt：使用 `reading_anchor_summary_item` 組合每段錨點。
- System prompt：
  - iOS App：`SystemPromptStore().load()`（可自訂）
  - Safari Extension（長文）：固定使用 `default_system_prompt.txt`

### 預設模板
```
default_system_prompt.txt
Transform the given content into a concise, structured brief with key points.

Output requirements:
- Clear structured headings + bullet points
- No tables (including Markdown tables)

reading_anchor_summary_item.txt
Chunk {{chunk_index}}
{{chunk_text}}
```

## 7. Raw Library 輸出結構

```
readingAnchors: [
  {
    index: Int,
    tokenCount: Int,
    text: String,
    startUTF16: Int?,
    endUTF16: Int?
  }
]
tokenEstimate: Int
tokenEstimator: String
chunkTokenSize: Int
routingThreshold: Int
isLongDocument: Bool
```

## 8. 目前預設值與設定來源

### 長文預設（App + Extension）
- `chunkTokenSize`：1792（唯一允許值）
- `routingThreshold`：2048
- `maxChunks`：4/5/6/7（預設 5）

### Auto Strategy（影響 executionType）
- 固定門檻：1792（來源：`LongDocumentDefaults.autoStrategyThresholdValue`）
- Auto 模式下 `tokenEstimate > 1792` 傾向 BYOK，**會阻止長文 pipeline 啟動**。

### 模型 context window（參考）
- iOS MLC build：`context_window_size = 3072`、`prefill_chunk_size = 640`
  - 來源：`mlc-package-config.json`
- Safari Extension WebLLM：本地 override `context_window_size = 4096`
  - 來源：`popup.js -> getLocalAppConfig()`
- 模型原始 `mlc-chat-config.json` 宣告 `context_window_size = 40960`
  - WebLLM 以 override 值為準。

## 9. 已知行為與限制

- 長文 pipeline 只在 **local executionType** 下運行。
- Auto 模式可能在 `tokenEstimate > routingThreshold` 時仍被 BYOK 擋掉。
- Extension 長文 summary 不使用自訂 system prompt。
- heuristic chunking 的 `startUTF16/endUTF16` 僅供參考。

## 10. 代碼對應

- iOS 長文流程：`iOS (App)/Features/Clipboard/ClipboardKeyPointViewModel.swift`
- Token 估算：`iOS (App)/Shared/TokenEstimation/GPTTokenEstimator.swift`
- 長文預設：`iOS (App)/Shared/LongDocument/LongDocumentDefaults.swift`
- Auto strategy：`iOS (App)/Shared/Stores/AutoStrategySettingsStore.swift`（門檻值取自 `LongDocumentDefaults`）
- Extension 長文流程：`Shared (Extension)/Resources/webllm/popup.js`
- Extension native bridge：`Shared (Extension)/SafariWebExtensionHandler.swift`
- MLC config：`mlc-package-config.json`
