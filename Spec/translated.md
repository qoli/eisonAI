# 語言導向提示詞（Language-Guided Prompt）規格

本文件描述「語言導向提示詞」的核心行為與流程。系統在任一時間點只存在「目前語言」的一份最終 Prompt；不做雙語顯示、不做雙語拼接。英文預設提示詞只作為翻譯時的來源資料（build-time input），不屬於 runtime 狀態。

## 核心行為
1. **翻譯觸發點**
   - 翻譯行為發生在 `ModelLanguageStore.save(...)`，也就是使用者變更語言時。

2. **提示詞讀取方法**
   - System Prompt：`SystemPromptStore().load()`
   - Chunk Prompt：`ChunkPromptStore().loadWithLanguage()`

3. **App 啟動檢查**
   - 啟動時檢查 `AppDefaults.translatedPrompt.summary` 與 `AppDefaults.translatedPrompt.chunk` 是否為空字串。
   - 只要有任一為空，立即啟動翻譯流程並寫入 `AppDefaults`。

## 設計原則

- 系統在 runtime 只使用「一份」目前語言下的最終 Prompt（單語）。
- 不保留、不拼接、不顯示原始英文 Prompt。
- 英文預設 Prompt 只作為翻譯時的 source（build-time input），翻譯完成後不再參與 runtime。
- 翻譯是建構/刷新步驟（build step），不是 runtime state。
- 語言變更或啟動檢查只會導致「重新產生並覆寫」最終 Prompt。

## AppDefaults 儲存格式

所有翻譯結果只以「目前語言的最終可用版本」形式儲存，不保留語言標記、不保留歷史版本、不做多語系並存。

所有儲存的內容皆為「單語最終結果」，不做「原文 + 譯文」的拼接。

使用以下鍵值（皆為 String）：

- `AppDefaults.translatedPrompt.summary`
  - 內容：目前語言下的 Summary/System Prompt（最終可直接使用的字串）
  - 規則：
    - 翻譯成功後直接覆寫
    - 語言切換時會被重新產生並覆寫
    - 若為空字串，代表尚未生成，需要觸發翻譯流程

- `AppDefaults.translatedPrompt.chunk`
  - 內容：目前語言下的 Chunk Prompt（最終可直接使用的字串）
  - 規則：
    - 翻譯成功後直接覆寫
    - 語言切換時會被重新產生並覆寫
    - 若為空字串，代表尚未生成，需要觸發翻譯流程

不儲存：
- 不儲存 `languageTag`
- 不儲存原文與譯文的配對
- 不儲存多語系版本
- 不儲存任何版本號或狀態欄位
- 不儲存任何「原文」或「雙語組合結果」

語意約定：

- App 內任何地方只要讀取這兩個欄位，就視為「目前語言下已決定好的最終 Prompt」
- runtime 不需要、也不應該再判斷語言或翻譯狀態
- 語言變更 = 清空並重新產生這兩個欄位

## 參考
- Apple Translation API：`/Volumes/Data/Github/Language-translation`
