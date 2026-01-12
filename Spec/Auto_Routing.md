# Auto Strategy Routing (智能策略分流) — v3

> 本文檔定義 Auto / Local / BYOK 的責任邊界，以及 Long Document Reading Pipeline 的唯一適用範圍。
> 目標：**結構單一、語義不混淆、實作可預期**。

---

## 一、設計目標

將三個概念徹底解耦並簡化：

1) **Long Document Reading Pipeline**：只作為「Local（本地受限模型）」的能力補丁  
2) **BYOK**：永遠不參與長文 pipeline，只嘗試 single-shot / streaming  
3) **Auto**：只根據 **Token 門檻** 在 **Local vs BYOK** 之間分流

---

## 二、名詞與分類

- **GenerationBackend**：使用者選擇的模式（`auto | local | byok`）
- **ExecutionBackendType**：實際執行類型（`local | byok`）

### Local（本地受限模型）

- **Apple Intelligence**
  - 本地模型
  - context window 約 4k
  - 可能需要 Long Document Reading Pipeline
- **Qwen3 0.6B（WebLLM / MLC）**
  - 本地模型
  - context 小、能力有限
  - 可能需要 Long Document Reading Pipeline

### BYOK（外部強模型）

- 任意外部雲端模型（OpenAI / Claude / Gemini / etc）
- 特性：
  - 大 context
  - 嘗試直接 single-shot / streaming
  - **永遠不進入 Long Document Reading Pipeline**

### Long Document Reading Pipeline

- 僅用於 **Local 類型** 的分段閱讀與摘要（chunk / map-reduce）

---

## 三、核心規則（Invariants）

1. **Long Document Pipeline 只允許在 `ExecutionBackendType = local` 時使用。**
2. **BYOK 永遠不參與 Long Document Pipeline。**
3. **Apple Intelligence 屬於 Local 類型，與 Qwen3 0.6B 同級，並受 Long Document Pipeline 規則約束。**
4. **Auto 只是一個「token 門檻分流器」，不參與任何長文邏輯。**

---

## 四、系統分層

### 層 1：使用者選擇（GenerationBackend）

- `auto`：系統依 token 門檻自動在 Local / BYOK 間分流
- `local`：強制使用 Local（Apple / Qwen）
- `byok`：強制使用 BYOK

### 層 2：實際執行類型（ExecutionBackendType）

- `local`：Apple Intelligence 或 Qwen3 0.6B
- `byok`：任一 BYOK provider

---

## 五、Auto 的定義（v3）

> **Auto 的唯一職責：用 `tokenEstimate + strategyThreshold` 決定 `ExecutionBackendType = local | byok`。**

### 分流規則

```
if tokenEstimate <= strategyThreshold:
    ExecutionBackendType = local
else:
    ExecutionBackendType = byok
```

- `strategyThreshold` 是 **Auto 專用門檻**
- 目前 **固定為 2600**，不提供調整
- Auto：
  - ❌ 不關心 chunk
  - ❌ 不關心 longdocRoutingThreshold
  - ❌ 不關心 pipeline 細節
  - ✅ 只輸出 `local | byok`

---

## 六、Long Document Pipeline 的觸發規則

> **LongDoc 只看 ExecutionBackendType，與 Auto 無關。**

```
if ExecutionBackendType == local:
    if tokenEstimate > longdocRoutingThreshold:
        use Long Document Pipeline
    else:
        single-shot
else:
    // byok
    single-shot only (or error if provider rejects)
```

---

## 七、行為矩陣

| GenerationBackend | tokenEstimate | ExecutionBackendType | LongDoc |
|-------------------|---------------|----------------------|----------|
| auto              | 小            | local                | 可能（看 longdoc 門檻） |
| auto              | 大            | byok                 | ❌ |
| local             | 任意          | local                | 可能 |
| byok              | 任意          | byok                 | ❌ |

---

## 八、Extension 端設計

### Native Command：`getAutoStrategySettings`

```
{
  strategyThreshold: Int,
  localPreference: "appleIntelligence" | "qwen3",
  qwenEnabled: Bool,
  appleAvailability: {
    enabled: Bool,
    available: Bool,
    reason: String
  }
}
```

> 只包含 **Auto 分流所需資訊**，不包含任何 LongDoc 參數。

### Popup 行為

1. 讀取：
   - `getGenerationBackend`
   - `getBYOKSettings`
   - `getAutoStrategySettings`
2. 若 backend = auto：
   - 用 `tokenEstimate + strategyThreshold` 解析 `ExecutionBackendType`
3. 若 backend = local / byok：
   - 直接決定 `ExecutionBackendType`
4. LongDoc 的啟用與否：
   - **只看 `ExecutionBackendType == local` + longdocRoutingThreshold**

---

## 九、App 端行為摘要

- `GenerationBackend = auto`：
  - 只做 Local / BYOK 分流（依 token 門檻）
- `ExecutionBackendType = local`：
  - 可能啟用 Long Document Pipeline（依 longdocRoutingThreshold）
- `ExecutionBackendType = byok`：
  - 永遠 single-shot / streaming

---

## 十、設定分離

- **AutoStrategySettings**
  - `strategyThreshold`
  - `localPreference`
- **LongDocSettings**
  - `longdocRoutingThreshold`
  - `chunkTokenSize`
  - `maxChunks`
- **BYOKSettings**
  - provider / url / key / model / maxTokens / etc

> 三者 **互不引用、互不影響**。

---

## 十一、與舊版的關係

- 舊版（v2）曾嘗試讓 Auto 與 LongDoc 完全切割（Auto 永不進 LongDoc）。
- v3 最終定案為：
  - **LongDoc = Local 的能力補丁**
  - **BYOK = 強模型直出**
  - **Auto = 單純的 token 門檻分流器**
