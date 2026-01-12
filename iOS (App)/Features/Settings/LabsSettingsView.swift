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
        guard store.loadSelectedBackend() == .local else { return }
        if AppleIntelligenceAvailability.currentStatus() != .available {
            store.saveSelectedBackend(.byok)
        }
    }
}

#Preview {
    NavigationStack {
        LabsSettingsView()
    }
}
