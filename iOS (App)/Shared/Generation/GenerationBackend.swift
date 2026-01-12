import Foundation

enum GenerationBackend: String, CaseIterable, Codable {
    case auto = "auto"
    case local = "local"
    case byok = "byok"

    var displayName: String {
        switch self {
        case .auto:
            return "Auto"
        case .local:
            return "Local"
        case .byok:
            return "BYOK"
        }
    }
}

enum ExecutionBackendType: String {
    case local
    case byok
}

enum ExecutionBackend: String {
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

struct LocalModelAvailability {
    let isQwenAvailable: Bool
    let isAppleAvailable: Bool

    var hasAnyLocal: Bool {
        isQwenAvailable || isAppleAvailable
    }
}

struct GenerationBackendSettingsStore {
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)

    func loadSelectedBackend() -> GenerationBackend {
        guard let raw = defaults?.string(forKey: AppConfig.generationBackendKey) else {
            return .local
        }
        if let backend = GenerationBackend(rawValue: raw) {
            return backend
        }
        if raw == ExecutionBackend.mlc.rawValue || raw == ExecutionBackend.appleIntelligence.rawValue {
            return .local
        }
        if raw == ExecutionBackend.byok.rawValue {
            return .byok
        }
        return .local
    }

    func saveSelectedBackend(_ backend: GenerationBackend) {
        defaults?.set(backend.rawValue, forKey: AppConfig.generationBackendKey)
    }

    func resolveExecutionBackendType(tokenCount: Int?) -> ExecutionBackendType {
        let selected = loadSelectedBackend()
        let availability = localModelAvailability()
        switch selected {
        case .auto:
            let threshold = AutoStrategySettingsStore.shared.strategyThreshold()
            let count = max(0, tokenCount ?? 0)
            let type: ExecutionBackendType = count <= threshold ? .local : .byok
            return type == .local && !availability.hasAnyLocal ? .byok : type
        case .local:
            return availability.hasAnyLocal ? .local : .byok
        case .byok:
            return .byok
        }
    }

    func resolveExecutionBackend(tokenCount: Int?) -> ExecutionBackend {
        let type = resolveExecutionBackendType(tokenCount: tokenCount)
        switch type {
        case .byok:
            return .byok
        case .local:
            if let local = preferredLocalBackend() {
                return local
            }
            return .byok
        }
    }

    func localModelAvailability() -> LocalModelAvailability {
        let qwenEnabled = LabsSettingsStore().isLocalQwenEnabled()
        let appleAvailable = AppleIntelligenceAvailability.currentStatus() == .available
        return LocalModelAvailability(
            isQwenAvailable: qwenEnabled,
            isAppleAvailable: appleAvailable
        )
    }

    func preferredLocalBackend() -> ExecutionBackend? {
        let availability = localModelAvailability()
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
}
