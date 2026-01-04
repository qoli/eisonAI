# Gemini Context: EisonAI

## Project Overview

**EisonAI** is a sophisticated iOS/iPadOS application that functions primarily as a Safari Web Extension, integrated with a companion native App. Its core purpose is to provide "Cognitive Indexing" for web articles—summarizing and structuring content to allow non-linear reading.

**Key Technical Features:**
*   **Hybrid Architecture:** Combines a Native iOS App (SwiftUI) with a Safari Web Extension (HTML/JS/Wasm).
*   **Local AI Inference:**
    *   **Safari Extension:** Uses **WebLLM** (WebGPU + WebWorker) to run LLMs directly in the browser popup.
    *   **Native App:** Uses **MLCSwift** for on-device inference and optionally integrates with Apple Intelligence (Foundation Models).
*   **Offline-First:** Models and WASM binaries are bundled as assets within the extension, preventing runtime downloads and ensuring privacy.
*   **Sync:** Uses **CloudKit** and App Groups to synchronize libraries and settings between the Extension and the App.

## Directory Structure

*   **`iOS (App)/`**: The native host application (SwiftUI).
    *   `Features/`: Modularized feature logic (e.g., Library, History, Onboarding).
    *   `Shared/`: Shared utilities, including `MLC/` (Native LLM logic) and `CloudKit/`.
*   **`Shared (Extension)/`**: The core logic for the Safari Extension.
    *   `Resources/`: Web assets.
        *   `webllm/`: The WebLLM runtime, popup UI (`popup.html`), and worker logic.
        *   `webllm-assets/`: **CRITICAL**. Stores the actual model weights and WASM files.
    *   `SafariWebExtensionHandler.swift`: The native bridge handling communication between Safari and the App.
*   **`Scripts/`**: Build and maintenance scripts.
    *   `download_webllm_assets.py`: Downloads the required LLM models.
    *   `build_mlc_xcframeworks.sh`: Custom script to package MLC libraries.
*   **`Spec/`**: Detailed technical specifications and architectural decision records.
*   **`buildMacOS.sh`**: The primary script for building and running the app from the CLI.

## Building and Running

### Prerequisites
*   **Xcode 16+** (implied by iOS 18+ requirement).
*   **Python 3** (for asset scripts).
*   **Ruby** (for Fastlane, optional but recommended).
*   **Device:** Real iOS device or Apple Silicon Mac (for WebGPU support).

### 1. Asset Setup (First Run)
Before building, you **MUST** download the model assets. They are ignored by Git.

```bash
python3 Scripts/download_webllm_assets.py
```

### 2. Build & Run (CLI)
The project provides a unified build script `buildMacOS.sh` that wraps `xcodebuild`.

**Run on Mac Catalyst (easiest for testing):**
```bash
./buildMacOS.sh
# Defaults to TARGET=catalyst
```

**Run on iOS Simulator:**
```bash
TARGET=simulator ./buildMacOS.sh
```

**Run on "My Mac" (Designed for iPad):**
```bash
TARGET=mymac ./buildMacOS.sh
```

### 3. Build & Run (Xcode)
Open `eisonAI.xcodeproj`.
*   Select the `iOS` scheme.
*   Choose a destination (Your Mac or a connected Device).
*   **Note:** The native MLCSwift integration currently requires a real device (ARM64) and does not support the Simulator.

## Development Conventions

### Code Style
*   **Swift:** Modern Swift concurrency (`async/await`, `Actors`). MVVM-like pattern in `Features/`.
*   **JS:** Vanilla JS/ES6 modules for the extension.
*   **Formatting:** Follows standard Swift formatting.

### key Files & Configurations
*   **`iOS (App)/Config/mlc-app-config.json`**: Defines which models are available to the native app.
*   **`Shared (Extension)/Resources/webllm/popup.js`**: The entry point for the extension's UI logic.
*   **`Shared (Extension)/SafariWebExtensionHandler.swift`**: Handles "Native Messaging". If you change the message protocol, update both this file and the JS side.

### Architecture Notes
*   **App Groups:** Data sharing between the App and Extension relies on the App Group `group.com.qoli.eisonAI`.
*   **WebGPU:** The extension *requires* a WebGPU-capable environment. If testing in Safari, ensure "Develop > Feature Flags > WebGPU" is enabled (standard in recent versions).

## Common Tasks
*   **Updating Models:** Update `download_webllm_assets.py` and run it. Then update `mlc-app-config.json`.
*   **Modifying Prompt:** Check `iOS (App)/Config/default_system_prompt.txt` or the corresponding Settings feature.
