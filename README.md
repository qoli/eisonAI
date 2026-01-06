# EisonAI

[中文版 README](README_zh.md)

EisonAI is an iOS/iPadOS Safari Web Extension + App that turns “structure” into a visible entry point for reading. You don’t have to follow the author’s linear narrative—see the key points and structure first, then decide where to dive in.

The Safari popup uses **WebLLM (WebGPU + WebWorker)** for on-device inference with `Qwen3-0.6B`. The app uses **MLCSwift** (and optional Apple Intelligence) for summaries and long-document processing.

This project adopts a **bundled assets** strategy: models and wasm are packaged into the extension bundle. The popup reads only local resources, does no runtime downloads, and does not rely on persistent storage inside the iOS extension.

![EisonAI Screenshot](https://raw.githubusercontent.com/qoli/eisonAI/refs/heads/main/assets/iPhone-Medata-Preview.jpg)

## eisonAI 2.0 is a complete rewrite.

https://youtu.be/B-NtdpZH9_o

## App Store

### App Store

https://apps.apple.com/us/app/eison-ai/id6484502399
( app store 正在審核，所以下載的版本是 1.0 版本)

## Product Concept

- **Cognitive Index™**: Make structure visible before content to reduce the cost of finding where meaning is created.
- **Read less linearly**: Reading doesn’t have to follow narrative order.
- **Think more deliberately**: Reserve attention for judgment and understanding, not for maintaining context.
- **Make structure visible**: See relationships and key points first, then choose your path deeper.

## Feature Overview

- **Safari Extension**: Generate summaries and structured highlights inside Safari without leaving the browser.
- **Cognitive Index™**: Structured output surfaces key points to help quickly locate meaning-dense sections.
- **Long-Document**: Chunked processing for long content, supporting roughly 15,000-token scale.
- **Local-First**: On-device inference and storage for privacy.
- **CloudKit Sync**: Sync your Library across devices.
- **Library & Tags**: Save, tag, and search.
- **Language of Thought**: Choose the language the model “thinks and outputs” in, adjustable anytime.
- **Open Source**: Auditable privacy and behavior.

## System Requirements

- iOS / iPadOS 18+
- Apple Intelligence (optional): iOS 26+ and enabled
- Recommended: iPhone 14 or newer for the best experience

## License

This project is licensed under the PolyForm Noncommercial License 1.0.0. See `LICENSE`.
