# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EisonAI is a Safari browser extension that uses Large Language Models (LLMs) to summarize web page content. It's built as a native application for macOS and iOS that contains a Safari Web Extension.

- **Frontend:** The extension's UI is built with HTML, CSS, and JavaScript.
- **Backend:** The core logic is in JavaScript, split into content scripts, background scripts, and popup/settings scripts.
- **Native Wrapper:** The Xcode project (`eisonAI.xcodeproj`) wraps the web extension for distribution on the App Store.

## Key Files and Directories

- `Shared (App)/`: Contains the core web extension assets and JavaScript files.
  - `Base.lproj/Main.html`: The main HTML file for the popup interface.
  - `Resources/`: Holds JavaScript (`Script.js`) and CSS (`Style.css`).
  - `ViewController.swift`: The main view controller for the native app wrapper.
- `macOS (App)/` & `iOS (App)/`: Platform-specific code and configurations.
- `eisonAI.xcodeproj/`: The Xcode project file.

## Common Development Tasks

### Running the Project

To develop and run the project, you need to use Xcode.

1.  **Install dependencies:**
    ```bash
    bundle install
    ```
2.  **Open the project in Xcode:**
    ```bash
    open eisonAI.xcodeproj
    ```
3.  **Run the app:**
    - Select the desired target (e.g., "eisonAI (macOS)") and a simulator or connected device.
    - Click the "Run" button in Xcode.

### Modifying the Web Extension

- The primary logic for the Safari extension is located in `Shared (App)/Resources/`.
- `Script.js` likely contains the main application logic (content extraction, API calls, UI updates).
- `Style.css` contains the styling for the popup.
- After making changes to the JavaScript or CSS files, you will need to re-run the application from Xcode to see the changes in Safari.
