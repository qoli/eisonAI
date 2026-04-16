import Foundation

struct AutoStrategySettingsStore {
    static let shared = AutoStrategySettingsStore()
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)

    enum LocalModelPreference: String, CaseIterable {
        case appleIntelligence
        case mlx

        var displayName: String {
            switch self {
            case .appleIntelligence:
                return "Apple Intelligence"
            case .mlx:
                return "Selected MLX Model"
            }
        }
    }

    func strategyThreshold() -> Int {
        LongDocumentDefaults.autoStrategyThresholdValue
    }

    func localModelPreference() -> LocalModelPreference {
        guard let raw = defaults?.string(forKey: AppConfig.autoLocalModelPreferenceKey),
              let preference = LocalModelPreference(rawValue: raw)
        else {
            if defaults?.string(forKey: AppConfig.autoLocalModelPreferenceKey) == "qwen3" {
                return .mlx
            }
            return .appleIntelligence
        }
        return preference
    }

    func setLocalModelPreference(_ preference: LocalModelPreference) {
        defaults?.set(preference.rawValue, forKey: AppConfig.autoLocalModelPreferenceKey)
    }
}
