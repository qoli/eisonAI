import Foundation

struct BrowserPrototypeSettingsStore {
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)

    func isEnabled() -> Bool {
        defaults?.bool(forKey: AppConfig.browserPrototypeEnabledKey) ?? false
    }

    func setEnabled(_ enabled: Bool) {
        defaults?.set(enabled, forKey: AppConfig.browserPrototypeEnabledKey)
    }
}
