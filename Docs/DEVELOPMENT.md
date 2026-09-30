# Developer Guide

## Setup

1. Clone `eisonAI` and `AnyLanguageModel` as sibling directories.
2. Open `eisonAI.xcodeproj`.
3. Use `eisonAI-Sim` for simulator compilation and `iOS` for device builds with the Safari extension.

```text
Github/
  eisonAI/
  AnyLanguageModel/
```

The app and extension use Apple Intelligence or BYOK. No model assets, downloadable local runtime, or model packaging step is required.

## Validation

```bash
xcodebuild -scheme 'eisonAI-Sim' -project eisonAI.xcodeproj \
  -destination 'generic/platform=iOS Simulator' build
```

```bash
xcodebuild -scheme 'eisonAITests' -project eisonAI.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Use an eligible physical device to verify Apple Intelligence generation. Use a controlled provider endpoint to verify BYOK request and streaming behavior.

## Main Surfaces

- `Shared (Extension)/Resources/webllm/`: historical directory name for the active popup UI, Markdown renderer, and tokenizer bundles.
- `Shared (Extension)/SafariWebExtensionHandler.swift`: native configuration and streaming bridge.
- `iOS (App)/Shared/Generation/`: app routing and model client.
- `iOS (App)/Features/Settings/AIModelsSettingsView.swift`: backend and BYOK settings.
