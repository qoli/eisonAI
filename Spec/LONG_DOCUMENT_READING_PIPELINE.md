# eisonAI 長文閱讀 Pipeline 規格（Spec）

## 1. 目的

本 pipeline 旨在**手機端**、僅使用**小型本地語言模型（qwen3-0.6B）**的前提下，對超長文本提供**穩定、低幻覺、可預期**的閱讀輔助體驗。

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
- App 使用 `SwiftikToken`，Extension 使用 `gpt-tokenizer`

### 2.5 輸出資料結構（Raw Library Schema）
- 長文 Pipeline 需要保存逐段閱讀錨點與估算資訊
- 既有欄位不刪除，新增可選欄位以保持向後相容

**建議新增欄位**
```
readingAnchors: [
  {
    index: Int,        // chunk 序號（0-based）
    tokenCount: Int,   // 該 chunk 的 token 數（tokenEstimator encoding）
    text: String       // Step 2 輸出的閱讀錨點
  }
]
tokenEstimate: Int        // 原文總 token（tokenEstimator encoding）
tokenEstimator: String    // 例如 "cl100k_base"
chunkTokenSize: Int       // 固定（2200/2600/3000/3200，預設 2600；最多段數由設定決定，預設 5）
routingThreshold: Int     // 3200
isLongDocument: Bool      // 是否走長文 pipeline
```

## 3. Pipeline 總覽

```
原文
  ↓
Step 0  Token 估算與分流（tokenEstimator，預設 cl100k_base）
  ├─ ≤ 3200 tokens：走原本單次摘要流程
  └─ > 3200 tokens：進入長文 Pipeline
  ↓
Step 1  Token 切割
  ↓
Step 2  Chunk 級閱讀錨點抽取（array X）
  ↓
Step 3  展示用摘要生成
  ↓
輸出：array X + summary
```

## 4. Pipeline 詳細步驟

### Step 0：Token 估算與分流（Routing）

**目的**  
在進入長文 pipeline 前，先判斷是否需要分段處理。

**實作方式**
- 使用 **tokenEstimator encoding** 估算 Token（預設 `cl100k_base`）
  - App：`SwiftikToken`
  - Extension：`gpt-tokenizer`
- 分流門檻：**3200 tokens**
  - `≤ 3200`：沿用原本單次摘要流程
  - `> 3200`：進入長文 pipeline

**Safari Extension 實作要點**
- popup 內直接使用 JS tokenizer 估算
- 不再走 native messaging 的 `token.estimate`
- tokenizer 初始化失敗時，fallback 回 heuristic 估算

### Step 1：長文切割（Chunking）

**目的**  
將超長文本切割為可被模型安全處理的段落。

**實作方式**
- 使用 **tokenEstimator encoding** 計算 Token（預設 `cl100k_base`）
- 固定 chunk 大小：`chunkTokenSize` 由設定決定（2200/2600/3000/3200，預設 2600）
- 最多段數由設定決定（4/5/6/7，預設 5）；超過則丟棄

**設計理由**
- 限制閱讀錨點處理段數，避免超長內容拖垮處理時間
- 仍保留長文 pipeline 的穩定分段與可控流程

**輸出**
- `chunks[]`：原文段落陣列

### Step 2：Chunk 級閱讀錨點抽取（核心步驟）

**角色定位**
- 模型角色：文字整理員
- 任務性質：閱讀輔助（非摘要生成）

**Prompt（workingVersion）**

```text
你是一個文字整理員。

你目前的任務是，正在協助用戶完整閱讀超長內容。

- 當前這是原文中的一個段落（chunks 1 of 4）
- 擷取此文章的關鍵點
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
- `array X[]`：逐段關鍵點結果  
  （此為整個 pipeline 的主要價值輸出）

### Step 3：展示用摘要生成（非精度導向）

**目的**
- 提供「快速掃描」用的總覽內容
- 不承擔嚴格正確性或忠於原文的責任

**輸入**
- `array X[]`（Step 2 的中間產物）

**Prompt（newPrompt）**

使用 `AppConfig.defaultSystemPrompt`

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
- `array X`：逐段閱讀錨點  
  - 高可信度  
  - 用於實際理解與閱讀輔助
- `summary`：展示用摘要  
  - 低風險、低成本  
  - 用於快速掃描與 UI 呈現

**UI 呈現**
- Library detail：保留 summary 位置
- 長文 pipeline 的 `array X` 顯示於 Library detail（作為閱讀錨點）

## 6. 已知限制

- Step 3 的摘要不保證完全忠於原文
- 不嘗試在端側進行全文級深度推理
- 不解決跨段落高階語義整合問題（屬於大模型責任）

## 7. 設計結論

本 pipeline 並非追求「一次生成完美摘要」，而是透過**分段閱讀錨點 + 展示用摘要**的結構，在小模型與端側限制下提供**穩定、可預期、可長期使用**的閱讀系統。
