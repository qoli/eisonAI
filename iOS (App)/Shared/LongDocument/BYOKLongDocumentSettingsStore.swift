import Foundation

final class BYOKLongDocumentSettingsStore {
    static let shared = BYOKLongDocumentSettingsStore()

    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)
    private let fallbackChunkSize = 4096
    private let fallbackRoutingThreshold = 7168

    func chunkTokenSize() -> Int {
        guard let stored = defaults?.object(forKey: AppConfig.byokLongDocumentChunkTokenSizeKey) as? Int else {
            return fallbackChunkSize
        }
        return max(1, stored)
    }

    func setChunkTokenSize(_ value: Int) {
        defaults?.set(max(1, value), forKey: AppConfig.byokLongDocumentChunkTokenSizeKey)
    }

    func routingThreshold() -> Int {
        guard let stored = defaults?.object(forKey: AppConfig.byokLongDocumentRoutingThresholdKey) as? Int else {
            return fallbackRoutingThreshold
        }
        return max(1, stored)
    }

    func setRoutingThreshold(_ value: Int) {
        defaults?.set(max(1, value), forKey: AppConfig.byokLongDocumentRoutingThresholdKey)
    }
}
