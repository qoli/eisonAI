import Foundation

struct LabsSettingsStore {
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)

    func isLocalQwenEnabled() -> Bool {
        defaults?.bool(forKey: AppConfig.localQwenEnabledKey) ?? false
    }

    func setLocalQwenEnabled(_ value: Bool) {
        defaults?.set(value, forKey: AppConfig.localQwenEnabledKey)
    }
}
