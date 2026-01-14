# Prompt Translation Spec

```
Summarize the content as a short brief with key points.

Output requirements:
- Clear structured headings + bullet points
- No tables (including Markdown tables)
- Do not use the `|` character
```

## 背景
小參數模型對「請使用某語言」的遵守度偏弱，但在雙語提示詞情境下（原文 + 目標語言）反而更穩定，因此本規格以雙語模式為預設。

## 目標
將系統提示詞切換為「雙語模式」：
- 使用者選定的目標語言必須生效。
- 透過 **Apple Translation API** 翻譯提示詞並快取，避免每次都重新翻譯。

## 範圍
- 主要涵蓋 **System Prompt**（summary 系統提示詞）。
- 若需要一致行為，建議同步擴展到：Chunk Prompt、Title Prompt、Reading Anchor 相關模板。

## Chunk Prompt / Reading Anchor 位置
### iOS
- Chunk Prompt 讀取：`iOS (App)/Shared/Stores/ChunkPromptStore.swift`（UserDefaults key：`eison.chunkPrompt`）
- Chunk Prompt 預設：`iOS (App)/Shared/Config/AppConfig.swift` → `AppConfig.defaultChunkPrompt`
- 長文 Anchor 系統提示組合：`iOS (App)/Features/Clipboard/ClipboardKeyPointViewModel.swift`
  - `buildReadingAnchorSystemPrompt()` 以 Chunk Prompt 為 base，再接 `reading_anchor_system_suffix`
  - `buildReadingAnchorUserPrompt()` 使用 `reading_anchor_user_prompt`
  - `buildSummaryUserPrompt()` 使用 `reading_anchor_summary_item`

### Safari Extension
- Chunk Prompt 預設檔：`Shared (Extension)/Resources/default_chunk_prompt.txt`
- Native 讀取邏輯：`Shared (Extension)/Resources/webllm/popup.js` → `refreshChunkPromptFromNative()`
- Reading Anchor 模板檔：
  - system suffix：`Shared (Extension)/Resources/reading_anchor_system_suffix.txt`
  - user prompt：`Shared (Extension)/Resources/reading_anchor_user_prompt.txt`
  - anchors 聚合：`Shared (Extension)/Resources/reading_anchor_summary_item.txt`

## 語言支持位置（App）
- 語言清單與推薦邏輯：`iOS (App)/Shared/Stores/ModelLanguageStore.swift`
  - `ModelLanguage.supported`：支援語言列表
  - `ModelLanguageStore.loadOrRecommended()`：依 locale 推薦並保存
  - 儲存 key：`AppConfig.modelLanguageKey`（`eison.modelLanguage`）
- 系統提示詞附加語言提示：`iOS (App)/Shared/Stores/SystemPromptStore.swift`
  - `summary_language_line` 模板：`Shared (Extension)/Resources/summary_language_line.txt`
- UI 設定入口：
  - `iOS (App)/Features/Settings/GeneralSettingsView.swift`（Language picker）
  - `iOS (App)/Features/Settings/PromptSettingsView.swift`（提示語言說明）
  - `iOS (App)/Features/Onboarding/OnboardingView.swift`（初始保存）

## 核心概念
- **Default Prompt**：由 App 提供的預設提示詞（上方 block）。
- **Translated Prompt**：Default Prompt 翻譯後的版本。
- **App Defaults Cache**：保存 Translated Prompt 的本地快取。
- **ModelLanguageStore**：保存使用者選擇的目標語言設定。
- **Translation API**：iOS 17.4 / macOS 14.4 之後的 on-device 翻譯框架。

## 資料儲存
- `AppDefaults.translatedPrompt`（String，預設空字串）
- `AppDefaults.translatedPrompt.languageTag`（String，記錄翻譯目標語言）
- `ModelLanguageStore.selectedLanguage`（語言代碼）

## 雙語格式（必須）
翻譯結果需保留 Default Prompt 格式，並與原文同時存在：

```
<Original Default Prompt>

<Translated Prompt in target language>
```

說明：
- 先原文後翻譯，固定順序。
- 翻譯必須保留原本的空行與條列格式。

## 工作流程
### 啟動或使用提示詞時
1. 讀取 `AppDefaults.translatedPrompt`。
2. 若為空字串，或 `translatedPrompt.languageTag` 與目標語言不同：
   - 使用 **TranslationSession** 翻譯 Default Prompt → 目標語言。
   - 寫入 `AppDefaults.translatedPrompt` 與對應語言標記。
3. `ModelLanguageStore.loadOrRecommended()` 必須回傳語言適配結果。

### 使用者切換語言時
在「語言變更流程」中處理（不可在 sync `save` 內直接做 async 翻譯）：
1. 先保存新語言到 `ModelLanguageStore`。
2. 由上層流程（UI/Service）觸發 **TranslationSession** 翻譯任務。
3. 覆蓋 `AppDefaults.translatedPrompt` 與語言標記。
4. 翻譯完全由 Translation API 控制，不使用 LLM。

## 翻譯規則
- 翻譯來源：**Default Prompt**，不要翻譯已翻譯內容。
- 翻譯輸出必須保留原本的格式（空行、條列符號）。
- 目標語言由 `ModelLanguageStore` 決定。
- 不能改寫語義，只做語言翻譯。

## Translation API 使用規則
- 使用 `TranslationSession.Configuration` 指定目標語言。
- 來源語言可省略，讓框架自動偵測（不引入 `NLLanguageRecognizer`）。
- 翻譯必須是 **程式化、可控、機械式翻譯**，不可透過 LLM。

## 錯誤與回退
- 翻譯失敗：保持 `AppDefaults.translatedPrompt` 為空，並回退使用 Default Prompt。
- 若翻譯成功但格式損壞：丟棄翻譯結果，回退 Default Prompt。
- 若 `translatedPrompt.languageTag` 與目標語言不一致：視為快取失效，重新翻譯。

## 檢查點
- 切換語言後，提示詞立即更新。
- App 重啟後仍可讀到已翻譯的提示詞。
- 生成結果同時包含原文與翻譯，且格式一致。
