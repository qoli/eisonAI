import SwiftUI

struct SettingsView: View {
    private let store = SystemPromptStore()
    private let foundationModelsStore = FoundationModelsSettingsStore()

    @State private var draftPrompt = ""
    @State private var status = ""
    @State private var didLoad = false
    @State private var showClipboardKeyPoint = false
    @State private var foundationModelsAppEnabled = false
    @State private var foundationModelsExtensionEnabled = false

    var body: some View {
        let fmStatus = FoundationModelsAvailability.currentStatus()

        Form {
            Section("Clipboard") {
                Button("Key-point from Clipboard") {
                    showClipboardKeyPoint = true
                }
                Text("Reads URL or text from clipboard, generates key points, and saves to Library.")
                    .foregroundStyle(.secondary)
            }

            Section("Demos") {
                NavigationLink("Qwen3 0.6B (MLC Swift)") {
                    MLCQwenDemoView()
                }
                Text("A single-turn, streaming chat demo using the native MLC Swift SDK.")
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
                case .unavailable(let reason):
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

            Section("Safari Extension") {
                Text("Enable eisonAI’s Safari extension in Settings → Safari → Extensions.")
                Text("Summaries run in the extension popup via WebLLM (bundled assets).")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showClipboardKeyPoint) {
            ClipboardKeyPointSheet()
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            draftPrompt = store.load()

            foundationModelsAppEnabled = foundationModelsStore.isAppEnabled()
            foundationModelsExtensionEnabled = foundationModelsStore.isExtensionEnabled()

            if FoundationModelsAvailability.currentStatus() != .available {
                foundationModelsAppEnabled = false
                foundationModelsExtensionEnabled = false
                foundationModelsStore.setAppEnabled(false)
                foundationModelsStore.setExtensionEnabled(false)
            }
        }
    }
}
