import SwiftUI

struct SettingsView: View {
    private let store = SystemPromptStore()
    private let titlePromptStore = TitlePromptStore()
    private let foundationModelsStore = FoundationModelsSettingsStore()
    private let sharePollingStore = SharePollingSettingsStore()

    @State private var draftPrompt = ""
    @State private var draftTitlePrompt = ""
    @State private var status = ""
    @State private var titlePromptStatus = ""
    @State private var debugStatus = ""
    @State private var cloudSyncStatus = ""
    @State private var isCloudSyncing = false
    @State private var didLoad = false
    @State private var foundationModelsAppEnabled = false
    @State private var foundationModelsExtensionEnabled = false
    @State private var sharePollingEnabled = false

    var body: some View {
        let fmStatus = FoundationModelsAvailability.currentStatus()

        Form {
            Section("Demos") {
                NavigationLink("Qwen3 0.6B (MLC Swift)") {
                    MLCQwenDemoView()
                }
                Text("A single-turn, streaming chat demo using the native MLC Swift SDK.")
                    .foregroundStyle(.secondary)

                NavigationLink("Clipboard 2000-Token Splitter") {
                    ClipboardTokenChunkingView()
                }
                Text("Paste from clipboard and split long text into 2000-token chunks (word tokenizer).")
                    .foregroundStyle(.secondary)
            }

            Section("Foundation Models (Apple Intelligence)") {
                Toggle(
                    "Use Foundation Models (App)",
                    isOn: Binding(
                        get: { foundationModelsAppEnabled },
                        set: { newValue in
                            guard fmStatus == .available else { return }
                            foundationModelsAppEnabled = newValue
                            foundationModelsStore.setAppEnabled(newValue)
                        }
                    )
                )
                .disabled(fmStatus != .available)

                Toggle(
                    "Use Foundation Models (Safari Extension)",
                    isOn: Binding(
                        get: { foundationModelsExtensionEnabled },
                        set: { newValue in
                            guard fmStatus == .available else { return }
                            foundationModelsExtensionEnabled = newValue
                            foundationModelsStore.setExtensionEnabled(newValue)
                        }
                    )
                )
                .disabled(fmStatus != .available)

                switch fmStatus {
                case .available:
                    Text("Available.")
                        .foregroundStyle(.secondary)
                case .notSupported:
                    Text("Requires iOS 26+ with Apple Intelligence enabled.")
                        .foregroundStyle(.secondary)
                case let .unavailable(reason):
                    Text(reason)
                        .foregroundStyle(.secondary)
                }

                Text("When unavailable, the app/extension automatically falls back to the bundled WebLLM/MLC paths.")
                    .foregroundStyle(.secondary)
            }

            Section("System prompt") {
                Text("Used by the Safari extension popup summary.")
                    .foregroundStyle(.secondary)

                TextEditor(text: $draftPrompt)
                    .frame(minHeight: 180)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                HStack {
                    Button("Save") {
                        store.save(draftPrompt)
                        draftPrompt = store.load()
                        status = "Saved."
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reset to default") {
                        store.save(nil)
                        draftPrompt = store.load()
                        status = "Reset to default."
                    }
                    .buttonStyle(.bordered)
                }

                if !status.isEmpty {
                    Text(status)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Title prompt") {
                Text("Used when rebuilding missing titles in the Library detail view.")
                    .foregroundStyle(.secondary)

                TextEditor(text: $draftTitlePrompt)
                    .frame(minHeight: 120)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                HStack {
                    Button("Save") {
                        titlePromptStore.save(draftTitlePrompt)
                        draftTitlePrompt = titlePromptStore.load()
                        titlePromptStatus = "Saved."
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reset to default") {
                        titlePromptStore.save(nil)
                        draftTitlePrompt = titlePromptStore.load()
                        titlePromptStatus = "Reset to default."
                    }
                    .buttonStyle(.bordered)
                }

                if !titlePromptStatus.isEmpty {
                    Text(titlePromptStatus)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Safari Extension") {
                Text("Enable eisonAI’s Safari extension in Settings → Safari → Extensions.")
                Text("Summaries run in the extension popup via WebLLM (bundled assets).")
                    .foregroundStyle(.secondary)
            }

            Section("Share Extension") {
                Toggle(
                    "Enable Share polling (foreground only)",
                    isOn: Binding(
                        get: { sharePollingEnabled },
                        set: { newValue in
                            sharePollingEnabled = newValue
                            sharePollingStore.setEnabled(newValue)
                        }
                    )
                )

                Text("When enabled, the app checks for shared payloads on foreground and polls every 2 seconds while active.")
                    .foregroundStyle(.secondary)
            }

            Section("CloudKit Sync") {
                Button(isCloudSyncing ? "Syncing..." : "Overwrite CloudKit with Local Data") {
                    isCloudSyncing = true
                    cloudSyncStatus = ""
                    Task {
                        do {
                            try await RawLibrarySyncService.shared.overwriteRemoteWithLocal()
                            cloudSyncStatus = "Completed."
                        } catch {
                            cloudSyncStatus = "Failed: \(error.localizedDescription)"
                        }
                        isCloudSyncing = false
                    }
                }
                .disabled(isCloudSyncing)

                Text("This deletes all remote RawLibrary records and re-uploads local files.")
                    .foregroundStyle(.secondary)

                if !cloudSyncStatus.isEmpty {
                    Text(cloudSyncStatus)
                        .foregroundStyle(.secondary)
                }
            }

            #if DEBUG
                Section("Share Payload (Debug)") {
                    Button("Clear pending share payloads") {
                        do {
                            let count = try SharePayloadStore().clearAllPending()
                            debugStatus = "Cleared \(count) payload(s)."
                        } catch {
                            debugStatus = "Clear failed: \(error.localizedDescription)"
                        }
                    }

                    if !debugStatus.isEmpty {
                        Text(debugStatus)
                            .foregroundStyle(.secondary)
                    }
                }
            #endif
        }
        .navigationTitle("Settings")
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            draftPrompt = store.load()
            draftTitlePrompt = titlePromptStore.load()

            foundationModelsAppEnabled = foundationModelsStore.isAppEnabled()
            foundationModelsExtensionEnabled = foundationModelsStore.isExtensionEnabled()
            sharePollingEnabled = sharePollingStore.isEnabled()

            if FoundationModelsAvailability.currentStatus() != .available {
                foundationModelsAppEnabled = false
                foundationModelsExtensionEnabled = false
                foundationModelsStore.setAppEnabled(false)
                foundationModelsStore.setExtensionEnabled(false)
            }
        }
    }
}
