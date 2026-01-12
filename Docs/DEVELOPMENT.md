# 開發者指南（WebLLM Popup 方案）

本專案是 **Safari Web Extension（iOS/iPadOS 18+）**，在 extension 的 **popup** 內用 **WebLLM（WebGPU + WebWorker）** 執行本地推理，並以 **bundled assets** 的方式把模型與 wasm 打包進 extension bundle（不做 runtime 下載、不依賴 iOS extension 持久儲存）。

## 1) 你需要知道的架構決策

- **推理只在 popup 內做**：不使用 `SafariWebExtensionHandler`（native messaging）做推理（算力/資源配置不足且不穩）。
- **模型/wasm 必須打包進 extension bundle**：開發時用腳本下載到 `Shared (Extension)/Resources/webllm-assets/`；Git 會忽略大檔（每位開發者自行下載）。
- **不使用 background/service worker**：目前流程由 popup 直接 `tabs.sendMessage` 向 content script 取文章內容，再於 popup 內推理。

## 2) 目錄結構（你最常改的地方）

- Extension manifest / CSP：`Shared (Extension)/Resources/manifest.json`
- 內容擷取（Readability）：`Shared (Extension)/Resources/contentReadability.js` + `Shared (Extension)/Resources/content.js`
- WebLLM popup UI：`Shared (Extension)/Resources/webllm/popup.html`
- WebLLM popup 邏輯：`Shared (Extension)/Resources/webllm/popup.js`
- WebWorker 入口：`Shared (Extension)/Resources/webllm/worker.js`
- WebLLM runtime（vendor + Safari patch）：`Shared (Extension)/Resources/webllm/webllm.js`
- 模型/wasm（打包進 extension）：`Shared (Extension)/Resources/webllm-assets/`
- 下載 assets 腳本：`Scripts/download_webllm_assets.py`

## 3) 開發環境需求

- Xcode（能建置 iOS/iPadOS 18+）
- Python 3（下載 WebLLM assets 用）
- 一台 iPhone/iPad（建議真機驗證 WebGPU；模擬器不代表真實 Safari 行為）

## 4) 第一次跑起來（必做：下載 assets）

1. 下載模型與 wasm 到 extension 的 assets 目錄：

```bash
python3 Scripts/download_webllm_assets.py
```

2. 打開並建置：

```bash
open eisonAI.xcodeproj
```

3. iOS/iPadOS 啟用 extension：

- 設定 → Safari → 擴充功能 → 啟用 `eisonAI`
- 允許在網站上使用（依需求設定「所有網站 / 指定網站」）

4. 使用方式：

- 在 Safari 開啟任一文章頁
- 點工具列的 extension 圖示 → 進入 popup
- popup 會先檢查 Readability 是否能取得正文：
  - 有正文：自動載入模型並自動開始總結
  - 無正文：顯示「無可用總結正文」

## 5) Debug/排障方式（最常用）

### 5.1 看 popup / worker console

popup/worker 內會 `console.log`（例如 model/wasm URL、載入進度等）。建議用 macOS Safari 的 Develop 選單做遠端檢視（連 iPhone/iPad 的 Safari）。

### 5.2 常見錯誤

- **WebGPU unavailable**
  - 現象：`Load` 直接報 WebGPU 不可用
  - 方向：確認裝置/系統版本支援 WebGPU、Safari 設定是否限制、是否在正確的 Safari 環境（而非 WebView/受限容器）

- **CSP / wasm 被擋**
  - 現象：`Refused to create a WebAssembly object... 'unsafe-eval'/'wasm-unsafe-eval'`
  - 方向：檢查 `Shared (Extension)/Resources/manifest.json` 的 `content_security_policy` 是否包含 `'wasm-unsafe-eval'` 與 `worker-src`

- **Request url is not HTTP/HTTPS**
  - 現象：Safari 對 `safari-web-extension://...` URL 在某些 Cache API 路徑會拋錯
  - 方向：本專案已在 vendor 的 `webllm.js` 做 workaround（避免對非 http(s) URL 走 Cache API + `new Request(url)`），若你更新 WebLLM runtime 記得保留此 patch

- **Assets 缺檔**
  - 現象：載入時 404 / fetch fail
  - 方向：確認 `Shared (Extension)/Resources/webllm-assets/` 目錄結構與檔案完整；重新跑下載腳本

## 6) 常見開發任務

### 6.1 修改摘要 prompt

- 預設 system prompt：`Shared (Extension)/Resources/default_system_prompt.txt`
- popup 會先透過 native messaging（`browser.runtime.sendNativeMessage`）讀取主 App 設定；若未設定則使用預設值
- 預設 chunk prompt（長文閱讀錨點）：`Shared (Extension)/Resources/default_chunk_prompt.txt`
- 預設 title prompt（App 端補標題）：`Shared (Extension)/Resources/default_title_prompt.txt`
- user prompt 模板（正文格式/截斷策略）：
  - 共用：`Shared (Extension)/Resources/summary_user_prompt.txt`
- 長文閱讀錨點模板：
  - system suffix：`Shared (Extension)/Resources/reading_anchor_system_suffix.txt`
  - user prompt：`Shared (Extension)/Resources/reading_anchor_user_prompt.txt`
  - anchors 聚合格式：`Shared (Extension)/Resources/reading_anchor_summary_item.txt`

### 6.2 修改 chat template（MLC conv_template）

WebLLM/MLC 會從模型目錄的 `mlc-chat-config.json` 讀取 `conv_template` 來把 OpenAI-style `messages[]` 轉成實際 prompt。

- 檔案位置（assets 下載後才會存在）：`Shared (Extension)/Resources/webllm-assets/models/Qwen3-0.6B-q4f16_1-MLC/resolve/main/mlc-chat-config.json`
- 你可調整的欄位：`conv_template.system_template` / `roles` / `seps` / `stop_str` / `stop_token_ids` 等

注意：`tokenizer_config.json` 裡的 HuggingFace `chat_template` **不會被 WebLLM 用來組 prompt**；WebLLM 使用的是 `mlc-chat-config.json` 的 `conv_template`。

### 6.3 切換模型（仍維持 bundled assets）

1. 更新 `popup.js` 的：
   - `MODEL_ID`
   - `WASM_FILE`
   - `getLocalAppConfig(...)` 內的 model/wasm URL
2. 調整 `webllm-assets/` 下載與目錄結構（必要時更新 `Scripts/download_webllm_assets.py`）

### 6.4 更新 WebLLM runtime（vendor）

`Shared (Extension)/Resources/webllm/webllm.js` 是 vendored 檔案。若從 upstream 更新：

- 先替換成新版本
- 再把 Safari `safari-web-extension://` 的相容 patch 重新套回去（避免 Cache API 對非 http(s) URL 報錯）

### 6.5 加長文處理（chunk + reduce）

目前 `popup.js` 以字元截斷避免 prompt 過大。若要提升品質：

- 在 popup 端做 chunk（字元或 tokenizer-based）
- 先逐段摘要，再做合併摘要（reduce）

## 7) 與舊架構的差異（避免走回頭路）

- 舊的 `settings` / 遠端 API / native messaging 推理已移除。
- `SafariWebExtensionHandler.swift` 只用於輕量設定（例如 system prompt），不做推理、不做下載。

## 8) 延伸閱讀

- 內容擷取協定：`Docs/content.js.md`
- WebLLM popup 說明：`Docs/popup.md`
