# Key-Point Function Chains

## Safari Extension

```text
popup.js
  → sendNative("getGenerationBackend" / "getBYOKSettings")
  → sendNative("fm.stream.start")
  → SafariWebExtensionHandler.resolveExecutionBackend
  → FoundationModelsStreamManager.start
  → LanguageModelSession.streamResponse
  → sendNative("fm.stream.poll")
  → popup renders deltas and persists the Library item
```

The concrete model is either `SystemLanguageModel` or a BYOK provider model supplied by `AnyLanguageModel`.

## App

```text
ClipboardKeyPointViewModel.run
  → prepareInput
  → GPTTokenEstimator.estimateTokenCount
  → GenerationBackendSettingsStore.resolveExecutionBackend
  → runSingleSummary OR runLongDocumentPipeline
  → AnyLanguageModelClient.streamChat
  → RawLibraryStore completes or fails the pending item
```

## Generated Titles

```text
GenerationService.generateTitleIfNeeded
  → GenerationBackendSettingsStore.resolveExecutionBackend
  → AnyLanguageModelClient.streamChat
  → RawLibraryStore.updateTitle
```

No chain contains a downloadable-model loader, model catalog, or background model download job.
