# Key-Point Generation

## Safari

1. `Shared (Extension)/Resources/webllm/popup.js` extracts the page and estimates tokens.
2. The popup reads backend and BYOK settings through native messaging.
3. `fm.stream.start` selects Apple Intelligence or BYOK in `SafariWebExtensionHandler`.
4. The popup polls deltas, renders the structured response, and updates the pending Library record.

The `webllm` directory name is historical. No browser-local inference engine is loaded.

## App

1. `ClipboardKeyPointViewModel` normalizes clipboard/share input.
2. `GenerationBackendSettingsStore` resolves Apple Intelligence or BYOK.
3. Short input uses a single streaming request.
4. Long Apple Intelligence input uses the reading-anchor pipeline.
5. The result and generation state are persisted through `RawLibraryStore`.

## Failure Behavior

- Auto may select BYOK when Apple Intelligence is unavailable. An explicit Local selection fails without sending the input to BYOK.
- Invalid BYOK settings fail closed with a visible configuration error.
- A failed or cancelled generation updates the existing pending Library record instead of silently creating a completed item.
