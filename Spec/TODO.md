# TODO：EisonAI（Safari Web Extension + iOS 主 App）

## ✅ 已完成

- ✅ Extension popup 改用 WebLLM（`webllm/popup.*` + `webllm/worker.js`）。
- ✅ 模型與 wasm 以 **extension bundle assets** 提供（`Shared (Extension)/Resources/webllm-assets/`），popup 不做 runtime 下載。
- ✅ popup Markdown 渲染改用 Marked（本地 `Shared (Extension)/Resources/webllm/marked.umd.js`，不使用遠端 CDN）。
- ✅ 專案最低版本調整為 iOS / iPadOS 18+（deployment target）。
- ✅ CSP 調整允許 wasm/worker（`manifest.json` 同時提供 `extension_page` / `extension_pages`）。
- ✅ Safari `safari-web-extension://` scheme 相容：修正 `Request url is not HTTP/HTTPS`（`webllm/webllm.js` 對非 http(s) URL 避免走 Cache API）。
- ✅ 移除 native messaging 推理 / 模型下載管線（專案全面轉向 WebLLM）。
- ✅ 產出 MLC iOS 所需檔案：在 repo 根目錄執行 `MLC_LLM_SOURCE_DIR=/Users/ronnie/Github/mlc-llm mlc_llm package`，生成 `dist/lib`（與 `dist/bundle` 供檢查/比對用）。
- ✅ iOS 主 App link 完成：`dist/lib` 搜尋路徑 + linker flags（包含 `-ltvm_ffi_static`）可成功 Build（真機 `arm64`）。
- ✅ iOS 目標為真機限定：移除 iOS Simulator 支援（`SUPPORTED_PLATFORMS` 不含 `iphonesimulator`）。
- ✅ iOS 主 App 新增原生 MLC Swift SDK（`MLCSwift`/`MLCEngine`）Qwen3 0.6B 單輪 streaming demo（SwiftUI + `NavigationLink`），真機 smoke test 可正常 streaming。
- ✅ `mlc-app-config.json` 以小檔資源打進 iOS App（`iOS (App)/Config/mlc-app-config.json`），提供 `model_id` / `model_lib` / `model_path`。
- ✅ 模型檔案統一使用 `webllm-assets`：`webllm-assets` 同時標記為 iOS App 與 iOS Extension 的 Target Membership，使其在 App bundle 中以 Embedded Extension resource 的形式存在，供主 App 以唯讀方式存取（不修改 popup/extension 行為）。
- ✅ 清理：移除 `Shared (App)` 舊的 WKWebView/HTML 設定頁（不保留 legacy 回退支持）。
- ✅ 整理：`iOS (App)` 目錄按 App/Features/Shared 分層，提升可維護性（並同步更新 Xcode 專案引用）。
- ✅ 新增 `mlc-package-config.json`（供 `mlc_llm package` 產生 `dist/`），並在 `.gitignore` 忽略大型 `dist/` 產物。

## 🔜 下一步

### iOS 主 App（SwiftUI 驅動）

- [x] 以 SwiftUI `App` lifecycle 取代 storyboard/SceneDelegate（移除對 `Main.storyboard` 的依賴）。
- [x] SwiftUI Onboarding：提示「設定 → Safari → Extensions」開啟擴充功能（保留現有文案重點）。
- [x] SwiftUI 設定頁：System Prompt 編輯/儲存/重置（使用 App Group：`group.com.qoli.eisonAI`、key：`eison.systemPrompt`）。
- [x] UI/UX：儲存狀態提示（Saved/Reset），並處理空字串視為「回到預設」。
- [x] 確認 Qwen3 0.6B 的 `model_id`/量化版本與 `model_lib`，並讓 demo 預設選到可用模型（`iOS (App)/Config/mlc-app-config.json`）。
- [ ] 真機驗證（進階）：首次載入時間、streaming 是否順暢、記憶體峰值與退場處理（clear / cancel / reset / background ↔ foreground）。
- [ ] Demo UX：加入 Stop/Cancel、顯示「目前載入的 model_id」、以及更明確的錯誤訊息（缺檔/路徑不符時不崩潰）。
- [ ] 開發流程：將 `iOS (App)/Config/mlc-app-config.json` 的更新流程文件化（從 `dist/bundle/mlc-app-config.json` 同步 `model_lib`），避免重新 `mlc_llm package` 後 hash 變更造成載入失敗。
- [ ] macOS（Mac Catalyst）支援（for Titlebar 可控）：
  - [ ] 產出 macabi 靜態庫：目前 `dist/lib/*.a` 為 iphoneos（arm64）靜態庫，無法在 `arm64-apple-ios-macabi`/`x86_64-apple-ios-macabi` 下連結（會出現「Building for macCatalyst, but linking ... built for iOS」）
  - [ ] 需要一套對應的 TVM/MLC runtime + tokenizers + sentencepiece + model lib（例如 `libtvm_runtime.a`、`libtvm_ffi_static.a`、`libmlc_llm.a`、`libtokenizers_*.a`、`libsentencepiece.a`、以及 Catalyst 專用的 `libmodel_*.a`）
  - [ ] Xcode link 分流：iphoneos vs macabi（建議用 `.xcframework` 或依 `EFFECTIVE_PLATFORM_NAME` 分開 `LIBRARY_SEARCH_PATHS/OTHER_LDFLAGS`）
  - [ ] `mlc_llm package` 目前設定是 `"device": "iphone"`（`mlc-package-config.json`），需確認/擴充是否能產出 macCatalyst 目標的 `dist/lib-*`（可能要改 `/Users/ronnie/Github/mlc-llm` 的 build/package 流程）

### Safari Extension popup（WebLLM）

- [ ] 長文處理：chunk + reduce（避免目前 `popup.js` 以字元截斷 6k 的資訊流失）。
- [ ] popup UX：
  - [ ] 顯示「目前頁面標題/URL」與截斷提示
  - [ ] 加入「複製結果」/「一鍵清除」的小工具
- [ ] WebGPU 不可用時的引導（Safari 設定/裝置限制提示）。
- [ ] 開發流程：
  - [ ] 在 `README.md` 加入「下載 assets」與「常見錯誤（CSP / WebGPU / 缺檔）」排障段落
  - [ ] 在 `Scripts/download_webllm_assets.py` 加上缺檔校驗/輸出摘要（避免漏抓）
- [ ] 可選清理：
  - [ ] 若不再需要 App Group，移除 `iOS.entitlements` / `eisonAI Extension (iOS).entitlements` 的相關 capability
  - [ ] 盤點並移除未使用的資源（icon/locale 除外）
  - [ ] 移除未再使用的 `showdown.min.js`（已改用 Marked）
