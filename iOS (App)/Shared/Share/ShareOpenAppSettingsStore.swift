import Foundation

@MainActor
final class ShareOpenAppSettingsStore {
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)

    func isEnabled() -> Bool {
        guard let defaults else { return true }
        if defaults.object(forKey: AppConfig.shareOpenAppAfterShareKey) == nil {
            return true
        }
        return defaults.bool(forKey: AppConfig.shareOpenAppAfterShareKey)
    }

    func setEnabled(_ value: Bool) {
        defaults?.set(value, forKey: AppConfig.shareOpenAppAfterShareKey)
    }
}
