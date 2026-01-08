# EisonAI

[![iOS 18+](https://img.shields.io/badge/iOS-18%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-PolyForm%20Noncommercial-green.svg)](LICENSE)

[中文版 README](README_zh.md)

<p align="center">
  <img src="https://raw.githubusercontent.com/qoli/eisonAI/refs/heads/main/assets/iPhone-Medata-Preview.jpg" alt="EisonAI Screenshot" width="600">
</p>

**EisonAI** is an iOS/iPadOS Safari Web Extension + App that turns “structure” into a visible entry point for reading. You don’t have to follow the author’s linear narrative—see the key points and structure first, then decide where to dive in.

The Safari popup uses **WebLLM (WebGPU + WebWorker)** for on-device inference with `Qwen3-0.6B`. The app uses **MLCSwift** (and optional Apple Intelligence) for summaries and long-document processing.

This project adopts a **bundled assets** strategy: models and wasm are packaged into the extension bundle. The popup reads only local resources, does no runtime downloads, and does not rely on persistent storage inside the iOS extension.

---

## 📥 App Store

<a href="https://apps.apple.com/us/app/eison-ai/id6484502399" target="_blank">
  <img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83&releaseDate=1716336000" alt="Download on the App Store" style="width: 200px; height: 66px;">
</a>

---

## 🌟 Product Concept

- **Cognitive Index™**: Make structure visible *before* content to reduce the cost of finding where meaning is created.
- **Read less linearly**: Reading doesn’t have to follow narrative order.
- **Think more deliberately**: Reserve attention for judgment and understanding, not for maintaining context.
- **Make structure visible**: See relationships and key points first, then choose your path deeper.

## 🚀 Feature Overview

- **Safari Extension**: Generate summaries and structured highlights inside Safari without leaving the browser.
- **Cognitive Index™**: Structured output surfaces key points to help quickly locate meaning-dense sections.
- **Long-Document Support**: Chunked processing for long content, supporting roughly 15,000-token scale.
- **Local-First Privacy**: On-device inference and storage.
- **CloudKit Sync**: Seamlessly sync your Library across devices.
- **Library & Tags**: Save, tag, and search your processed articles.
- **Language of Thought**: Choose the language the model “thinks and outputs” in, adjustable anytime.
- **Open Source**: Auditable privacy and behavior.

---

## 📺 Media & Demos

### eisonAI 2.0 - Onboarding Experience
- [Little Red Book (Xiaohongshu)](http://xhslink.com/o/69q4KGNdyG)
- [YouTube Shorts](https://youtube.com/shorts/T5yg5KZyOiQ)

### eisonAI 2.0 - Story of Cognitive Index
- [Little Red Book (Xiaohongshu)](http://xhslink.com/o/14SnPwbEUSs)
- [YouTube](https://youtu.be/B-NtdpZH9_o)

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

舉例：
- 不是只存一篇文章
- 而是知道：
    - 它是「靈感」
    - 還是「背景資料」
    - 還是「之後要用的引用」

這就像：**圖書館不是把書亂堆，而是知道小說區、工具書區、漫畫區在哪裡。**  
eisonAI 就是在幫你建這個「腦內圖書館」。

### eisonAI 的核心目標：保護你的心流

心流是什麼？就是：

> **你正在順順地想事情，而不是一直被打斷。**

eisonAI 想做的是：
1. 你看到好東西 → 丟給 eisonAI
2. 你繼續想 → 不用管分類、不用整理
3. 之後要用 → 一下就找得到

> 🛟 它像一個「幫你收東西的助理」，讓你的大腦可以專心想重要的事。

---

## 🛠 System Requirements

- **OS**: iOS / iPadOS 18.0+
- **Apple Intelligence** (Optional): iOS 18.1+ and enabled device
- **Device**: Recommended iPhone 14 Pro / iPad Pro (M1) or newer for best inference performance.

## 📄 License

This project is licensed under the **PolyForm Noncommercial License 1.0.0**. See `LICENSE` for more details.