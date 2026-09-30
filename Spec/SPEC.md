# eisonAI 2.x Current Product Specification

## Product

eisonAI is an iOS/iPadOS app and Safari extension that turns articles and shared text into structured reading material, stores results in a local Library, and optionally syncs them through CloudKit.

## Supported Generation Backends

- Apple Intelligence through `SystemLanguageModel` on eligible iOS 26+ devices.
- BYOK through a user-configured OpenAI-compatible, Ollama, Anthropic, or Gemini endpoint.
- Downloadable local-model runtimes are not supported.

Both the app and Safari extension use `AnyLanguageModel` as the model abstraction. The extension keeps the existing `fm.*` start/poll native-messaging protocol.

## Routing

- `Auto`: short inputs use Apple Intelligence when available; otherwise use BYOK. Inputs above the strategy threshold use BYOK.
- `Local`: means Apple Intelligence only. If unavailable, generation fails explicitly instead of sending the input to BYOK.
- `BYOK`: always uses the configured provider.
- Legacy stored value `mlx` is read as `Local` for upgrade compatibility; there is no MLX execution backend.

## Long Documents

Apple Intelligence uses the chunked reading-anchor pipeline when the estimated input size exceeds the long-document threshold. If the Foundation Models context window is exceeded, the app retries with a smaller allowed chunk size. BYOK stays on the direct provider path.

## Settings

`Settings → AI Models` controls:

- in-app and Safari backend selection;
- BYOK provider, endpoint, key, model, connection check, and save flow;
- Apple Intelligence availability;
- long-document chunk size and maximum chunk count.

There is no model catalog, local-model installer, download job, or model-management UI.

## Acceptance

- The simulator build and XCTest cover compile-time integration, routing, and helper behavior.
- Apple Intelligence generation requires an eligible physical device for runtime acceptance.
- BYOK generation requires an accessible user-configured endpoint.
