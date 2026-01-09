import Foundation

final class LongDocumentSettingsStore {
    static let shared = LongDocumentSettingsStore()

    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)
    private let allowedChunkSizes: [Int] = [2000, 2200, 2600, 3000, 3200]
    private let fallbackChunkSize = 2000
    private let routingThresholdValue = 2600
    private let allowedMaxChunkCounts: [Int] = [4, 5, 6, 7]
    private let fallbackMaxChunkCount = 5

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

    func routingThreshold() -> Int {
        routingThresholdValue
    }

    func maxChunkCount() -> Int {
        guard let stored = defaults?.object(forKey: AppConfig.longDocumentMaxChunkCountKey) as? Int else {
            return fallbackMaxChunkCount
        }
        return allowedMaxChunkCounts.contains(stored) ? stored : fallbackMaxChunkCount
    }

    func setMaxChunkCount(_ value: Int) {
        let resolved = allowedMaxChunkCounts.contains(value) ? value : fallbackMaxChunkCount
        defaults?.set(resolved, forKey: AppConfig.longDocumentMaxChunkCountKey)
    }

    func maxChunkCountOptions() -> [Int] {
        allowedMaxChunkCounts
    }
}
