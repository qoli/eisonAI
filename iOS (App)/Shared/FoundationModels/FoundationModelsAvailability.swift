import Foundation

#if canImport(AnyLanguageModel)
    import AnyLanguageModel
#endif

enum AppleIntelligenceAvailability {
    enum Status: Equatable {
        case notSupported
        case available
        case unavailable(String)
    }

    static func currentStatus() -> Status {
        guard #available(iOS 26.0, *) else {
            return .notSupported
        }

        #if canImport(FoundationModels) && canImport(AnyLanguageModel)
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unavailable("Device not eligible for Apple Intelligence.")
                case .appleIntelligenceNotEnabled:
                    return .unavailable("Apple Intelligence is not enabled.")
                case .modelNotReady:
                    return .unavailable("Apple Intelligence models are still downloading.")
                @unknown default:
                    return .unavailable("Apple Intelligence is unavailable.")
                }
            }
        #else
            return .notSupported
        #endif
    }
}
