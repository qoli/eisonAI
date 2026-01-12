import Foundation

enum GenerationBackend: String, CaseIterable, Codable {
    case mlc = "mlc"
    case appleIntelligence = "apple"
    case byok = "byok"

    var displayName: String {
        switch self {
        case .mlc:
            return "Qwen3 0.6B"
        case .appleIntelligence:
            return "Apple Intelligence"
        case .byok:
            return "BYOK"
        }
    }
}

struct GenerationBackendSettingsStore {
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)

    func loadSelectedBackend() -> GenerationBackend {
        guard let raw = defaults?.string(forKey: AppConfig.generationBackendKey),
              let backend = GenerationBackend(rawValue: raw)
        else {
            return .mlc
        }
        return backend
    }

    func saveSelectedBackend(_ backend: GenerationBackend) {
        defaults?.set(backend.rawValue, forKey: AppConfig.generationBackendKey)
    }

    func effectiveBackend() -> GenerationBackend {
        let selected = loadSelectedBackend()
        let localQwenEnabled = LabsSettingsStore().isLocalQwenEnabled()
        if selected == .mlc, !localQwenEnabled {
            if AppleIntelligenceAvailability.currentStatus() == .available {
                return .appleIntelligence
            }
            return .byok
        }
        if selected == .appleIntelligence,
           AppleIntelligenceAvailability.currentStatus() != .available {
            if localQwenEnabled {
                return .mlc
            }
            return .byok
        }
        return selected
    }
}
