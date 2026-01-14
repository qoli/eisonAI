import SwiftUI

struct DebugSettingsView: View {
    @State private var debugStatus = ""

    var body: some View {
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
                Text("Paste from clipboard and split long text into 2000-token chunks (using the selected tokenizer).")
                    .foregroundStyle(.secondary)
            }

            Section("Prompts") {
                NavigationLink("Prompt Settings") {
                    PromptSettingsView()
                }
                Text("Manage summary, chunk, and title prompts in one place.")
                    .foregroundStyle(.secondary)
            }

            Section("AppConfig") {
                NavigationLink("AppConfig Data") {
                    AppConfigDebugView()
                }
                Text("Inspect AppConfig constants and stored values.")
                    .foregroundStyle(.secondary)
            }

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
        }
        .navigationTitle("Debug")
    }
}

#Preview {
    NavigationStack {
        DebugSettingsView()
    }
}
