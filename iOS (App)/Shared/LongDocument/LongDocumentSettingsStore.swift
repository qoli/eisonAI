import Foundation

final class LongDocumentSettingsStore {
    static let shared = LongDocumentSettingsStore()

    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)
    private let allowedChunkSizes: [Int] = [2200, 2600, 3000, 3200]
    private let fallbackChunkSize = 2600

    func chunkTokenSize() -> Int {
        guard let stored = defaults?.object(forKey: AppConfig.longDocumentChunkTokenSizeKey) as? Int else {
            return fallbackChunkSize
        }
        return allowedChunkSizes.contains(stored) ? stored : fallbackChunkSize
    }

    func setChunkTokenSize(_ value: Int) {
        let resolved = allowedChunkSizes.contains(value) ? value : fallbackChunkSize
        defaults?.set(resolved, forKey: AppConfig.longDocumentChunkTokenSizeKey)
    }

    func allowedChunkTokenSizes() -> [Int] {
        allowedChunkSizes
    }
}
