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

<!-- threadbridge:runtime:start -->
## threadBridge Runtime Appendix

This managed block is appended by threadBridge to a real project workspace `AGENTS.md`.

### Runtime Model

- The current working directory is the real bound workspace, not a projected copy.
- Preserve this workspace's own conventions and instructions. This appendix adds bot/runtime behavior; it does not replace project-local rules.
- threadBridge tracks Telegram-thread metadata outside the workspace under its own bot-local runtime data root. In debug builds this defaults to repo-local `data/`; in release builds it defaults to the platform local app-data directory. That bot-local state is not the source of truth for project files.
- Use the current Codex thread context as the primary continuity source. Do not rebuild long transcript replays unless a workflow explicitly requires it.

### Runtime Surface

- threadBridge installs wrapper commands under:
  - `./.threadbridge/bin/build_prompt_config`
  - `./.threadbridge/bin/generate_image`
  - `./.threadbridge/bin/hcodex`
  - `./.threadbridge/bin/send_telegram_media`
- threadBridge installs local shell/runtime sync files under:
  - `./.threadbridge/state/workspace-config.json`
  - `./.threadbridge/state/app-server/current.json`
  - `./.threadbridge/state/runtime-observer/current.json`
  - `./.threadbridge/state/runtime-observer/events.jsonl`
- threadBridge request/result files live under:
  - `./.threadbridge/tool_requests/`
  - `./.threadbridge/tool_results/`
- Keep these wrapper names and paths stable.
- `./.threadbridge/state/runtime-observer/*` is a workspace-local observation and activity surface.
- Treat desktop owner heartbeat and management/runtime protocol views as the canonical runtime-health authority, not `runtime-observer/*` by itself.

### Local Codex TUI

- Run `./.threadbridge/bin/hcodex` for the managed local TUI path in this workspace.
- `hcodex` resolves the shared workspace daemon from `./.threadbridge/state/app-server/current.json` and launches `codex --remote ...`.
- `hcodex` also reads `./.threadbridge/state/workspace-config.json` so local launch and resume use the workspace execution mode.
- With no extra args, `hcodex` starts a fresh local TUI session for this workspace.
- Fresh `hcodex` sessions project mirror activity from the existing live daemon stream; standalone observer attach is reserved for explicit resume flows.
- Use `hcodex resume <session-id>` when you explicitly want to continue an existing Codex session.

### `./.threadbridge/bin/build_prompt_config`

- Use this command when the current thread needs to build or refresh prompt artifacts in this workspace.
- Before running it, decide whether the current Codex thread already has enough information.
- If information is still missing, ask follow-up questions and do not run the tool.
- If information is sufficient:
  1. Write `./.threadbridge/tool_requests/build_prompt_config.request.json`.
  2. Run `./.threadbridge/bin/build_prompt_config`.
  3. Inspect `./.threadbridge/tool_results/build_prompt_config.result.json`.

The request file must look like this:

```json
{
  "concept": {
    "concept_id": "c_001",
    "title": "Short concept title",
    "summary": "One concise paragraph for the current thread brief.",
    "keywords": ["keyword 1", "keyword 2"],
    "style_notes": ["style note 1", "style note 2"],
    "constraints": ["constraint 1", "constraint 2"],
    "source": "buildpromptconfig",
    "updated_at": "2026-03-16T00:00:00.000Z"
  },
  "prompt": {
    "concept_id": "c_001",
    "variant_id": "primary",
    "provider": "nanobanana",
    "mode": "text_to_image",
    "instruction": "A complete final instruction for Nanobanana.",
    "image_inputs": [],
    "generation_config": {
      "response_modalities": ["IMAGE"],
      "image_config": {
        "aspect_ratio": "1:1",
        "image_size": "1K"
      }
    },
    "safety_settings": [
      {
        "category": "HARM_CATEGORY_HATE_SPEECH",
        "threshold": "BLOCK_MEDIUM_AND_ABOVE"
      }
    ],
    "metadata": {
      "source": "buildpromptconfig",
      "timestamp": "2026-03-16T00:00:00.000Z",
      "notes": ["Short implementation note."]
    }
  }
}
```

### Prompt Guide For `instruction`

- Build the final Nanobanana `instruction` from the current session and any workspace-local images.
- For text-to-image requests, structure the instruction around:
  - `Subject + Action + Setting + Style + Composition + Lighting + Key details + Constraints`
- For image-edit requests, structure the instruction around:
  - `Keep + Change + How/Style + Constraints`
- The `instruction` must be a final provider-ready prompt, not a question to the user.
- Do not invent diffusion-style fields or hidden model settings.
- Only reference source images that actually exist in this workspace.

### `./.threadbridge/bin/generate_image`

- Use this command when the current thread needs to generate images from workspace artifacts.
- By default, use the latest prompt config in `prompts/` unless the session clearly requires another one.
- If the workspace still lacks a usable prompt config or required image inputs, ask follow-up questions and do not run the tool.
- After a successful run, inspect `./.threadbridge/tool_results/generate_image.result.json`.

### `./.threadbridge/bin/send_telegram_media`

- Use this command only when sending text, images, or files back into the current Telegram thread would materially help the user.
- This capability is optional. Ordinary chat replies still work without it.
- Before running it:
  1. Write `./.threadbridge/tool_requests/send_telegram_media.request.json`.
  2. Keep all referenced files inside the current workspace.
  3. Prefer concise captions and user-facing filenames that already exist on disk.
- Each item may include an optional `surface` field. The default is `content`.
- Telegram delivery does upload-size preflight before sending queued files.
- Oversized `photo` items may fall back to `document`; oversized files may fall back to a warning instead of a Telegram upload.
- After a successful run, inspect `./.threadbridge/tool_results/send_telegram_media.result.json`.
- The bot runtime will deliver queued items from the workspace outbox after the Codex turn completes.

The request file must look like this:

```json
{
  "items": [
    {
      "type": "text",
      "text": "Short user-facing message.",
      "surface": "content"
    },
    {
      "type": "photo",
      "path": "images/generated/005/example.png",
      "caption": "Optional caption."
    },
    {
      "type": "document",
      "path": "prompts/005_primary.json",
      "caption": "Optional caption."
    }
  ]
}
```

### Artifact Boundaries

- threadBridge-owned runtime surface inside this workspace:
  - `.threadbridge/bin/`
  - `.threadbridge/state/workspace-config.json`
  - `.threadbridge/state/app-server/`
  - `.threadbridge/state/runtime-observer/`
  - `.threadbridge/tool_requests/`
  - `.threadbridge/tool_results/`
- `runtime-observer/` remains a workspace-local observability/activity lane; it is not the machine-level owner authority.
- Workspace/project artifacts produced by the tools:
  - `concept.json`
  - `prompts/*.json`
  - `images/generated/`

### Implementation Discipline

- Keep ordinary chat behavior grounded in the current Codex thread and the actual artifacts on disk.
- Do not overwrite or redefine the rest of the workspace `AGENTS.md`.
- Do not reintroduce diffusion-style placeholder parameters for Nanobanana configs.
<!-- threadbridge:runtime:end -->
