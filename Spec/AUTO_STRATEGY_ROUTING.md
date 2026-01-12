# Auto Strategy Routing (智能策略分流)

## 目的
統一定義「Auto（智能策略）」在 App 與 Safari Extension 的分流行為、門檻設定、以及長文 pipeline 的 routing threshold 來源，避免前後端邏輯不一致。

## 名詞
- **Auto / 智能策略**：依「策略門檻」決定走本地模型或 BYOK。
- **策略門檻**（routing threshold）：token 數量的分流門檻。
- **本地模型偏好**：Apple Intelligence / Qwen3 0.6B 的優先順序。
- **BYOK**：使用外部 API 的模型（OpenAI / Anthropic / Gemini / Ollama / 等）。

## Auto 分流規則
1. **token <= 策略門檻** → 優先走本地模型  
2. **token > 策略門檻** → 走 BYOK

### 本地模型優先順序
依使用者選擇的「本地模型偏好」決定：
- 偏好 Apple Intelligence：Apple 可用 → Apple；不可用 → Qwen3（若啟用）→ BYOK
- 偏好 Qwen3 0.6B：Qwen3 啟用 → Qwen3；不可用 → Apple → BYOK

### 本地可用性
- **Apple Intelligence**：需裝置支援 + 已開啟 Apple Intelligence
- **Qwen3 0.6B**：需在「實驗室」啟用

### 策略門檻值
允許的門檻值（固定）：
- 2600（偏向 BYOK）
- 7168（偏向本地）

## 長文 Pipeline 的 routing threshold
長文 pipeline 使用的 **routing threshold** 必須依當前分流結果而定：
- 若本次請求實際走 **BYOK** → 使用 **BYOK routing threshold**
- 其他情況 → 使用 **預設 routing threshold**

這個行為需在 App 與 Safari Extension 中保持一致。

## Extension 端分流設計
### 新增 Native Command
`getAutoStrategySettings`

回傳內容：
```
{
  strategyThreshold: Int,        // 2600 or 7168
  localPreference: "appleIntelligence" | "qwen3",
  qwenEnabled: Bool,
  appleAvailability: {
    enabled: Bool,
    available: Bool,
    reason: String
  }
}
```

### Popup 端行為
1. 啟動時讀取：
   - `getGenerationBackend`
   - `getBYOKSettings`
   - `getByokLongDocumentSettings`
   - `getAutoStrategySettings`
2. Auto 模式下依 `tokenEstimate` 決定：
   - 是否使用 Foundation Models（Apple / BYOK）
   - 長文 routing threshold 是否取 BYOK 設定
3. AI Model label 依實際分流顯示（Apple / Qwen / BYOK）

## App 端行為摘要
- `GenerationBackend = auto` 時，會讀取策略門檻與本地偏好後決定實際 backend。
- 若 BYOK 未設定且分流結果為 BYOK，應顯示提示（不可用）。

## Onboarding 影響
Auto 策略、Qwen3 0.6B（實驗室）、Apple Intelligence（裝置支援）會影響可選 Backend。
Onboarding 需在後續同步調整。
