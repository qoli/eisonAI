# Repository Guidelines

## Project Structure & Module Organization
- `iOS (App)/` holds the SwiftUI app code (`Features/`, `Shared/`, `Config/`, `App/`).
- `Shared (Extension)/Resources/` contains Safari extension assets: `manifest.json`, `content.js`, and the `webllm/` directory that now hosts the Apple Intelligence/BYOK popup UI and tokenizer bundles.
- `Shared (Extension)/SafariWebExtensionHandler.swift` handles extension/native settings bridge.
- `Shared (App)/Assets.xcassets` holds shared images; `Docs/` and `Scripts/` contain guides and tooling; `assets/` is for marketing images.
- `eisonAI.xcodeproj` is the Xcode entry point.

## Build, Test, and Development Commands
- `open eisonAI.xcodeproj` builds and runs the iOS/iPadOS app + Safari extension in Xcode.
- `xcodebuild -scheme 'eisonAI-Sim' -project eisonAI.xcodeproj -destination 'generic/platform=iOS Simulator' build` validates the app without a device.

## Coding Style & Naming Conventions
- Swift uses 4-space indentation; SwiftUI views follow `FeatureNameView`/`FeatureNameViewModel` naming.
- Extension JavaScript uses 2-space indentation; file names are descriptive (`popup.js`, `contentReadability.js`).
- Keep constants uppercase with underscores (for example, `MODEL_ID`, `WASM_FILE`).
- Prefer small, single-purpose files under `Features/<FeatureName>/`.

## Testing Guidelines
- `eisonAITests` contains XCTest coverage for routing and long-document helpers.
- Validate Apple Intelligence generation on an eligible real device; simulator tests only prove routing and compilation.

## Commit & Pull Request Guidelines
- Commits follow Conventional Commits with a scope; emoji prefixes are common. Example: `✨ feat(library): 新增收藏功能`.
- Common types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, and `build` (seen in history).
- PRs should include a clear description, linked issues, and screenshots for UI/popup changes. Update `Docs/` when setup or behavior changes.

## Security & Configuration Notes
- Extension CSP and entry points live in `Shared (Extension)/Resources/manifest.json`; keep them aligned with the popup’s current Apple Intelligence/BYOK behavior.
