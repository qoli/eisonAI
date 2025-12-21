import Foundation

@MainActor
final class SharePollingSettingsStore {
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)

    func isEnabled() -> Bool {
        defaults?.bool(forKey: AppConfig.sharePollingEnabledKey) ?? false
    }

    func setEnabled(_ value: Bool) {
        defaults?.set(value, forKey: AppConfig.sharePollingEnabledKey)
    }
}
