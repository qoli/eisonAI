import Foundation

struct AutoStrategySettingsStore {
    static let shared = AutoStrategySettingsStore()
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

    let allowedThresholds: [Int] = [2600, 7168]
    private let defaultThreshold = 7168

    func strategyThreshold() -> Int {
        guard let stored = defaults?.object(forKey: AppConfig.autoStrategyThresholdKey) as? Int,
              allowedThresholds.contains(stored)
        else {
            return defaultThreshold
        }
        return stored
    }

    func setStrategyThreshold(_ value: Int) {
        guard allowedThresholds.contains(value) else { return }
        defaults?.set(value, forKey: AppConfig.autoStrategyThresholdKey)
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
