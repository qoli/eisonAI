import Foundation

@MainActor
final class SharePollingSettingsStore {
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)

    func isEnabled() -> Bool {
        guard let defaults else { return true }
        if defaults.object(forKey: AppConfig.sharePollingEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: AppConfig.sharePollingEnabledKey)
    }

    func setEnabled(_ value: Bool) {
        defaults?.set(value, forKey: AppConfig.sharePollingEnabledKey)
    }
}
