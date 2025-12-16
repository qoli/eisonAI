# Spec：Safari iOS Web Extension · WebLLM（Popup 推理 + Bundled Assets）

## 背景

先前嘗試在 `SafariWebExtensionHandler`（native messaging）內跑本地 LLM（MLX）推理，但在 Safari Extension 的執行環境下（特別是 native handler）算力/資源配置明顯不足：同一模型在主 App 可 20s 內回應，但在 extension handler 可能需要數分鐘，甚至在部分 iPad（如高階機種）直接拒絕啟動。

因此方案改為：

- **推理移到 popup 頁面**，使用 `mlc-ai/web-llm`（WebGPU + WebWorker）。
- **模型與 wasm 以本地 assets 打包進 extension bundle**，popup 僅讀取本地資源，不做 runtime 下載、也不依賴 iOS extension 的持久儲存。

## 目標（to-be）

- iOS/iPadOS Safari extension：popup 一鍵取得「目前分頁」文章摘要（繁體中文）。
- 模型：`mlc-ai/Qwen3-0.6B-q4f16_1-MLC`（本地 assets）。
- 離線優先：popup 不做 runtime 下載；`IndexedDB` cache 關閉（避免依賴持久儲存）。
- 同一套 popup 亦可用於 macOS Safari（包含 “My Mac (Designed for iPad)”）。

## 非目標（non-goals）

- 不再在 native handler 內做推理或模型下載。
- 不提供遠端 API（OpenAI/Gemini）fallback（若需要再另開規格）。
- 不做長期持久快取（iOS extension 儲存限制 + 可預期不穩定）。

## 系統需求

- iOS / iPadOS 18+（以確保 WebGPU + WebLLM 的可用性/穩定性）

## 系統架構

### Extension 構成

- `contentReadability.js` + `content.js`：使用 Readability 解析頁面正文，回傳 `{ title, body }`。
- `webllm/popup.html`、`webllm/popup.js`、`webllm/worker.js`：popup UI + WebLLM engine（worker 內跑）。
- `webllm/webllm.js`：vendor 的 WebLLM runtime（含 Safari `safari-web-extension://` scheme workaround patch）。
- `webllm-assets/`：模型與 wasm 檔案（由 Xcode 打包進 extension）。

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
