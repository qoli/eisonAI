import Foundation

@MainActor
final class FoundationModelsSettingsStore {
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)

    func isAppEnabled() -> Bool {
        defaults?.bool(forKey: AppConfig.foundationModelsAppEnabledKey) ?? false
    }

    func setAppEnabled(_ value: Bool) {
        defaults?.set(value, forKey: AppConfig.foundationModelsAppEnabledKey)
    }

    func isExtensionEnabled() -> Bool {
        defaults?.bool(forKey: AppConfig.foundationModelsExtensionEnabledKey) ?? false
    }

    func setExtensionEnabled(_ value: Bool) {
        defaults?.set(value, forKey: AppConfig.foundationModelsExtensionEnabledKey)
    }
}

