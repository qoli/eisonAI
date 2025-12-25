# [SPEC] 更換 tokenizer 計算器

## 1. 背景 / 問題

目前 Key-point 長文 Pipeline 與一般摘要流程的 token 估算與切段，主要依賴 **GPTEncoder（GPT-2 BPE）**。在中文/混合語系內容上誤差過大（最高可達 2.7 倍），導致：
- 長文分流判斷不準（本該走長文卻走短文，或反之）
- chunk 切割邊界不可靠，影響閱讀錨點與摘要品質
- extension 與 app 的 token 資訊難以對齊

## 2. 目標

- **改用與 OpenAI/TikToken 一致的計數基準**：`p50k_base`
- **Safari Extension 與 App 原生端一致對齊**（同一套 encoding）
- **長文分流與切段更可預期**
- 不改變既有 pipeline 行為（只換計數器）

## 3. 非目標

- 不調整 Pipeline 本身步驟（僅換 token estimator）
- 不變更模型或摘要 Prompt
- 不做歷史資料回填

## 4. 方案概述

### 4.1 Tokenizer 選型

- **Safari Extension**：`gpt-tokenizer`（JS）
  - repo：https://github.com/niieani/gpt-tokenizer
  - encoding：`p50k_base`
- **App 原生端**：`SwiftikToken`（Swift，無 FFI）
  - 路徑：`SwiftikToken/`
  - encoding：`p50k_base`

> 備註：兩端都統一使用 `p50k_base`，確保 token 數與 chunk 邊界一致。

### 4.2 Token 門檻調整

- 長文分流門檻（routingThreshold）：`3200`
- chunk 切段大小（chunkTokenSize）：`2600`

> 說明：原 2600/2000 為 GPT-2 BPE 誤差保守值，新計數器改為 `p50k_base` 後上調。

### 4.3 影響範圍（對應 Key-point chain）

- **Safari Extension（popup）**
  - `estimateTokensFromText()`：由 heuristic 改為 tokenizer
  - 移除 native messaging 的 `token.estimate` / `token.chunk` 路徑
  - 以 JS tokenizer 直接計算 token 與切段（保留 heuristic fallback）
  - `saveRawHistoryItem()` 的 `tokenEstimator` 欄位需更新
- **iOS App（Clipboard/Share）**
- `GPTTokenEstimator` 改為 `SwiftikToken`
  - `ClipboardTokenChunkingView` 文案更新（GPTEncoder → SwiftikToken）
  - `RawHistoryItem.tokenEstimator` 更新

> 關聯文件：
> - `Docs/key-point-function-chains.md`
> - `Spec/LONG_DOCUMENT_READING_PIPELINE.md`

## 5. Safari Extension 詳細規格

### 5.1 集成方式

- 下載 `https://unpkg.com/gpt-tokenizer/dist/p50k_base.js`
- 放置到 `Shared (Extension)/Resources/webllm/p50k_base.js`
- 以本地檔案載入（避免 runtime CDN）

### 5.2 設計與 API

**新增 tokenizer 模組（popup.js 或獨立檔）**
- 初始化一次並快取
- 提供：
  - `estimateTokens(text) -> Int`
  - `chunkByTokens(text, chunkTokenSize) -> [{ index, tokenCount, text, startUTF16, endUTF16 }]`

**估算與切段行為**
- 取代舊的 heuristic `estimateTokensFromText()`
- 長文分流與 Step 1 切段改走 tokenizer
- 分流門檻：`3200` tokens；切段大小：`2600` tokens
- 不再走 native messaging 的 `token.estimate` / `token.chunk`
- 若 tokenizer init 失敗，fallback 回原 heuristic（避免功能中斷）

### 5.3 Raw Library 欄位

- `tokenEstimator`：改為 `"p50k_base"`
- 其餘欄位維持：`tokenEstimate` / `chunkTokenSize` / `routingThreshold` / `isLongDocument`
  - `routingThreshold = 3200`、`chunkTokenSize = 2600`

## 6. App 端詳細規格

### 6.1 取代 GPTEncoder

- `GPTTokenEstimator` 改用 `SwiftikToken`
- encoding 固定 `p50k_base`
- 僅使用 `encode` 作為 token 計算來源（不要求 decode 回原文）
- 分流門檻：`3200` tokens；切段大小：`2600` tokens
- 對外 API 介面不變：
  - `estimateTokenCount(for:)`
  - `chunk(text:chunkTokenSize:)`

**計算方式（示意）**
```swift
// Encode text
let text = "Hello, world!"
let tokenizer = Tiktoken(encoding: .p50k)
let tokens = try await tokenizer.encode(text: text, allowedSpecial: [])
print("Tokens: \(tokens)")
```

### 6.2 UI / 文案更新

- `ClipboardTokenChunkingView` 說明文案同步更新
  - 「GPTEncoder (GPT-2 BPE)」→「SwiftikToken (p50k_base)」

### 6.3 Raw Library 欄位

- `tokenEstimator`：改為 `"p50k_base"`
- 舊資料保持 `"gpt2-bpe"` 不回填

## 7. 相容性與遷移

- **不做歷史資料回填**
- 新資料以 `tokenEstimator = "p50k_base"` 儲存
- UI 顯示需容忍舊值（`gpt2-bpe`）

## 8. 驗收標準

- 同一段文字在 **Extension 與 App** 端 token 數一致
- 長文分流與 chunk 切段結果一致（同一輸入、同一 chunk size）
- 原有流程不受影響（可順利生成摘要與閱讀錨點）
- 無 tokenizer 時仍可 fallback 並完成流程

## 9. 測試建議

- **文本測試集**（中英混合 / 只有中文 / 只有英文 / emoji）
- 比對 Extension 與 App token 數是否一致
- 驗證 3200/2600 門檻是否合理（必要時調整）
- 檢查 Raw Library 寫入欄位是否正確

## 10. 風險與對策

- **風險：JS tokenizer 初始化失敗**
  - 對策：保留 heuristic fallback
- **風險：新 token 計數導致分流行為改變**
  - 對策：先以 3200/2600 作為預設，再視實測調整
