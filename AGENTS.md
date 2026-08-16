# Repository Guidelines

## Project Structure & Module Organization
- `iOS (App)/` holds the SwiftUI app code (`Features/`, `Shared/`, `Config/`, `App/`).
- `Shared (Extension)/Resources/` contains Safari extension assets: `manifest.json`, `content.js`, and `webllm/` popup HTML/JS/worker files.
- `Shared (Extension)/Resources/webllm-assets/` stores downloaded model/wasm files (gitignored).
- `Shared (Extension)/SafariWebExtensionHandler.swift` handles extension/native settings bridge.
- `Shared (App)/Assets.xcassets` holds shared images; `Docs/` and `Scripts/` contain guides and tooling; `assets/` is for marketing images.
- `eisonAI.xcodeproj` is the Xcode entry point.

## Build, Test, and Development Commands
- `python3 Scripts/download_webllm_assets.py` downloads model/wasm files into `Shared (Extension)/Resources/webllm-assets/` (required).
- `open eisonAI.xcodeproj` builds and runs the iOS/iPadOS app + Safari extension in Xcode.
- `Scripts/build_mlc_xcframeworks.sh` rebuilds MLC xcframeworks (expects `MLC_LLM_SOURCE_DIR`, outputs to `dist/`).

## Coding Style & Naming Conventions
- Swift uses 4-space indentation; SwiftUI views follow `FeatureNameView`/`FeatureNameViewModel` naming.
- Extension JavaScript uses 2-space indentation; file names are descriptive (`popup.js`, `contentReadability.js`).
- Keep constants uppercase with underscores (for example, `MODEL_ID`, `WASM_FILE`).
- Prefer small, single-purpose files under `Features/<FeatureName>/`.

## Testing Guidelines
- No automated test targets were found. Validate changes manually in Xcode and on real iOS/iPadOS devices (WebGPU behavior differs from the simulator).
- If adding tests, use XCTest with `*Tests.swift` and run via Xcode’s Test action or `xcodebuild test`.

## Commit & Pull Request Guidelines
- Commits follow Conventional Commits with a scope; emoji prefixes are common. Example: `✨ feat(library): 新增收藏功能`.
- Common types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, and `build` (seen in history).
- PRs should include a clear description, linked issues, and screenshots for UI/popup changes. Update `Docs/` when setup or behavior changes.

## Security & Configuration Notes
- Large assets in `Shared (Extension)/Resources/webllm-assets/` are intentionally gitignored; use the download script instead of committing binaries.
- Extension CSP and entry points live in `Shared (Extension)/Resources/manifest.json`; keep WebGPU/wasm settings aligned with WebLLM updates.
