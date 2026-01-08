# EisonAI

[![iOS 18+](https://img.shields.io/badge/iOS-18%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-PolyForm%20Noncommercial-green.svg)](LICENSE)

[中文版 README](README_zh.md)

<p align="center">
  <img src="https://raw.githubusercontent.com/qoli/eisonAI/refs/heads/main/assets/iPhone-Medata-Preview.jpg" alt="EisonAI Screenshot" width="600">
</p>

**EisonAI** is an macOS / iOS / iPadOS Safari Web Extension + App that turns “structure” into a visible entry point for reading. You don’t have to follow the author’s linear narrative—see the key points and structure first, then decide where to dive in.

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

## 🧠 What is eisonAI?

Imagine this: You are reading a book, a webpage, or some documents, and you often find yourself thinking:

> "Wait, where did I see that key point just now?"  
> "I know I've seen this before, but I forgot where I saved it."  
> "I have so many ideas in my head, but they get messy as soon as I try to write them down."

**eisonAI** is the assistant that helps you remember, organize, and retrieve these things.

### What is Cognitive Index™?

The name sounds complex, but the meaning is simple:

> **It's not just about remembering the "content", but remembering "what this is used for".**

For example:
- Not just saving an article.
- But knowing whether:
    - It is an "inspiration".
    - It is "background material".
    - Or it is a "citation for later use".

It's like: **A library doesn't just pile books up randomly; it knows where the fiction, reference, and comic sections are.**  
eisonAI is here to help you build this "library in your brain".

### Core Goal: Protecting Your Flow

What is Flow? It means:

> **You are thinking smoothly without constant interruptions.**

What eisonAI wants to do:
1. You see something good → Throw it to eisonAI.
2. You keep thinking → No need to worry about categorizing or organizing.
3. You need it later → Find it instantly.

> 🛟 It acts like an "assistant that tidies up for you", allowing your brain to focus on the important thinking tasks.

---

## 🛠 System Requirements

- **OS**: iOS / iPadOS 18.0+
- **Apple Intelligence** (Optional): iOS 18.1+ and enabled device
- **Device**: Recommended iPhone 14 Pro / iPad Pro (M1) or newer for best inference performance.

## 📄 License

This project is licensed under the **PolyForm Noncommercial License 1.0.0**. See `LICENSE` for more details.