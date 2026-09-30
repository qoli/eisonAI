# Inference Backend Consolidation Around AnyLanguageModel

## Current Status

- `landed`
- eisonAI 2.x now supports Apple Intelligence and BYOK only.
- Downloadable MLX models, model catalog and management UI, background downloads, deep links, and MLX build products have been removed.
- The app and Safari extension retain `AnyLanguageModel` as their shared abstraction for Apple Intelligence and provider-backed generation.

## Decision

The supported backend model is:

- `Local`: Apple Intelligence only
- `User-provided`: BYOK
- `Abstraction layer`: AnyLanguageModel
- `Retired`: MLX, MLCSwift, MLC-LLM packaging, and WebLLM inference

The legacy stored backend value `mlx` migrates to the existing `local` selection. That explicit local selection resolves only to Apple Intelligence and fails closed when Apple Intelligence is unavailable; it never silently sends input to BYOK. No MLX execution case remains.

## Why

- Remove a large model download and cache lifecycle from the maintenance-only 2.x line.
- Eliminate machine-local MLX trait shims and legacy MLC build artifacts from the reproducible project graph.
- Keep app and extension behavior aligned around the two paths that remain strategically relevant.
- Make product, privacy, onboarding, and Settings copy accurately describe when content stays on device and when it is sent to a user-selected provider.

## Implemented Boundaries

- App routing, title generation, and long-document generation use Apple Intelligence or BYOK.
- Safari native streaming already used those same two backends and remains intact.
- Settings no longer exposes downloaded-model selection, installation, deletion, or download status.
- App lifecycle no longer starts model download recovery, notifications, or MLX debug automation.
- The Xcode project no longer enables the `MLX` package trait or references legacy MLC xcframework outputs.
- MLX-only tests, scripts, resources, and current-state setup documentation have been retired.

## Acceptance Boundary

- Simulator build and XCTest prove routing, legacy-value migration, and compile-time integration.
- Apple Intelligence generation still requires an eligible iOS 26+ device for runtime acceptance.
- BYOK runtime acceptance requires a configured provider endpoint.
- Previously downloaded model data is not deleted automatically; local-data deletion is a separate destructive migration decision.

## Historical Context

Before this decision, eisonAI had successively used WebLLM, MLCSwift/MLC-LLM, and MLX. Historical changelogs and explicitly historical flow documents may retain those names to explain earlier releases; they are not current architecture.
