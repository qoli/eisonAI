import Foundation

final class LongDocumentSettingsStore {
    static let shared = LongDocumentSettingsStore()

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppConfig.appGroupIdentifier)) {
        self.defaults = defaults
    }

    func chunkTokenSize() -> Int {
        guard let defaults else { return LongDocumentDefaults.fallbackChunkSize }
        guard let stored = defaults.object(forKey: AppConfig.longDocumentChunkTokenSizeKey) as? Int else {
            return LongDocumentDefaults.fallbackChunkSize
        }
        let resolved = LongDocumentDefaults.allowedChunkSizeSet.contains(stored)
            ? stored
            : LongDocumentDefaults.fallbackChunkSize
        if resolved != stored {
            defaults.set(resolved, forKey: AppConfig.longDocumentChunkTokenSizeKey)
        }
        return resolved
    }

    func setChunkTokenSize(_ value: Int) {
        let resolved = LongDocumentDefaults.allowedChunkSizeSet.contains(value)
            ? value
            : LongDocumentDefaults.fallbackChunkSize
        defaults?.set(resolved, forKey: AppConfig.longDocumentChunkTokenSizeKey)
    }

    func allowedChunkTokenSizes() -> [Int] {
        LongDocumentDefaults.allowedChunkSizes
    }

    func routingThreshold() -> Int {
        LongDocumentDefaults.routingThresholdValue
    }

    func maxChunkCount() -> Int {
        guard let defaults else { return LongDocumentDefaults.fallbackMaxChunkCount }
        guard let stored = defaults.object(forKey: AppConfig.longDocumentMaxChunkCountKey) as? Int else {
            return LongDocumentDefaults.fallbackMaxChunkCount
        }
        let resolved = LongDocumentDefaults.allowedMaxChunkCountSet.contains(stored)
            ? stored
            : LongDocumentDefaults.fallbackMaxChunkCount
        if resolved != stored {
            defaults.set(resolved, forKey: AppConfig.longDocumentMaxChunkCountKey)
        }
        return resolved
    }

    func setMaxChunkCount(_ value: Int) {
        let resolved = LongDocumentDefaults.allowedMaxChunkCountSet.contains(value)
            ? value
            : LongDocumentDefaults.fallbackMaxChunkCount
        defaults?.set(resolved, forKey: AppConfig.longDocumentMaxChunkCountKey)
    }

    func maxChunkCountOptions() -> [Int] {
        LongDocumentDefaults.allowedMaxChunkCounts
    }
}
