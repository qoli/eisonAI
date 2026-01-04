# EisonAI

EisonAI 是一個 iOS/iPadOS 的 Safari Web Extension + App，目標是把「結構」變成可見的閱讀入口。你不必照著作者的線性敘事走，先看到重點與結構，再決定要深入哪一段。

Safari popup 內使用 **WebLLM（WebGPU + WebWorker）** 本機推理 `Qwen3-0.6B`；App 端則使用 **MLCSwift**（以及可選的 Apple Intelligence）做摘要與長文處理。

本專案採用 **bundled assets** 策略：模型與 wasm 會被打包進 extension bundle，popup 只讀取本地資源，不做 runtime 下載，也不依賴 iOS extension 的持久儲存。

![EisonAI Screenshot](https://raw.githubusercontent.com/qoli/eisonAI/refs/heads/main/assets/iPhone-Medata-Preview.jpg)

## Building a Safari Extension with a Fully Local LLM (WebLLM)

項目展示：
https://youtu.be/tC25imOO9GA

## App Store & TestFlight

### TestFlight

https://testflight.apple.com/join/1nfTzlPS

### App Store

https://apps.apple.com/us/app/eison-ai/id6484502399

## 產品概念

- **Cognitive Index™**：讓結構先於內容被看見，降低閱讀定位成本。
- **Read less linearly**：閱讀不必跟著敘事順序走。
- **Think more deliberately**：把注意力留給判斷與理解，而非維持上下文。
- **Make structure visible**：先看到關係與重點，再決定深入路徑。

## 功能概覽

- **Safari Extension**：在 Safari 內直接生成摘要與結構化重點，無需離開瀏覽器。
- **Cognitive Index™**：以結構化輸出呈現關鍵點，協助快速定位「意義生成」的區段。
- **Long-Document**：長文分段處理，支援約 15,000 tokens 級別的內容。
- **Local-First**：本機推理與儲存，保護隱私。
- **CloudKit Sync**：跨裝置同步 Library。
- **Library & Tags**：收藏、標籤與檢索。
- **Language of Thought**：選擇模型「思考與輸出」的語言，可隨時調整。
- **Open Source**：可審查的隱私與行為。

## 系統需求

- iOS / iPadOS 18+
- Apple Intelligence（可選）：iOS 26+ 且已啟用
- 建議至少 iPhone 14 以上機型體驗較佳

## 架構概覽

- 內容擷取：`Shared (Extension)/Resources/contentReadability.js` + `Shared (Extension)/Resources/content.js`
- 推理入口：`Shared (Extension)/Resources/webllm/popup.html`（`action.default_popup`）
- WebLLM runtime：`Shared (Extension)/Resources/webllm/webllm.js`
- 模型/wasm（需下載後放入）：`Shared (Extension)/Resources/webllm-assets/`
- Native bridge（設定/儲存/Apple Intelligence）：`Shared (Extension)/SafariWebExtensionHandler.swift`
- App Library & Sync：App Group RawLibrary + CloudKit（詳見 `iOS (App)/Shared`）

## 開發（必做：下載 assets）

開發流程與排障細節請看：`Docs/DEVELOPMENT.md`

1. 下載模型與 wasm 到 extension assets 目錄：

```bash
python3 Scripts/download_webllm_assets.py
```

2. 用 Xcode 打開並建置：

```bash
open eisonAI.xcodeproj
```

3. 若需重建 MLC xcframeworks（需設定 `MLC_LLM_SOURCE_DIR`，輸出到 `dist/`）：

```bash
Scripts/build_mlc_xcframeworks.sh
```

## macOS（Mac Catalyst）建置

使用預設腳本建置 Mac Catalyst（My Mac）：

```bash
./buildMacOS.sh TARGET=catalyst
```

## 常見限制

- 需要 WebGPU；若裝置/系統不支援，popup 會提示無法載入模型。
- Safari extension 使用 `safari-web-extension://` scheme；專案已在 vendor 的 `webllm/webllm.js` 針對非 http(s) URL 做相容處理。
- 模型/wasm assets 在 `Shared (Extension)/Resources/webllm-assets/`（gitignored），需先執行下載腳本。
- 模擬器不代表真機行為（WebGPU / MLCSwift 可能不可用）；建議以真機驗證。

## License

This project is licensed under the PolyForm Noncommercial License 1.0.0. See `LICENSE`.
