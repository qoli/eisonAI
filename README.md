# EisonAI

EisonAI 是一個 iOS/iPadOS 的 Safari Web Extension + App，目標是把「結構」變成可見的閱讀入口。你不必照著作者的線性敘事走，先看到重點與結構，再決定要深入哪一段。

Safari popup 內使用 **WebLLM（WebGPU + WebWorker）** 本機推理 `Qwen3-0.6B`；App 端則使用 **MLCSwift**（以及可選的 Apple Intelligence）做摘要與長文處理。

本專案採用 **bundled assets** 策略：模型與 wasm 會被打包進 extension bundle，popup 只讀取本地資源，不做 runtime 下載，也不依賴 iOS extension 的持久儲存。

![EisonAI Screenshot](https://raw.githubusercontent.com/qoli/eisonAI/refs/heads/main/assets/iPhone-Medata-Preview.jpg)

## eisonAI 2.0 is a complete rewrite.

https://youtu.be/B-NtdpZH9_o

## App Store

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

## License

This project is licensed under the PolyForm Noncommercial License 1.0.0. See `LICENSE`.
