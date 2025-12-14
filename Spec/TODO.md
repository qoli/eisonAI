# TODO / 里程碑進度

> 目標：讓 Codex 可「一次性」把開發推到可用里程碑；此檔作為進度與待決事項的單一來源。

## 狀態總覽

- ✅ M1：Readability 擷取 → Native 回傳原文（echo）→ Popup 顯示
- ✅ M2：模型下載（App）+ 模型狀態（Extension）+ 未就緒提示
- ⏭️ M3：真正使用本地模型產生摘要（Qwen3 MLX 4bit）
- ⏸️ M10（未來）：Share Extension + App Intent

## M1（已完成）

- ✅ Extension：`content.js` 只做 Readability 擷取
- ✅ Extension：`background.js` 流程改為呼叫 native `summarize.start`
- ✅ Native：`SafariWebExtensionHandler.swift` 在 M1 以 echo mode 回傳正文
- ✅ UI：`popup.js` 顯示狀態與結果；移除 `contentGPT.js` fallback 與 settings 面板引用

## M2（已完成）

- ✅ App Group：`group.com.qoli.eisonAI`（App / iOS Extension entitlements 已更新）
- ✅ 模型固定 revision：`75429955681c1850a9c8723767fe4252da06eb57`
- ✅ 模型下載與落盤：`iOS (App)/ModelDownloadManager.swift`
  - ✅ 修正 CFNetworkDownload tmp 檔案搬移時機（必須在 `didFinishDownloadingTo` 內 move）
- ✅ App 最小 UI：只提供下載按鈕與進度/狀態（WebView UI）
- ✅ Extension gating：
  - ✅ `model.getStatus` 顯示 `notInstalled/downloading/verifying/ready/failed`
  - ✅ `MODEL_NOT_READY` 提示使用者打開 App 下載模型

## M3（下一步：本地推理產生摘要）

### 3.1 需要先決策（缺的資料/決策）

- [ ] 推理 runtime：要用 `AnyLanguageModel`（需修 macro build）或改用其他（例如 `mlx-swift`/`mlx-swift-lm` 類路線）
- [ ] `AnyLanguageModel`：目前已改成本地 package reference（`../AnyLanguageModel`）；若要用 MLX 本地模型需確保專案已啟用 `MLX`（trait / build 設定）
- [ ] 目標行為：先「非串流一次性回傳」(M3a) 還是直接做「串流/輪詢」(M3b)
- [ ] 生成參數預設值：`temperature`、`maxOutputTokens`、stop/重複懲罰等
- [ ] Prompt 預設內容：
  - [ ] `APPSystemText`
  - [ ] `APPPromptText`（user template；含 `{{title}}` / `{{text}}` 之類 placeholder）

### 3.2 主要工作項目

- [ ] 新增/落地 `LocalLLMService`（shared）：
  - [ ] 從 App Group model path 載入模型（repoId + revision）
  - [ ] tokenizer + prompt 拼裝
  - [ ] 產生符合 `eison.summary.v1` 格式輸出（`總結：` + `要點：`）
- [ ] 長文處理（chunk + reduce）：
  - [ ] 先以字元長度 chunk（MVP），後續可改 tokenizer-based
- [ ] Extension ↔︎ Native 串流：
  - [ ] 先確認 iOS Safari `connectNative` 是否可用；否則走 `summarize.poll`
  - [ ] `background.js` 支援 `stream/done/error` 並 forward 到 `popup.js`
- [ ] 快取策略：
  - [ ] M3 開始恢復快取（目前 echo mode `noCache:true`）

## M10（未來實現）

- [ ] Share Extension（分享 URL/文字）→ 呼叫同一套 `LocalLLMService`
- [ ] App Intent（Shortcuts）`SummarizeTextIntent` / `SummarizeURLIntent`
- [ ] 每站客製 prompt（regex rule；根域名輸入是 regex 簡寫；不匹配子域名）

## 已知風險 / 觀察

- `swift-huggingface` 在 iOS 編譯會踩到 `homeDirectoryForCurrentUser`（因此 M2 已改用 `URLSession` 直接 resolve 下載）。
- AnyLanguageModel 的 MLX 支援需要啟用 `MLX`（trait / build 設定）。
- AnyLanguageModel README 提到 Xcode 26 + iOS 18/更早 可能會有 build bug（必要時改用 Xcode 16 toolchain）。
