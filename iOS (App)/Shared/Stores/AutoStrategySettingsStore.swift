import Foundation

struct AutoStrategySettingsStore {
    static let shared = AutoStrategySettingsStore()
    static let fixedThreshold = 2600
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)

    enum LocalModelPreference: String, CaseIterable {
        case appleIntelligence
        case qwen3

        var displayName: String {
            switch self {
            case .appleIntelligence:
                return "Apple Intelligence"
            case .qwen3:
                return "Qwen3 0.6B"
            }
        }
    }

    func strategyThreshold() -> Int {
        Self.fixedThreshold
    }

    func localModelPreference() -> LocalModelPreference {
        guard let raw = defaults?.string(forKey: AppConfig.autoLocalModelPreferenceKey),
              let preference = LocalModelPreference(rawValue: raw)
        else {
            return .appleIntelligence
        }
        return preference
    }

    func setLocalModelPreference(_ preference: LocalModelPreference) {
        defaults?.set(preference.rawValue, forKey: AppConfig.autoLocalModelPreferenceKey)
    }
}
