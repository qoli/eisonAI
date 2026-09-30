# EisonAI

[![iOS 18+](https://img.shields.io/badge/iOS-18%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-PolyForm%20Noncommercial-green.svg)](LICENSE)

[English README](README.md)

<p align="center">
  <img src="https://raw.githubusercontent.com/qoli/eisonAI/refs/heads/main/assets/iPhone-Medata-Preview.jpg" alt="EisonAI 截圖" width="600">
</p>

**EisonAI** 是一個 iOS / iPadOS 的 Safari Web Extension + App，目標是把「結構」變成閱讀的入口。你不必先照著作者的線性敘事走，而是先看到關鍵點與關係，再決定要往哪裡深入。

專案目前已經整併為一套基於 **AnyLanguageModel** 的推理架構：

- **Safari 彈出視窗** 只使用 **Apple Intelligence** 或 **BYOK**
- **App 端** 同樣只使用 **Apple Intelligence** 或 **BYOK**
- 2.12 已移除可下載的本地模型 runtime 與模型管理功能

---

## 📥 App Store 下載

<a href="https://apps.apple.com/us/app/eison-ai/id6484502399" target="_blank">
  <img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/zh-tw?size=250x83&releaseDate=1716336000" alt="Download on the App Store" style="width: 200px; height: 66px;">
</a>

---

## 🌟 產品概念

- **Cognitive Index™（認知索引）**：讓結構先於內容被看見，降低閱讀時的定位成本
- **Read less linearly（非線性閱讀）**：閱讀不必受限於敘事順序
- **Think more deliberately（更專注思考）**：把注意力留給判斷與理解，而不是維持上下文
- **Make structure visible（結構可見）**：先掌握關係與重點，再選擇深入路徑

## 🚀 功能概覽

- **Safari Extension**：在 Safari 內直接生成摘要與結構化重點，無需離開瀏覽器
- **統一推理路由**：在 Apple Intelligence 與 BYOK 之間切換，不再維護可下載的本地 runtime
- **BYOK Providers**：可設定自己的 OpenAI-compatible、Anthropic、Gemini 或 Ollama 端點與模型
- **Cognitive Index™**：以結構化輸出呈現關鍵點，協助快速定位「意義生成」的區段
- **長文件支援**：以 Apple Intelligence 分段處理長文，並支援 BYOK overflow 路由
- **CloudKit 同步**：跨裝置同步 Library
- **Library & Tags**：收藏、標籤化與檢索已處理內容
- **語言自由切換**：可隨時調整模型輸出語言
- **開源透明**：隱私與執行行為可檢查

---

## 📺 媒體與展示

### eisonAI 2.0 - 上手體驗
- [小紅書影片](http://xhslink.com/o/69q4KGNdyG)
- [YouTube Shorts](https://youtube.com/shorts/T5yg5KZyOiQ)

### eisonAI 2.0 - 認知索引的故事
- [小紅書影片](http://xhslink.com/o/14SnPwbEUSs)
- [YouTube 完整影片](https://youtu.be/B-NtdpZH9_o)

---

## 🧠 eisonAI 是什麼？

想像一下：你在看書、看網頁、看資料時，常常會遇到這些情況：

> 「我剛剛看到那個重點放哪裡了？」  
> 「這個東西我明明存過，但忘記在哪裡。」  
> 「腦中有很多想法，可是一寫就亂。」

**EisonAI** 想解決的，就是這種在閱讀、記錄、回找之間反覆打斷思路的成本。

### 什麼是 Cognitive Index™（認知索引）？

核心概念其實很簡單：

> **不是只記住內容，而是記住這個東西是拿來做什麼的。**

例如：
- 不只是存下一篇文章
- 而是知道它是：
- 靈感
- 背景資料
- 之後要引用的材料

它更像圖書館的分類與檢索邏輯，而不是把內容一股腦地堆在一起。

### 核心目標：保護心流

EisonAI 想維持的是這個循環：

1. 你看到值得留下來的東西
2. 你把它交給 eisonAI
3. 你繼續思考，不被整理動作打斷
4. 之後真的需要時，可以找得回來

重點不是多一個筆記工具，而是減少整理行為對思考的干擾。

---

## 🛠 系統需求

- **作業系統**：iOS / iPadOS 18.0+
- **Safari extension target**：iPhone / iPad 實機
- **Apple Intelligence 路徑**：需要受支援裝置，且 app target 可用目前的 Foundation Models runtime

## 🔧 開發與建置

1. clone 本 repo
2. 把 `AnyLanguageModel` clone 到與本 repo 同層的目錄

目錄結構範例：

```text
Github/
  eisonAI/
  AnyLanguageModel/
```

Xcode 專案會直接連結這個 sibling checkout，而且不啟用任何本地模型 trait。

3. 用 Xcode 開啟 `eisonAI.xcodeproj`
4. 按需求選擇 scheme：
- `iOS`：實機 build，包含 Safari extension
- `eisonAI-Sim`：模擬器專用 app build

常用指令：

```bash
open eisonAI.xcodeproj
```

```bash
xcodebuild -scheme 'eisonAI-Sim' -project eisonAI.xcodeproj -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

```bash
xcodebuild -scheme 'iOS' -project eisonAI.xcodeproj -configuration Debug -destination 'generic/platform=iOS' build
```

Xcode 自動化輔助腳本：

```bash
Scripts/run_xcode.sh
Scripts/export_xcode_console.sh
```

完整用法、前提條件與限制請見 [Docs/xcode-automation.md](Docs/xcode-automation.md)。

## 🧩 執行時說明

- Safari extension 已移除 WebLLM / WebGPU 的本地執行路徑
- Popup 與 App 現在都透過 native bridge 使用 **Apple Intelligence** 或 **BYOK**
- eisonAI 2.x 不再包含可下載的 MLX 模型、catalog 或背景下載生命週期

## 📄 授權協議

本專案採用 **PolyForm Noncommercial License 1.0.0** 授權。詳情請參閱 `LICENSE`。
