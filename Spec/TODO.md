# TODO / 里程碑進度

> 目標：讓 Codex 可「一次性」把開發推到可用里程碑；此檔作為進度與待決事項的單一來源。

## 狀態總覽

- ✅ M1：Readability 擷取 → Native 回傳原文（echo）→ Popup 顯示
- ✅ M2：模型下載（App）+ 模型狀態（Extension）+ 未就緒提示
- ⏭️ M3：真正使用本地模型產生摘要（Qwen3 CoreML 0.6B）（已實作 M3a 非串流，待 iOS Safari E2E 驗證）
- ⏸️ M10（未來）：Share Extension + App Intent

## M1（已完成）

- ✅ Extension：`content.js` 只做 Readability 擷取
- ✅ Extension：`popup.js` 直接呼叫 native `summarize.start`（避免 Safari MV3 `background.service_worker` 的 native messaging 不穩）
- ✅ Native：`SafariWebExtensionHandler.swift` 在 M1 以 echo mode 回傳正文
- ✅ UI：`popup.js` 顯示狀態與結果；移除 `contentGPT.js` fallback 與 settings 面板引用

## M2（已完成）

- ✅ App Group：`group.com.qoli.eisonAI`（App / iOS Extension entitlements 已更新）
- ✅ 模型固定 revision：`fc6bdeb0b02573744ee2cba7e3f408f2851adf57`（`XDGCC/coreml-Qwen3-0.6B`）
- ✅ 模型下載與落盤：`iOS (App)/ModelDownloadManager.swift`
  - ✅ 修正 CFNetworkDownload tmp 檔案搬移時機（必須在 `didFinishDownloadingTo` 內 move）
- ✅ App 最小 UI：只提供下載按鈕與進度/狀態（WebView UI）
- ✅ Extension gating：
  - ✅ `model.getStatus` 顯示 `notInstalled/downloading/verifying/ready/failed`
  - ✅ `MODEL_NOT_READY` 提示使用者打開 App 下載模型
- ✅ 修正 `popup.js` 語法錯誤（避免 popup 直接白屏 / 顯示 `{Status Text}`）
- ✅ App 端 LLM Ping 測試（WebView UI 內 `llm.ping` → 回傳結果顯示）
- ✅ Qwen3 關閉 think：下載完成後 patch `tokenizer_config.json:chat_template`，讓模板永遠插入空 `<think></think>`（等價於 vLLM `enable_thinking=false`）

## M3（下一步：本地推理產生摘要）

### 3.1 需要先決策（缺的資料/決策）

- [x] 推理 runtime：`AnyLanguageModel`
- [x] `AnyLanguageModel`：本地 package reference（`../AnyLanguageModel`）
- [x] 目標行為：先做「非串流一次性回傳」(M3a)
- [x] 生成參數預設值（暫定）：`temperature=0.4`、`maxOutputTokens=512`
- [ ] Prompt 預設內容：
  - [ ] `APPSystemText`
  - [ ] `APPPromptText`（user template；含 `{{title}}` / `{{text}}` 之類 placeholder）
  - [x]（暫時）native 內建 fallback prompt（後續再改由 App 管理並落 App Group）

### 3.2 主要工作項目

- [x] Native 端產生摘要（M3a）：
  - [x] `SafariWebExtensionHandler.swift`：改為 async，使用 `AnyLanguageModel.CoreMLLanguageModel`（iOS 18+）從 App Group 模型目錄做本地推理
  - [x] 產生符合 `eison.summary.v1` 格式輸出（`總結：` + `要點：`）
  - [x] 長文保護：先用字元截斷（16k chars）避免 prompt 過大
- [x] 使用 App Group 模型路徑載入 CoreML 模型（repoId + revision）
- [ ] 長文處理（chunk + reduce）：
  - [ ] 先以字元長度 chunk（MVP），後續可改 tokenizer-based
- [ ] Extension ↔︎ Native 串流：
  - [ ] 先確認 iOS Safari `connectNative` 是否可用；否則走 `summarize.poll`
  - [ ] `background.js` 支援 `stream/done/error` 並 forward 到 `popup.js`
- [ ] 快取策略：
  - [x] M3 恢復快取（`background.js` 會寫入 `Receipt*`；`popup.js` 會 cache）

## M10（未來實現）

- [ ] Share Extension（分享 URL/文字）→ 呼叫同一套 `LocalLLMService`
- [ ] App Intent（Shortcuts）`SummarizeTextIntent` / `SummarizeURLIntent`
- [ ] 每站客製 prompt（regex rule；根域名輸入是 regex 簡寫；不匹配子域名）

## 已知風險 / 觀察

- `swift-huggingface` 在 iOS 編譯會踩到 `homeDirectoryForCurrentUser`（因此 M2 已改用 `URLSession` 直接 resolve 下載）。
- AnyLanguageModel 的 CoreML 支援需要啟用 `CoreML` trait。
- 目前用 local shim package `EisonAIKit` 來啟用 traits，並集中管理 AnyLanguageModel 相關依賴（避免 Xcode 無法直接設定 traits）。
- 若 `AnyLanguageModel.CoreMLLanguageModel` 在編譯時不存在，需確認 AnyLanguageModel package 有把 traits 映射到 Swift compilation conditions（`-D CoreML/MLX/Llama`）；目前已在本機 `AnyLanguageModel/Package.swift` 補上 `swiftSettings: [.define(..., .when(traits: ...))]`。
- Safari MV3 `background.service_worker` 可能無法呼叫 `browser.runtime.sendNativeMessage`；目前改為由 `popup.js` 直接呼叫 native（避免 `Invalid call to runtime.sendNativeMe...`）。
- Safari Web Extension 的 `sendNativeMessage` 常見是 callback 版：`sendNativeMessage("application.id", message, callback)`；若用 promise/少參數可能報 `Invalid call to runtime.sendNativeMessage()`，且 Safari 會忽略 `application.id`（仍建議傳入任意字串）並只送到 containing app 的 native app extension。
- `sendNativeMessage` 可能不允許同時多筆未完成請求；popup 端已加 mutex 讓 native 呼叫序列化（先 `model.getStatus` 再 `summarize.start`），並為摘要放寬 timeout。
- iOS Safari 可能對 `sendNativeMessage` 的 payload 大小有限制；若 `summarize.start` 因 `Invalid call` 失敗，會自動 fallback 到分段傳輸（`summarize.begin/chunk/end`）。
- iOS Safari 可能會對 `sendNativeMessage` 的 `applicationId` 字串做額外校驗；目前優先使用 `application.id`（sample 寫法）再 fallback `com.qoli.eisonAI`，避免使用 extension bundle id。
- 模型輸出可能包含 `<think>`/`<analysis>` 等推理內容；native 端已做輸出清洗並強制格式化，避免 UI 顯示推理與標籤。
- 若 popup 停留在「載入中... / `{Status Text}`」通常代表 `popup.js` 解析失敗（SyntaxError）；優先看 Safari Develop Console 的錯誤行號。
- AnyLanguageModel README 提到 Xcode 26 + iOS 18/更早 可能會有 build bug（必要時改用 Xcode 16 toolchain）。
