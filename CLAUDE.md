# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EisonAI is a Safari browser extension that uses Large Language Models (LLMs) to summarize web page content. It's built as a native macOS and iOS application that wraps a Safari Web Extension.

## Architecture

### Safari Extension Components

1. **Content Scripts** (`Shared (Extension)/Resources/`)
   - `content.js`: Injected into web pages, coordinates content extraction
   - `contentReadability.js`: Mozilla Readability library for extracting article content
   - `contentGPT.js`: Handles LLM API communication (OpenAI-compatible and Google Gemini)
   - `contentMarked.js`: Markdown rendering library

2. **Background Script** (`background.js`)
   - Message broker between popup and content scripts
   - Maintains persistent communication channels

3. **Popup Interface** (`popup.js`, `popup.html`, `popup.css`)
   - Main user interface for summarization
   - Handles chat interactions with LLM
   - Manages cached summaries
   - Auto-triggers summarization when no cache exists

4. **Settings Page** (`settings.js`, `settings.html`)
   - API configuration (URL, key, model)
   - System and user prompt customization
   - API connection testing
   - Display mode configuration

### Native App Wrapper

- **Xcode Project**: `eisonAI.xcodeproj`
- **Targets**: iOS, macOS, eisonAI Extension (iOS), eisonAI Extension (macOS)
- **Main App**: `Shared (App)/ViewController.swift` - native wrapper UI
- **Extension Handler**: `Shared (Extension)/SafariWebExtensionHandler.swift`

## Development Commands

### Build and Run

```bash
# Install Ruby dependencies for deployment
bundle install

# Open in Xcode for development
open eisonAI.xcodeproj

# Build for macOS (via fastlane)
bundle exec fastlane mac

# Deploy to TestFlight (both iOS and macOS)
bundle exec fastlane all

# Increment app version (1.0 -> 1.1)
bundle exec fastlane bump_version
```

### Version Management

The project uses automated build number management for pre-release testing:

- **Build Number**: Automatically incremented on each test release via `increment_build_number`
- **Version Number**: Remains fixed during pre-release phase (currently 1.0)
- **Unified Versioning**: iOS and macOS share the same version and build numbers
- **Changelog**: Automatically generated for test releases

Commands:
- `fastlane all`: Increment build number + deploy test version
- `fastlane bump_version`: Increment version number (only when ready for official release)

Version information is stored in the Xcode project's build settings:
- `CURRENT_PROJECT_VERSION`: Build number (auto-incremented: 1, 2, 3...)
- `MARKETING_VERSION`: App version (fixed at 1.0 for pre-release)

### Xcode Build

In Xcode:
1. Select target: "iOS" or "macOS"
2. Select destination (simulator or device)
3. Click Run (⌘R)

To test the Safari extension:
1. Build and run the app
2. Open Safari → Settings → Extensions
3. Enable "eisonAI"

## Key Development Patterns

### Message Passing Architecture

All communication between extension components uses browser.runtime messages:
- Popup ↔ Background ↔ Content Script
- Commands flow through background.js as the message broker

### API Integration

The extension supports two API types:
- OpenAI-compatible endpoints (e.g., `https://example.com/v1`)
- Google Gemini API

API configuration is stored in `browser.storage.local` with keys: APIURL, APIKEY, APIMODEL

### Content Extraction

Uses Mozilla's Readability.js to:
1. Parse DOM and extract article content
2. Remove ads and navigation elements
3. Return clean text for summarization

### Caching Strategy

Summaries are cached locally by URL to avoid redundant API calls. Cache is checked on popup open.

## Platform-Specific Considerations

### macOS vs iOS

The extension detects platform via user agent and applies appropriate CSS:
- macOS: Desktop-optimized layout
- iOS: Touch-friendly interface with larger tap targets

### Safari Extension Manifest

Located at `Shared (Extension)/Resources/manifest.json`
- Uses Manifest V3 format
- Requires permissions: activeTab, nativeMessaging, storage
- Content scripts injected on all URLs

## Security Notes

- API keys stored in browser.storage.local (device-only)
- HTTPS required for API endpoints
- Content Security Policy enforced via manifest