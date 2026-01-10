# BYOK SPEC

## 目標與背景
- 增加 BYOK（Bring Your Own Key）功能，作為新的 generation backend。
- 偏好使用 https://github.com/mattt/AnyLanguageModel 完成 LLM BYOK 方案。
- AnyLanguageModel 支持多種 Provider，其中 BYOK 需要的 HTTP Provider 包含：
  - Ollama HTTP API
  - Anthropic Messages API
  - Google Gemini API
  - OpenAI Chat Completions API
  - OpenAI Responses API
- AnyLanguageModel 需要使用 Package Traits 引入；需要啟用的 trait 為 `mlx`（為未來更多模型做準備）。

## 本次重構範圍（Phase 1）
1. 引入 AnyLanguageModel（含 `mlx` trait）。
2. 執行一次 refactor，將現有 generation backend 進一步模組化。
3. 把 `mlc_llm` 的處理路徑併入本次重構範圍。
4. web-llm（Safari extension）不做大改；延用既有 `fm.*` 原生通信協議，
   僅在 native 端改為 AnyLanguageModel backend 分流，JS 端只需 console.log 顯示 HTTP 設定。
5. **不新增 demo 頁面**；直接完成原生 app 的 `ClipboardKeyPointSheet` 流程。
6. 若 refactor 影響 Safari Extension 的 Foundation Models 路徑（需要訪問 Apple Foundation Models），必須同步修正。

## UI / 設定需求（AI Models）
- 設定入口：`Settings -> AI Models`。
- 使用新的 UI 結構（Section / Header / Body / Footer）。
- Generation backend：
  - Section header: `Generation Backend`
  - Section body: Menu（選項：Qwen3 0.6B / Apple Intelligence（可用時）/ BYOK）
  - Section footer: 保留既有可用性提示（如不可用原因）
- 當選擇 BYOK 時，顯示 BYOK 配置區塊（API URL / API Key / Model / Provider）。
- BYOK 作為新的 generation backend，影響正式 pipeline（非 demo-only）。
- Apple Intelligence 也走 AnyLanguageModel provider（同一路徑）。
- BYOK 欄位為 **onChange 自動保存**（無單獨 Save 按鈕）。
- BYOK 區塊 footer 需顯示檢查結果：
  - 若資訊有效：顯示「自動保存完畢」
  - 若資訊無效：顯示錯誤位置與原因

## BYOK 設定與存放
- 使用 App Group 的 UserDefaults 保存設定。
- 欄位：
  - `API URL`（必須輸入 `/v1` 結尾）
  - `API Key`
  - `Model`
  - `Provider`（由用戶手動指定）
- 驗證：
  - API URL 在「保存時」才提示是否以 `/v1` 結尾。
  - API Key 允許空白（例如本地 Ollama）。
  - 若 URL 未以 `/v1` 結尾，在 Section Footer 顯示**紅色字**提示：`URL 缺乏 /v1 結尾`。
  - 驗證不通過時不會自動保存；僅在信息完整且通過檢查時才會寫入。

## Provider 策略
- Provider 由用戶手動選擇（BYOK 區塊僅顯示 HTTP providers）。
- Apple Foundation Models 走 `Generation Backend` 的 Apple Intelligence 選項（不放在 HTTP Provider 下）。
- AnyLanguageModel 需覆蓋以下 provider（MLX 先隱藏，保留註釋）：
  - Apple Foundation Models
  - MLX models
  - Ollama HTTP API
  - Anthropic Messages API
  - Google Gemini API
  - OpenAI Chat Completions API
  - OpenAI Responses API
- UI Provider 選項順序（HTTP Provider Section）：
  - Ollama
  - Anthropic
  - Gemini
  - OpenAI (Chat)
  - OpenAI (Responses)
  - (MLX 先隱藏，寫在註釋)

## 長文 pipeline（BYOK）
- BYOK 使用 **獨立** 的 chunk size / routing threshold 參數。
- 預設值：
  - chunk size: 4096
  - routing threshold: 7168
- 以上兩個參數需要在 Settings 可調。
- maxTokens / think tags 維持與現有處理一致（共用原有策略）。

## Safari Extension 行為（更新）
- Extension 仍使用既有 `fm.checkAvailability / fm.prewarm / fm.stream.start / fm.stream.poll` 原生通訊。
- 原生端改為 AnyLanguageModel backend 分流：
- backend = `apple` → SystemLanguageModel（Apple Intelligence）
- backend = `byok` → HTTP provider（OpenAI/Ollama/Anthropic/Gemini）
- backend = `mlc` → 回報不可用（繼續走 WebLLM）
- Apple Intelligence 仍需 iOS 26+；BYOK 不受此限制（取決於 AnyLanguageModel 支援版本）。
- JS 端會讀取 `getGenerationBackend / getBYOKSettings / getByokLongDocumentSettings`：
  - backend = `byok` 時，長文 chunk size / routing threshold 使用 BYOK 設定。
  - `.ai-model` 顯示 BYOK model 名稱（否則維持 Apple Intelligence / WebLLM label）。
  - 仍保留 console.log 方便檢查 HTTP 設定資訊。

## BYOK 測試資訊（暫用）
- API: `http://ronnie-mac-studio.local:1234/v1`
- Model: `nvidia/nemotron-3-nano`

## 技術約束
- AnyLanguageModel 專案位置：`/Volumes/Data/Github/AnyLanguageModel/`。
- 原本的 `import FoundationModels` 需改為 `import AnyLanguageModel`，
  並使用 AnyLanguageModel 的 API 風格（與 Apple Foundation Models 相似）。
