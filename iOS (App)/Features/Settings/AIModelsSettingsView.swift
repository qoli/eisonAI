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
            Section("Apple Intelligence") {
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

                Text("If unavailable, eisonAI falls back to its built-in WebLLM/MLC models.")
                    .foregroundStyle(.secondary)
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
