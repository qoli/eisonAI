import Foundation

final class TokenEstimatorSettingsStore {
    static let shared = TokenEstimatorSettingsStore()

    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)
    private let fallbackEncoding: Encoding = .cl100k

    func selectedEncoding() -> Encoding {
        guard
            let raw = defaults?.string(forKey: AppConfig.tokenEstimatorEncodingKey),
            let encoding = Encoding(rawValue: raw)
        else {
            return fallbackEncoding
        }
        return encoding
    }

    func selectedEncodingRawValue() -> String {
        selectedEncoding().rawValue
    }

    func setSelectedEncoding(_ encoding: Encoding) {
        defaults?.set(encoding.rawValue, forKey: AppConfig.tokenEstimatorEncodingKey)
    }
}
