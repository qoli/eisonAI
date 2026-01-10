import SwiftUI

struct GeneralSettingsView: View {
    private let sharePollingStore = SharePollingSettingsStore()

    @State private var sharePollingEnabled = true
    @State private var didLoad = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Safari Extension")
                        .font(.headline)

                    Text("Enable eisonAI in Settings > Safari > Extensions. Summaries run in the extension popup using built-in WebLLM models.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Extensions")
            } footer: {
                Text("This lets you summarize pages directly from Safari.")
            }

            Section {
                Toggle(
                    "Share Polling",
                    isOn: Binding(
                        get: { sharePollingEnabled },
                        set: { newValue in
                            sharePollingEnabled = newValue
                            sharePollingStore.setEnabled(newValue)
                        }
                    )
                )
            } header: {
                Text("Share Extension")
            } footer: {
                Text("When enabled, the app checks every 2 seconds while it is in the foreground.")
            }
        }
        .navigationTitle("General")
        .onAppear {
            if !didLoad {
                didLoad = true
                sharePollingEnabled = sharePollingStore.isEnabled()
            }
        }
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
    }
}
