# Current Architecture Notes

## Inference

- App and Safari extension support Apple Intelligence and BYOK only.
- `AnyLanguageModel` provides the shared model abstraction.
- The app chooses Apple Intelligence or BYOK through `GenerationBackendSettingsStore`.
- The extension resolves the same two backends in `SafariWebExtensionHandler`.
- Downloadable local models and legacy MLC/WebLLM inference are retired.

## Safari Extension

- Popup entry: `Shared (Extension)/Resources/webllm/popup.html`.
- Popup logic: `Shared (Extension)/Resources/webllm/popup.js`.
- The `webllm` directory name is retained for path stability; its current contents are UI, Markdown, and tokenizer support rather than a local inference engine.
- Native bridge: `Shared (Extension)/SafariWebExtensionHandler.swift`.

## App

- Main generation flow: `iOS (App)/Features/Clipboard/ClipboardKeyPointViewModel.swift`.
- Shared client: `iOS (App)/Shared/Generation/AnyLanguageModelClient.swift`.
- Routing: `iOS (App)/Shared/Generation/GenerationBackend.swift`.
- Model settings: `iOS (App)/Features/Settings/AIModelsSettingsView.swift`.

## Evidence Boundary

Simulator builds prove compilation and routing tests. Apple Intelligence runtime behavior needs an eligible physical device, and BYOK runtime behavior needs the configured external endpoint.
