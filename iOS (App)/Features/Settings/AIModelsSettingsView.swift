import SwiftUI

struct AIModelsSettingsView: View {
    private let foundationModelsStore = FoundationModelsSettingsStore()
    @State private var didLoad = false
    @State private var foundationModelsAppEnabled = false
    @State private var foundationModelsExtensionEnabled = false

    var fmStatus: FoundationModelsAvailability.Status {
        FoundationModelsAvailability.currentStatus()
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Qwen3 (0.6B)")
                        .font(.headline)

                    Text("A lightweight on‑device model optimized for speed and lower memory use. Best for quick summaries, drafting, and simple coding. For complex tasks, consider a larger model when available.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("On‑Device Model")
            } footer: {
                Text("Runs locally without a network connection.")
            }

            Section {
                Toggle(
                    "Use Apple Intelligence in the app",
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
                    "Use Apple Intelligence in Safari extension",
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
                    Text("Available on this device.")
                        .foregroundStyle(.secondary)
                case .notSupported:
                    Text("Requires iOS 26+ and Apple Intelligence enabled.")
                        .foregroundStyle(.secondary)
                case let .unavailable(reason):
                    Text(reason)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Apple Intelligence")
            } footer: {
                Text("Uses Apple’s on‑device intelligence when available; otherwise eisonAI uses its built‑in models.")
            }
        }
        .navigationTitle("AI Models")
        .onAppear {
            if !didLoad {
                didLoad = true
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
}

#Preview {
    NavigationStack {
        AIModelsSettingsView()
    }
}
