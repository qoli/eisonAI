import Foundation

final class TokenEstimatorSettingsStore {
    static let shared = TokenEstimatorSettingsStore()

    private let defaults: UserDefaults?
    private let fallbackEncoding: Encoding = .cl100k

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppConfig.appGroupIdentifier)) {
        self.defaults = defaults
    }

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
