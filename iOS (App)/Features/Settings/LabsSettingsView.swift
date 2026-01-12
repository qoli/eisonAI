import SwiftUI

struct LabsSettingsView: View {
    @AppStorage(AppConfig.localQwenEnabledKey, store: UserDefaults(suiteName: AppConfig.appGroupIdentifier))
    private var localQwenEnabled = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable Local Qwen3 0.6B", isOn: $localQwenEnabled)
            } header: {
                Text("Local Models")
            } footer: {
                Text("Required to show Qwen3 0.6B in model selectors.")
            }
        }
        .navigationTitle("Labs")
        .onChange(of: localQwenEnabled) { _, newValue in
            if !newValue {
                downgradeBackendIfNeeded()
            }
        }
    }

    private func downgradeBackendIfNeeded() {
        let store = GenerationBackendSettingsStore()
        guard store.loadSelectedBackend() == .mlc else { return }
        let fallback: GenerationBackend
        if AppleIntelligenceAvailability.currentStatus() == .available {
            fallback = .appleIntelligence
        } else {
            fallback = .byok
        }
        store.saveSelectedBackend(fallback)
    }
}

#Preview {
    NavigationStack {
        LabsSettingsView()
    }
}
