# Popup（WebLLM）技術文檔

本專案的推理入口是 **Safari extension 的 popup**，以 **WebLLM（WebGPU + WebWorker）** 執行本機推理，並從 extension bundle 讀取已打包的模型/wasm assets。

對應檔案：

- `Shared (Extension)/Resources/webllm/popup.html`
- `Shared (Extension)/Resources/webllm/popup.css`
- `Shared (Extension)/Resources/webllm/popup.js`
- `Shared (Extension)/Resources/webllm/worker.js`
- `Shared (Extension)/Resources/webllm/webllm.js`（vendored）
- `Shared (Extension)/Resources/webllm-assets/`（bundled assets）

## 入口與 CSP

- popup 入口由 `Shared (Extension)/Resources/manifest.json` 的 `action.default_popup` 指向 `webllm/popup.html`。
- 為了讓 WebAssembly / WebWorker 正常運作，`manifest.json` 的 `content_security_policy` 需要允許：
  - `script-src`：`'wasm-unsafe-eval'`（並保留 `'unsafe-eval'` 做 Safari 兼容）
  - `worker-src`：`blob:`（以及 `'self'`）

## UI（popup.html）

目前 demo UI 提供：

- Model 選擇（目前只放 `Qwen3-0.6B-q4f16_1-MLC`）
- `Load / Unload`
- `Summarize active tab`（擷取目前分頁文章正文 → 生成摘要）
- `複製系統提示詞` / `複製用戶提示詞`（方便檢查送入模型的 prompts）
- `Generate / Stop`（手動輸入 prompt 生成）
- 狀態文字 + 進度條 + 輸出區

## 推理核心（popup.js）

### WebGPU 檢查

popup 會先檢查 `navigator.gpu`，若 WebGPU 不可用則阻止載入模型。

### WebWorker + Engine

- 以 module worker 建立 `worker.js`
- 透過 `CreateWebWorkerMLCEngine(worker, modelId, { appConfig, initProgressCallback })` 建立 engine

### 使用 bundled assets（關鍵）

- `appConfig.useIndexedDBCache = false`（避免依賴持久儲存）
- model/wasm URL 使用 `new URL(..., import.meta.url)` 組成 extension bundle URL
- `model_list` 內指定：
  - `model_id`
  - `model`（指向 `webllm-assets/models/.../resolve/main/`）
  - `model_lib`（指向 `webllm-assets/wasm/*.wasm`）

### 取得文章正文（popup → content script）

popup 透過 `browser.tabs.query` 取得 active tab，再以：

```js
browser.tabs.sendMessage(tab.id, { command: "getArticleText" });
```

向 `content.js` 請求 Readability 解析結果（詳見 `Docs/content.js.md`）。

### Streaming 輸出

`Summarize` 與 `Generate` 都使用 streaming：

- `engine.chat.completions.create({ stream: true, ... })`
- 逐段把 `delta.content` append 到 output
- `Stop` 會呼叫 `engine.interruptGenerate()`

## Safari 特殊相容（safari-web-extension://）

Safari extension 的資源 URL 通常是 `safari-web-extension://...`。

WebLLM 在某些 Cache API 路徑會對非 http(s) URL 丟出：

`TypeError: Request url is not HTTP/HTTPS`

本專案已在 vendored `Shared (Extension)/Resources/webllm/webllm.js` 內做 workaround（避免 Cache API + `new Request(url)` 對非 http(s) URL），若你更新 WebLLM runtime 記得保留此 patch。

## 如何繼續開發

- 修改摘要 prompt：調整 `Shared (Extension)/Resources/webllm/popup.js` 的 `buildSummaryMessages(...)`
- 長文策略：改成 chunk + reduce（避免目前單次截斷）
- 模型切換：更新 `MODEL_ID` / `WASM_FILE` 與 `getLocalAppConfig(...)`，並同步調整 `webllm-assets/` 下載與 layout
