# EisonAI

[![iOS 18+](https://img.shields.io/badge/iOS-18%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-PolyForm%20Noncommercial-green.svg)](LICENSE)

[English README](README.md)

<p align="center">
  <img src="https://raw.githubusercontent.com/qoli/eisonAI/refs/heads/main/assets/iPhone-Medata-Preview.jpg" alt="EisonAI 截圖" width="600">
</p>

**EisonAI** 是一個 iOS/iPadOS 的 Safari Web Extension + App，目標是把「結構」變成可見的閱讀入口。你不必照著作者的線性敘事走，透過先看到重點與結構，再決定要深入哪一段。

Safari 彈出視窗（Popup）內使用 **WebLLM（WebGPU + WebWorker）** 進行本機推理 `Qwen3-0.6B`；App 端則使用 **MLCSwift**（以及可選的 Apple Intelligence）進行摘要與長文處理。

本專案採用 **bundled assets** 策略：模型與 WASM 檔案會被打包進 Extension Bundle。Popup 僅讀取本地資源，不進行執行時（Runtime）下載，也不依賴 iOS Extension 的持久性儲存。

---

## 📥 App Store 下載

<a href="https://apps.apple.com/us/app/eison-ai/id6484502399" target="_blank">
  <img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/zh-tw?size=250x83&releaseDate=1716336000" alt="Download on the App Store" style="width: 200px; height: 66px;">
</a>

---

## 🌟 產品概念

- **Cognitive Index™（認知索引）**：讓結構先於內容被看見，大幅降低閱讀時的定位成本。
- **Read less linearly（非線性閱讀）**：閱讀不必受限於敘事順序。
- **Think more deliberately（深思熟慮）**：將注意力保留給判斷與理解，而非維持上下文。
- **Make structure visible（結構可見化）**：先掌握關係與重點，再選擇深入的路徑。

## 🚀 功能概覽

- **Safari Extension**：在 Safari 內直接生成摘要與結構化重點，無需離開瀏覽器。
- **Cognitive Index™**：以結構化輸出呈現關鍵點，協助快速定位「意義生成」的區段。
- **長文件支援**：長文分段處理技術，支援約 15,000 tokens 級別的內容。
- **隱私優先（Local-First）**：完全在裝置端進行推理與儲存。
- **CloudKit 同步**：跨裝置無縫同步您的圖書館（Library）。
- **圖書館與標籤**：收藏、標籤化管理與快速檢索。
- **語言自由切換**：可隨時調整模型「思考與輸出」的語言。
- **開源透明**：隱私行為可供審查。

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

想像一下：你在看書、看網頁、看資料的時候，是不是常常會遇到這種情況：

> 「咦？我剛剛看到那個重點放哪裡了？」  
> 「這個東西我明明看過，但忘記存在哪裡了。」  
> 「我腦袋裡有很多想法，但一寫就亂掉。」

**eisonAI** 就是來幫你記住東西、整理東西、找回東西的小幫手。

### 什麼是 Cognitive Index™（認知索引）？

這個名字聽起來很難，其實意思很簡單：

> **不是只記住「內容」，而是記住「這個東西是幹嘛用的」。**

舉例來說：
- 不是只存下一篇文章。
- 而是明確知道：
    - 它是「靈感」。
    - 還是「背景資料」。
    - 或是「之後要用的引用」。

這就像：**圖書館不是把書亂堆，而是清楚劃分小說區、工具書區、漫畫區在哪裡。**  
eisonAI 就是在幫您建立這個「腦內圖書館」。

### eisonAI 的核心目標：保護你的心流

心流（Flow）是什麼？就是：

> **你正在順暢地思考，而不被瑣事打斷。**

eisonAI 致力於：
1. **捕捉**：看到好東西 → 直接丟給 eisonAI。
2. **無感**：繼續思考 → 無需煩惱分類與整理。
3. **回溯**：之後需要時 → 一下就能找到。

> 🛟 它就像一個「幫你收納的助理」，讓您的大腦能專注在最重要的思考任務上。

---

## 🛠 系統需求

- **作業系統**：iOS / iPadOS 18.0+
- **Apple Intelligence**（選用）：iOS 18.1+ 且裝置已啟用該功能
- **建議裝置**：iPhone 14 Pro / iPad Pro (M1) 或更新機型，以獲得最佳推理效能。

## 📄 授權協議

本專案採用 **PolyForm Noncommercial License 1.0.0** 授權。詳情請參閱 `LICENSE` 檔案。