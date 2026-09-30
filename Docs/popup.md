# Safari Popup

The active Safari popup lives under `Shared (Extension)/Resources/webllm/`. The directory name is historical; it does not contain a WebLLM inference runtime.

## Responsibilities

- collect the current page content;
- estimate input size with bundled tokenizer data;
- request Apple Intelligence or BYOK generation through native messaging;
- poll streamed deltas and render Markdown output;
- persist completed or failed Library records through the native bridge.

## Native Commands

- configuration: `getGenerationBackend`, `getBYOKSettings`, `getAutoStrategySettings`;
- generation: `fm.checkAvailability`, `fm.prewarm`, `fm.stream.start`, `fm.stream.poll`, `fm.stream.cancel`;
- Library persistence: the existing raw-item commands handled by `SafariWebExtensionHandler`.

No model weights, WebGPU runtime, worker-based inference engine, or downloadable model files are bundled.
