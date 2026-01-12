import Foundation

enum GenerationBackend: String, CaseIterable, Codable {
    case auto = "auto"
    case mlc = "mlc"
    case appleIntelligence = "apple"
    case byok = "byok"

    var displayName: String {
        switch self {
        case .auto:
            return "Auto"
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

    func effectiveBackend(tokenCount: Int? = nil) -> GenerationBackend {
        let selected = loadSelectedBackend()
        let availability = localAvailability()
        switch selected {
        case .auto:
            return resolveAutoBackend(tokenCount: tokenCount, availability: availability)
        case .mlc:
            return availability.isQwenAvailable ? .mlc : fallbackBackend(availability: availability)
        case .appleIntelligence:
            return availability.isAppleAvailable ? .appleIntelligence : fallbackBackend(availability: availability)
        case .byok:
            return .byok
        }
    }

    func localModelAvailability() -> LocalModelAvailability {
        localAvailability()
    }

    func preferredLocalBackend() -> GenerationBackend? {
        let availability = localAvailability()
        let preference = AutoStrategySettingsStore.shared.localModelPreference()
        switch preference {
        case .appleIntelligence:
            if availability.isAppleAvailable { return .appleIntelligence }
            if availability.isQwenAvailable { return .mlc }
        case .qwen3:
            if availability.isQwenAvailable { return .mlc }
            if availability.isAppleAvailable { return .appleIntelligence }
        }
        return nil
    }

    private func resolveAutoBackend(
        tokenCount: Int?,
        availability: LocalModelAvailability
    ) -> GenerationBackend {
        let threshold = AutoStrategySettingsStore.shared.strategyThreshold()
        let useLocal = tokenCount.map { $0 <= threshold } ?? true
        if useLocal, let local = preferredLocalBackend() {
            return local
        }
        if !useLocal {
            return .byok
        }
        return fallbackBackend(availability: availability)
    }

    private func fallbackBackend(availability: LocalModelAvailability) -> GenerationBackend {
        if availability.isAppleAvailable {
            return .appleIntelligence
        }
        if availability.isQwenAvailable {
            return .mlc
        }
        return .byok
    }

    private func localAvailability() -> LocalModelAvailability {
        let qwenEnabled = LabsSettingsStore().isLocalQwenEnabled()
        let appleAvailable = AppleIntelligenceAvailability.currentStatus() == .available
        return LocalModelAvailability(
            isQwenAvailable: qwenEnabled,
            isAppleAvailable: appleAvailable
        )
    }
}

struct LocalModelAvailability {
    let isQwenAvailable: Bool
    let isAppleAvailable: Bool

    var hasAnyLocal: Bool {
        isQwenAvailable || isAppleAvailable
    }
}
