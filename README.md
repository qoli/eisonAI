# EisonAI

EisonAI 是一個 iOS/macOS 的 Safari Web Extension：在 popup 內使用 **WebLLM（WebGPU + WebWorker）** 於本機執行 `Qwen3-0.6B`（MLC）並摘要目前網頁內容。

本專案採用 **bundled assets** 策略：模型與 wasm 會被打包進 extension bundle，popup 只讀取本地資源，不做 runtime 下載，也不依賴 iOS extension 的持久儲存。

## 架構概覽

- 內容擷取：`Shared (Extension)/Resources/contentReadability.js` + `Shared (Extension)/Resources/content.js`
- 推理入口：`Shared (Extension)/Resources/webllm/popup.html`（`action.default_popup`）
- WebLLM runtime：`Shared (Extension)/Resources/webllm/webllm.js`
- 模型/wasm（需下載後放入）：`Shared (Extension)/Resources/webllm-assets/`

## 開發（必做：下載 assets）

1. 下載模型與 wasm 到 extension assets 目錄：

```bash
python3 Scripts/download_webllm_assets.py
```

2. 用 Xcode 打開並建置：

```bash
open eisonAI.xcodeproj
```

## 常見限制

- 需要 WebGPU；若裝置/系統不支援，popup 會提示無法載入模型。
- Safari extension 使用 `safari-web-extension://` scheme；專案已在 vendor 的 `webllm/webllm.js` 針對非 http(s) URL 做相容處理。
