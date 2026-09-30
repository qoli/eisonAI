import Foundation

struct AutoStrategySettingsStore {
    static let shared = AutoStrategySettingsStore()

    func strategyThreshold() -> Int {
        LongDocumentDefaults.autoStrategyThresholdValue
    }
}
