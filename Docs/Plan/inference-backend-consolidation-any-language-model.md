# Inference Backend Consolidation Around AnyLanguageModel

## Current Status

- `draft`
- The codebase still contains multiple local inference paths: WebLLM in the Safari popup, MLCSwift in the app, and Apple Intelligence where available.
- The extension native bridge already uses `AnyLanguageModel`-related capabilities for Apple Intelligence and BYOK integration.
- The app settings flow already includes BYOK verification and request paths built around `AnyLanguageModelClient`.
- MLC packaging, model assets, demo views, and related docs are still part of the repository and current product story.

## Problem / Background

The current inference stack is broad but operationally expensive:

- MLC introduces packaging, xcframework, model asset, and device validation complexity.
- WebLLM and MLC create parallel local-model paths with different runtime constraints.
- Product positioning is shifting toward a broader assistant rather than a local-model showcase.

### Reported Runtime Risk

- 2026-04-27: User suspects the eisonAI app may automatically start the MLX/MLC runtime while idle, causing unnecessary heat or battery drain.
- This is not yet confirmed. It should be treated as an observability-first investigation item before any runtime removal or lazy-loading fix is proposed.
- The first diagnostic pass should verify whether local runtime initialization happens during app launch, settings render, demo view discovery, background resume, or only after an explicit inference action.
- Useful signals include runtime initialization logs, Instruments energy impact, process CPU/GPU activity while idle, and call-site tracing around MLX/MLC model loading.

If the product direction becomes "local AI / information organization / learning assistant," the backend strategy may need to become simpler and more legible.

One possible simplification is:

- stop investing in `mlc_llm` / `MLCSwift`
- keep the browser extension focused on `Apple Intelligence` and `BYOK`
- converge the app-side model abstraction around `AnyLanguageModel`

This would trade maximum offline coverage for a narrower, easier-to-explain architecture.

## Scope / Positioning

This plan covers:

- evaluating removal of the MLC/MLCSwift path from the app
- evaluating whether the extension should drop WebLLM/MLC-based local inference
- using `AnyLanguageModel` as the main abstraction layer for Apple Intelligence and BYOK
- clarifying how this affects product promises, setup, fallback, and supported devices

This plan does not yet cover:

- the exact migration sequence in code
- the final user-facing pricing or provider strategy
- a commitment to remove all existing model assets immediately

## Main Model

### Proposed Direction

The proposed target architecture is:

- `Local`: Apple Intelligence only
- `Cloud / User-provided`: BYOK only
- `Abstraction layer`: AnyLanguageModel-based request flow
- `Removed or deprecated`: MLC/MLCSwift and possibly WebLLM-based local model execution

### Why This Direction Might Help

- reduce build and packaging complexity
- remove custom local model maintenance burden
- reduce duplicated inference logic across app and extension
- make model behavior easier to explain in onboarding and settings
- align implementation with the currently growing Apple Intelligence + BYOK paths

### Core Tradeoff

The main tradeoff is loss of universal on-device fallback.

Today, MLC/WebLLM gives the product a local path on devices without Apple Intelligence. If that path is removed, the product becomes more dependent on:

- Apple Intelligence eligibility
- user willingness to configure BYOK
- clearer capability messaging per device

This changes the meaning of "local-first" from "works locally on more devices" to "prefer local when Apple Intelligence is available, otherwise use user-provided remote models."

### Likely Product Impact

- onboarding would need clearer branching for `Apple Intelligence available` vs `BYOK required`
- settings would shift from model packaging and local runtime concerns toward capability availability and provider setup
- extension messaging would likely become simpler because only two backends remain
- docs, README copy, and App Store positioning would need to stop implying MLC-backed local support

### Likely Technical Impact

Areas likely affected if this plan moves forward:

- `iOS (App)/Features/Demos/MLC/`
- `iOS (App)/Config/mlc-app-config.json`
- MLC packaging files such as `mlc-package-config*.json`
- build and verification scripts for MLC artifacts
- `Shared (Extension)/Resources/webllm*`
- docs that currently describe WebLLM / MLC as active architecture

Areas that already align with this direction:

- `Shared (Extension)/SafariWebExtensionHandler.swift`
- `iOS (App)/Shared/FoundationModels/`
- `iOS (App)/Features/Settings/AIModelsSettingsView.swift`

## Relationship To Other Docs

This plan intersects with:

- `Spec/SPEC.md`
- `Docs/DEVELOPMENT.md`
- `Docs/long-document-reading-pipeline.md`
- `Docs/OpenDoc/eisonAI.md`
- `Docs/Plan/browser-integration-learning-assistant.md`

If adopted, this plan should later produce follow-up docs for:

- supported backend matrix by platform and device class
- migration and deprecation plan for MLC assets and scripts
- revised onboarding and positioning language
- extension backend behavior after WebLLM removal or reduction

## Open Questions

- Is the goal to remove only `MLCSwift`, or also remove WebLLM from the extension?
- If WebLLM is removed, what is the expected experience on devices without Apple Intelligence and without BYOK?
- Does the product still want to claim strong offline capability after this change?
- Can `AnyLanguageModel` fully cover the app and extension request patterns now handled by separate stacks?
- Should MLC remain as a debug-only or legacy fallback path during migration?
- Is the suspected idle heat caused by automatic MLX/MLC runtime startup, model preloading, WebGPU/Metal initialization, or an unrelated app lifecycle path?

## Suggested Next Steps

1. Write a backend matrix comparing current and target behavior by platform, OS version, and device capability.
2. Decide whether WebLLM is in scope for removal or whether only app-side MLC is being deprecated.
3. Audit every user-facing place that currently promises on-device local inference.
4. Define a staged migration plan before touching assets, scripts, or docs that still describe MLC as current architecture.
5. Instrument app launch and idle state to confirm whether MLX/MLC initializes without explicit user inference, then capture energy/CPU/GPU evidence before deciding on lazy loading or removal.
