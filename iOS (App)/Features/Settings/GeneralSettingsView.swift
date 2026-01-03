import SwiftUI

struct GeneralSettingsView: View {
    private let sharePollingStore = SharePollingSettingsStore()

    @State private var sharePollingEnabled = false
    @State private var didLoad = false

    var body: some View {
        Form {
            Section("Safari Extension") {
                Text("Turn on the eisonAI Safari extension in Settings > Safari > Extensions.")
                Text("Summaries run in the extension popup using built-in WebLLM models.")
                    .foregroundStyle(.secondary)
            }

            Section("Share Extension") {
                Toggle(
                    "Check for shared items while the app is open",
                    isOn: Binding(
                        get: { sharePollingEnabled },
                        set: { newValue in
                            sharePollingEnabled = newValue
                            sharePollingStore.setEnabled(newValue)
                        }
                    )
                )

                Text("When enabled, the app checks for new shared items every 2 seconds while in the foreground.")
                    .foregroundStyle(.secondary)
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
