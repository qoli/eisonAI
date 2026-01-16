# eisonAI 長文閱讀 Pipeline 規格（Spec）

## 1. 目的

本 pipeline 旨在**手機端**、使用**本地模型**的前提下，對超長文本提供**穩定、低幻覺、可預期**的閱讀輔助體驗。

目前實際涵蓋的本地模型：
- iOS App：MLC（Qwen3 0.6B）或 Apple Intelligence
- Safari Extension：WebLLM 或 Foundation Models（Apple Intelligence）

> BYOK（遠端模型）不進入長文 pipeline，只走 single-shot/streaming。

核心目標：
- 支援超出模型 context window 的長文處理
- 避免單次摘要造成語義坍縮與幻覺放大
- 將模型能力限制在「可控、可預測」範圍內
- 明確區分**閱讀理解價值**與**展示用摘要**

## 2. 設計原則

### 2.1 端側優先（On-Device First）
- 全流程在裝置端完成
- 不依賴雲端模型或更大參數模型
- 適用於資源受限環境（手機）

### 2.2 Less-is-More（小模型友善）
- Prompt 避免高階抽象語義
- 避免多重任務、隱含目標與過度約束
- 將「理解責任」留在系統層，而非模型層

### 2.3 職責分離（Separation of Concerns）
- **閱讀錨點（Reading Anchors）**與**摘要展示（Presentation Summary）**明確分離
- 精度優先的輸出與展示導向的輸出分層處理

### 2.4 Token 估算一致性（Token Estimation Consistency）
- 以 **tokenEstimator 指定的 encoding** 作為計數基準（預設 `cl100k_base`），確保 Extension 與 App token 對齊
- encoding 由 Shared defaults（`tokenEstimatorEncodingKey`）決定；App/Extension 都會讀取，若不存在或無效則回退 `cl100k_base`
- App 使用 `SwiftikToken`；Extension 使用內建 JS tokenizer（與 encoding 對應）
- 支援 encoding：`cl100k_base` / `o200k_base` / `p50k_base` / `r50k_base`
- Extension 若 tokenizer 不可用或 native messaging 失敗，回退為 heuristic 估算（CJK 以字元計、非 CJK 以 4 字元約 1 token）

### 2.5 輸出資料結構（Raw Library Schema）
- 長文 Pipeline 需要保存逐段閱讀錨點與估算資訊
- 既有欄位不刪除，新增可選欄位以保持向後相容

**建議新增欄位**
```
readingAnchors: [
  {
    index: Int,        // chunk 序號（0-based）
    tokenCount: Int,   // 該 chunk 的 token 數（tokenEstimator encoding）
    text: String,      // Step 2 輸出的閱讀錨點
    startUTF16: Int?,  // 原文 UTF-16 起點（可選）
    endUTF16: Int?     // 原文 UTF-16 終點（可選）
  }
]
tokenEstimate: Int        // 原文總 token（tokenEstimator encoding）
tokenEstimator: String    // 例如 "cl100k_base"
chunkTokenSize: Int       // 目前僅允許 1792（預設 1792；最多段數由設定決定，預設 5）
routingThreshold: Int     // 固定 2048（與 chunkTokenSize 分開）
isLongDocument: Bool      // 是否走長文 pipeline
```

## 3. Pipeline 總覽

```
原文
  ↓
Step 0  Token 估算與分流（tokenEstimator，預設 cl100k_base）
  ├─ executionType != local：走原本單次摘要流程
  └─ executionType == local 且 tokenEstimate > routingThreshold：進入長文 Pipeline
  ↓
Step 1  Token 切割
  ↓
Step 2  Chunk 級閱讀錨點抽取（readingAnchors）
  ↓
Step 3  展示用摘要生成
  ↓
輸出：readingAnchors + summary
```

## 4. Pipeline 詳細步驟

### Step 0：Token 估算與分流（Routing）

**目的**  
在進入長文 pipeline 前，先判斷是否需要分段處理。

**實作方式**
- 使用 **tokenEstimator encoding** 估算 Token（預設 `cl100k_base`）
  - App：`SwiftikToken`
  - Extension：JS tokenizer（依 encoding），失敗則 fallback heuristic
- `executionType` 由 backend 設定決定（auto/local/byok）
  - auto 模式下先以 **AutoStrategy 門檻（固定 1792）**決定 local/byok
  - 僅在 `executionType == local` 時進入長文 pipeline（BYOK 永遠不進入）
- 分流門檻：**routingThreshold**（固定 2048）
  - `≤ routingThreshold`：沿用原本單次摘要流程
  - `> routingThreshold`：進入長文 pipeline

**Safari Extension 實作要點**
- popup 內使用 JS tokenizer 估算，並從 native 讀取 encoding
- native messaging 不可用或 tokenizer 初始化失敗時，fallback 回 heuristic 估算
- native messaging 不可用時，長文參數使用 fallback：`routingThreshold = 2048`、`chunkTokenSize = 1792`、`maxChunks = 5`
  - 以上值與 App 的 `LongDocumentDefaults` 一致

### Step 1：長文切割（Chunking）

**目的**  
將超長文本切割為可被模型安全處理的段落。

**實作方式**
- 使用 **tokenEstimator encoding** 計算 Token（預設 `cl100k_base`）
- 固定 chunk 大小：`chunkTokenSize` 由設定決定（目前僅允許 1792，預設 1792）
- 最多段數由設定決定（4/5/6/7，預設 5）；超過則丟棄
- Apple Intelligence / Foundation Models 如遇 context window 超限，會嘗試降到下一個更小的 `chunkTokenSize`
  - 目前允許值只有 1792，因此實際上通常無可降級空間（等同直接失敗）

**平台差異（Chunking Implementation）**
- iOS App：以 `SwiftikToken` 實際 token 計數進行二分搜尋切段，保留原文 `startUTF16/endUTF16`
- Safari Extension：
  - tokenizer 可用時：先 encode 全文，再依 token 切片並 decode 成 chunk 文本
  - tokenizer 不可用時：改用 heuristic（CJK = 1 char / 非 CJK = 4 chars）逐字累積切段
  - `startUTF16/endUTF16` 以 chunk 文字長度推算（best-effort），不保證與原文完全對齊

**設計理由**
- 限制閱讀錨點處理段數，避免超長內容拖垮處理時間
- 仍保留長文 pipeline 的穩定分段與可控流程

**輸出**
- `chunks[]`：原文段落陣列

### Step 2：Chunk 級閱讀錨點抽取（核心步驟）

**角色定位**
- 模型角色：文字整理員
- 任務性質：閱讀輔助（非摘要生成）

**Prompt（實際組合方式）**

- System prompt = `ChunkPromptStore().loadWithLanguage()` + `reading_anchor_system_suffix` 模板  
- User prompt = `reading_anchor_user_prompt` 模板

**預設模板**

```text
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

**設計重點**
- 明確角色，限制模型行為空間
- 明確「這不是全文」，防止過早總結
- 任務描述保持輕量，避免高階語義判斷

**行為預期**
- 僅基於當前段落
- 整理、重排、提取原文中已有資訊
- 避免創作與外推

**輸出**
- `readingAnchors[]`：逐段關鍵點結果  
  （此為整個 pipeline 的主要價值輸出）
  - 每個 anchor 會保留 `startUTF16/endUTF16`（若可用）

### Step 3：展示用摘要生成（非精度導向）

**目的**
- 提供「快速掃描」用的總覽內容
- 不承擔嚴格正確性或忠於原文的責任

**輸入**
- `readingAnchors[]`（Step 2 的中間產物）

**Prompt**
- System prompt：
  - iOS App：`SystemPromptStore().load()`（預設 `default_system_prompt.txt`，可被自訂）
  - Safari Extension（長文）：固定使用 `default_system_prompt.txt`（不套用自訂 system prompt）
- User prompt：由 `reading_anchor_summary_item` 模板將 anchors 串接

**預設模板**

```text
default_system_prompt.txt
Transform the given content into a concise, structured brief with key points.

Output requirements:
- Clear structured headings + bullet points
- No tables (including Markdown tables)

reading_anchor_summary_item.txt
Chunk {{chunk_index}}
{{chunk_text}}
```

**設計說明**
- 不再使用角色定位
- 不再要求閱讀語境或忠於原文
- 明確將此步驟定位為 Presentation Layer

**設計取捨**
- 接受模型使用其最穩定的摘要模板
- 接受可能的語義簡化與概括
- 透過「職責降級」避免幻覺放大影響核心價值

**輸出**
- `summary`：簡短、可閱讀的摘要文本

## 5. 最終輸出

系統同時交付：
- `readingAnchors`：逐段閱讀錨點  
  - 高可信度  
  - 用於實際理解與閱讀輔助
- `summary`：展示用摘要  
  - 低風險、低成本  
  - 用於快速掃描與 UI 呈現

**UI 呈現**
- Library detail：保留 summary 位置
- 長文 pipeline 的 `readingAnchors` 顯示於 Library detail（作為閱讀錨點）

## 6. 已知限制

- Step 3 的摘要不保證完全忠於原文
- 不嘗試在端側進行全文級深度推理
- 不解決跨段落高階語義整合問題（屬於大模型責任）
### 6.1 目前實作上的額外限制
- Auto 模式下，`executionType` 會先由 **AutoStrategy 門檻（固定 1792）**決定 local/byok；若判定為 byok，長文 pipeline 不會啟動，即使 tokenEstimate > routingThreshold
- Safari Extension 的長文 summary 使用 **預設 system prompt**（`default_system_prompt.txt`），不會套用自訂 system prompt（與 iOS App 行為不同）
- Extension 在 tokenizer 失敗時採 heuristic 切段，且 `startUTF16/endUTF16` 為推算值，僅供定位參考

## 7. 設計結論

本 pipeline 並非追求「一次生成完美摘要」，而是透過**分段閱讀錨點 + 展示用摘要**的結構，在小模型與端側限制下提供**穩定、可預期、可長期使用**的閱讀系統。

## 8. 實作對齊（目前代碼對應值）

**長文設定（App + Extension）**
- `chunkTokenSize`：僅允許 `1792`（`LongDocumentDefaults.allowedChunkSizes`）
- `routingThreshold`：`2048`（`LongDocumentDefaults.routingThresholdValue`）
- `maxChunks`：`4/5/6/7`（預設 `5`）

**Auto Strategy（影響 executionType）**
- `strategyThreshold`：固定 `1792`（`AutoStrategySettingsStore.fixedThreshold`）
- Auto 模式下：`tokenEstimate > 1792` 會傾向走 BYOK（因此不進長文 pipeline）

**模型 context window（供參考）**
- iOS MLC build（`mlc-package-config.json`）：`context_window_size = 3072`、`prefill_chunk_size = 640`
- Safari Extension WebLLM（`popup.js`）：本地 model override `context_window_size = 4096`
- 模型原始 `mlc-chat-config.json` 內部宣告 `context_window_size = 40960`，但 WebLLM 會以 override 值為準
