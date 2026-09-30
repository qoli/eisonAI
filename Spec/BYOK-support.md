# BYOK Specification

## Providers

eisonAI supports these user-configured providers through `AnyLanguageModel`:

- OpenAI Chat Completions
- OpenAI Responses
- Ollama HTTP API
- Anthropic Messages API
- Google Gemini API

Apple Intelligence is selected as a generation backend, not as a BYOK provider.

## Settings and Storage

`Settings → AI Models → BYOK Settings` stores provider, API base URL, API key, and model in the app-group `UserDefaults`.

- API keys may be empty for endpoints such as local Ollama.
- Provider presets can supply a base URL.
- OpenAI-compatible and Ollama providers can load a model list.
- `Verify & Save` streams a short ping before persisting the settings.
- Invalid or unreachable configurations show their error without replacing the last verified settings.

## Runtime

The app routes clipboard/share summaries, generated titles, and other model requests through `AnyLanguageModelClient`.

The Safari extension retains the native commands:

- `fm.checkAvailability`
- `fm.prewarm`
- `fm.stream.start`
- `fm.stream.poll`
- `fm.stream.cancel`

The native handler resolves the current backend to Apple Intelligence or BYOK and streams deltas back to the popup.

## Privacy Boundary

Apple Intelligence runs on device when available. BYOK sends generation inputs to the exact provider endpoint configured by the user; the provider’s privacy and retention terms apply.
