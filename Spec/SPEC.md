# Spec：EisonAI（Safari Web Extension + iOS 主 App）

## 背景

先前嘗試在 `SafariWebExtensionHandler`（native messaging）內跑本地 LLM（MLX）推理，但在 Safari Extension 的執行環境下（特別是 native handler）算力/資源配置明顯不足：同一模型在主 App 可 20s 內回應，但在 extension handler 可能需要數分鐘，甚至在部分 iPad（如高階機種）直接拒絕啟動。

因此方案改為：

- **推理移到 popup 頁面**，使用 `mlc-ai/web-llm`（WebGPU + WebWorker）。
- **模型與 wasm 以本地 assets 打包進 extension bundle**，popup 僅讀取本地資源，不做 runtime 下載、也不依賴 iOS extension 的持久儲存。

同時，iOS 主 App 是 Safari Web Extension 的 container（負責上架、承載 extension、提供設定 UI）。原本主 App 以 UIKit + storyboard + `WKWebView` 載入本地 HTML 做設定頁；為了後續主 App 更容易擴充功能與維護，規劃改為 **SwiftUI 驅動** 的原生 UI。

## 目標（to-be）

- iOS/iPadOS Safari extension：popup 一鍵取得「目前分頁」文章摘要（繁體中文）。
- 模型：`mlc-ai/Qwen3-0.6B-q4f16_1-MLC`（本地 assets）。
- 離線優先：popup 不做 runtime 下載；`IndexedDB` cache 關閉（避免依賴持久儲存）。
- 同一套 popup 亦可用於 macOS Safari（包含 “My Mac (Designed for iPad)”）。
- iOS 主 App：以 SwiftUI 提供 onboarding 與輕量設定（例如 System Prompt），資料透過 App Group 與 extension 共用。
- iOS 主 App（dev/demo）：新增一個 **原生 MLC Swift SDK**（`MLCSwift`/`MLCEngine`）的 Qwen3 0.6B 單輪 streaming demo，用於驗證模型打包與推理鏈路（不依賴 WebView / WebLLM）。

## 非目標（non-goals）

- 不再在 native handler 內做推理或模型下載。
- 不把 Safari extension popup UI 改成 SwiftUI（popup 仍必須是 HTML/JS）。
- 不提供遠端 API（OpenAI/Gemini）fallback（若需要再另開規格）。
- 不做長期持久快取（iOS extension 儲存限制 + 可預期不穩定）。

## 系統需求

- iOS / iPadOS 18+（以確保 WebGPU + WebLLM 的可用性/穩定性）
- Apple Intelligence（可選）：若要啟用 **Foundation Models framework** 推理路線，需 iOS/iPadOS 26+ 且裝置/設定滿足 Apple Intelligence 條件（否則會自動 fallback 到既有 WebLLM/MLC）。
- 執行環境：
  - ✅ iPhone/iPad 真機（iphoneos）
  - ✅ My Mac (Designed for iPad)（以 iOS app 形式在 macOS 上執行）
  - ❌ Mac Catalyst：目前不支援（`dist/lib/*.a` 為 iphoneos 靜態庫，無法直接用於 `*-apple-ios-macabi`）

## 系統架構

### iOS 主 App（SwiftUI）

- App lifecycle：SwiftUI `@main App`，不依賴 storyboard/`SceneDelegate`。
- 主要功能：
  - Onboarding：引導使用者到「設定 → Safari → Extensions」開啟擴充功能。
  - 設定：編輯/儲存/重置 System Prompt（給 popup 摘要用）。
  - Demo（dev）：`MLCQwenDemoView` 單輪 streaming chat（入口 `NavigationLink`）。
- 資料儲存（與 extension 共用）：
  - App Group：`group.com.qoli.eisonAI`
  - Key：`eison.systemPrompt`
  - 規則：空字串/全空白視為「回到預設 prompt」。
  - （可選）Foundation Models 開關：
    - `eison.foundationModels.app.enabled`
    - `eison.foundationModels.extension.enabled`

#### iOS 原生 MLC Swift Demo（MLCSwift）

- 依賴來源：`/Users/ronnie/Github/mlc-llm/ios/MLCSwift`（Xcode 以 local package 引入）。
- **真機限定**：目前 `dist/lib/*.a` 為 `arm64` 靜態庫，專案不支援 iOS Simulator（僅在 iPhone/iPad 真機上建置/執行）。
- 模型/權重來源：Safari extension 的 `webllm-assets`（同一份 assets 同時供 WebLLM 與原生 MLC demo 使用），主 App 以唯讀方式從 **Embedded Extension（`.appex`）** 內存取。
- 模型設定來源：`iOS (App)/Config/mlc-app-config.json`（小檔資源，提供 `model_id` / `model_lib` / `model_path`）。
- Demo 尋找模型方式：
  - 讀取 app bundle 的 `mlc-app-config.json`
  - 從 `model_list` 找到符合 `model_id` 且有 `model_path` 的紀錄
  - `model_path` 以 Embedded Extension 的 `webllm-assets/models/<model_id>/resolve/main` 為準
  - 以 `MLCEngine.reload(modelPath:modelLib:)` 載入，並用 `engine.chat.completions.create(...)` streaming 輸出

#### MLC LLM 打包產物（dist）

- 專案內路徑（不進 Git）：`dist/`
  - `dist/bundle/`：包含 `mlc-app-config.json`、模型目錄（內含 `mlc-chat-config.json`、tokenizer、weights 等）
  - `dist/lib/`：包含 iOS 連結所需靜態庫（供 `LIBRARY_SEARCH_PATHS` + `OTHER_LDFLAGS`）
- 打包設定檔：repo 根目錄 `mlc-package-config.json`（供 `mlc_llm package` 使用）
- 產生方式（開發者在本機執行）：`MLC_LLM_SOURCE_DIR=/Users/ronnie/Github/mlc-llm mlc_llm package`

### Safari Web Extension（WebLLM popup）

- `contentReadability.js` + `content.js`：使用 Readability 解析頁面正文，回傳 `{ title, body }`。
- `webllm/popup.html`、`webllm/popup.js`、`webllm/worker.js`：popup UI + WebLLM engine（worker 內跑）。
- `webllm/webllm.js`：vendor 的 WebLLM runtime（含 Safari `safari-web-extension://` scheme workaround patch）。
- `webllm-assets/`：模型與 wasm 檔案（由 Xcode 打包進 extension）。
- Markdown 渲染：popup 使用本地 `marked.umd.js`（避免遠端 CDN 及 CSP/上架限制）。
- （可選）Foundation Models（Apple Intelligence）推理路線：
  - 目的：不改變 popup 行為/提示詞，只替換推理引擎（WebLLM ↔ FoundationModels）。
  - 實作：popup 透過 native messaging 以 **Start + Poll（120ms）** 取得 streaming delta；失敗/中斷會自動 fallback 回 WebLLM。
  - RawLibrary：FoundationModels 路線固定寫入 `modelId = foundation-models`。

### 通訊流程（摘要）

1. popup → content script：`tabs.sendMessage({ command: "getArticleText" })`
2. content script → popup：回傳 `{ title, body }`
3. popup 建立 WebWorker + WebLLM engine（WebGPU），從本地 assets 載入模型/wasm
4. popup 以 streaming 方式生成摘要並顯示

## Assets 打包（必做）

- 放置路徑：`Shared (Extension)/Resources/webllm-assets/`
- 預期結構：
  - `models/Qwen3-0.6B-q4f16_1-MLC/resolve/main/*`
  - `wasm/Qwen3-0.6B-q4f16_1-ctx4k_cs1k-webgpu.wasm`
- 下載腳本：`python3 Scripts/download_webllm_assets.py`
- Git：大檔已在 `.gitignore` 忽略（開發者需自行下載）

## 平台/瀏覽器限制與對策

- **WebGPU 必須可用**；否則 popup 顯示錯誤並禁止 Load。
- Safari extension 使用 `safari-web-extension://` scheme：
  - WebLLM 若透過 Cache API + `new Request(url)` 會拋 `Request url is not HTTP/HTTPS`
  - 已在 `webllm/webllm.js` 對非 http(s) URL 做 fallback（直接 fetch，不走 Cache API）
- CSP：
  - 需允許 wasm：`'wasm-unsafe-eval'`（並保留 Safari 兼容的 `'unsafe-eval'`）
  - `worker-src` 需允許 `blob:`

## 交付物（MVP）

- popup：`Load / Unload / Summarize active tab / Generate`
- 模型與 wasm：以 extension bundle 提供（無 runtime 下載）

## 後續延伸（可選）

- 長文：chunk + reduce pipeline（先以字元切分，再做合併摘要）
- UI：複製、分享、格式化（維持離線/無持久儲存依賴）
- 多模型切換（仍以 bundled assets 為前提）
