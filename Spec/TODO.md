# TODO：EisonAI（Safari Web Extension + iOS 主 App）

## ✅ 已完成

- ✅ Extension popup 改用 WebLLM（`webllm/popup.*` + `webllm/worker.js`）。
- ✅ 模型與 wasm 以 **extension bundle assets** 提供（`Shared (Extension)/Resources/webllm-assets/`），popup 不做 runtime 下載。
- ✅ popup Markdown 渲染改用 Marked（本地 `Shared (Extension)/Resources/webllm/marked.umd.js`，不使用遠端 CDN）。
- ✅ 專案最低版本調整為 iOS / iPadOS 18+（deployment target）。
- ✅ CSP 調整允許 wasm/worker（`manifest.json` 同時提供 `extension_page` / `extension_pages`）。
- ✅ Safari `safari-web-extension://` scheme 相容：修正 `Request url is not HTTP/HTTPS`（`webllm/webllm.js` 對非 http(s) URL 避免走 Cache API）。
- ✅ 移除 native messaging 推理 / 模型下載管線（專案全面轉向 WebLLM）。
- ✅ iOS 主 App 新增原生 MLC Swift SDK（`MLCSwift`/`MLCEngine`）Qwen3 0.6B 單輪 streaming demo（SwiftUI + `NavigationLink`）。
- ✅ iOS target build settings 已加入 `dist/lib` 搜尋路徑與必要 linker flags，並把 `dist/bundle` 加入 App Resources（供 `bundle/mlc-app-config.json` 與模型權重讀取）。
- ✅ 新增 `mlc-package-config.json`（供 `mlc_llm package` 產生 `dist/`），並在 `.gitignore` 忽略大型 `dist/` 產物。

## 🔜 下一步

### iOS 主 App（SwiftUI 驅動）

- [x] 以 SwiftUI `App` lifecycle 取代 storyboard/SceneDelegate（移除對 `Main.storyboard` 的依賴）。
- [x] SwiftUI Onboarding：提示「設定 → Safari → Extensions」開啟擴充功能（保留現有文案重點）。
- [x] SwiftUI 設定頁：System Prompt 編輯/儲存/重置（使用 App Group：`group.com.qoli.eisonAI`、key：`eison.systemPrompt`）。
- [x] UI/UX：儲存狀態提示（Saved/Reset），並處理空字串視為「回到預設」。
- [ ] 產出 MLC iOS 所需檔案：在 repo 根目錄執行 `MLC_LLM_SOURCE_DIR=/Volumes/Data/Github/mlc-llm mlc_llm package`，生成 `dist/bundle` + `dist/lib`。
- [ ] 確認 Qwen3 0.6B 的 `model_id`/量化版本與 `model_lib`（以 `dist/bundle/mlc-app-config.json` 為準），並讓 demo 預設選到可用模型。
- [ ] 真機驗證：首次載入時間、streaming 是否順暢、記憶體峰值與退場處理（clear / cancel / reset）。
- [ ] 清理：移除不再使用的 `Shared (App)` WebView/HTML 設定頁（或降級為 legacy/備用）。

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
