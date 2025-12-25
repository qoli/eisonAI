# Safari Extension 即時可見性規格（Draft）

## 1. 背景

目前 Safari Extension popup 在執行 Key-point 流程時，使用者難以即時理解系統正在處理哪些內容、以及各步驟的輸入/輸出。此規格旨在定義 **popup 的即時可見性**：在流程進行中，清楚顯示正在處理的文本片段與模型輸出。

本文件對應既有函數鏈路（參考 `Docs/key-point-function-chains.md`）：
- **A2**：Content Script 取正文
- **A4**：長文 Pipeline（Step 2：逐段閱讀錨點；Step 3：展示用摘要）
- **A5**：短文摘要流程

## 2. 目標

- 在 popup 中逐步顯示流程輸入與輸出，提升使用者對「正在處理什麼」的即時感知。
- 支援短文與長文兩條流程，且視覺上能分辨 Step 2（逐段）與 Step 3（總結）。

## 3. 非目標

- 不更動 pipeline 的計算邏輯、token 分流與 prompt 設計。
- 不調整長文切段的 token 參數與模型設定。
- 不增加新的儲存或同步機制。

## 4. 顯示需求（按流程）

### 4.1 一般流程（短文）

**需要展示：**
1. **A2 正文**：顯示 Readability 正文（**截斷 600 字**，作為 input/output 可視內容）
2. **A5 正常流程**：顯示模型 streaming 回應（摘要輸出）

### 4.2 長文流程

**需要展示：**
1. **A2 正文**：顯示 Readability 正文（**截斷 600 字**，作為 input/output 可視內容）
2. **A4 Step 2（逐段）**
   - 2.1 **逐段正文**：顯示每個 chunk 的原文（逐段，**截斷 600 字**）
   - 2.2 **逐段 Streaming 回應**：顯示對應 chunk 的 streaming 產出（閱讀錨點）
3. **A4 Step 3 正常流程**：顯示總結摘要的 streaming 回應

## 5. 顯示順序與關聯

- 先顯示 A2 正文（截斷版），再依流程顯示後續步驟。
- 長文流程中，Step 2 需以 chunk 為單位呈現「正文 + streaming 回應」對應關係。
- Step 3 以序列呈現於 Step 2 之後，不需要額外分區或卡片樣式。
- 所有輸出內容均顯示在 output；每次開始新的輸出前需先清空 output（**Streaming 過程除外**）。

## 6. 確認結論

- 逐段正文（Step 2.1）需要截斷，長度為 600 字。
- Step 2 與 Step 3 不需要明確分區或卡片，僅依序呈現。
- Streaming 中斷/取消的狀態由 Status Text 顯示即可。
