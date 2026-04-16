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

enum ExtensionGenerationBackendSelection: String, CaseIterable, Codable {
    case auto = "auto"
    case appleIntelligence = "apple"
    case byok = "byok"

    var displayName: String {
        switch self {
        case .auto:
            return "Auto"
        case .appleIntelligence:
            return "Apple Intelligence"
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
    case mlx = "mlx"
    case appleIntelligence = "apple"
    case byok = "byok"

    var displayName: String {
        switch self {
        case .mlx:
            return "MLX"
        case .appleIntelligence:
            return "Apple Intelligence"
        case .byok:
            return "BYOK"
        }
    }
}

struct LocalModelAvailability {
    let isMLXAvailable: Bool
    let isAppleAvailable: Bool

    var hasAnyLocal: Bool {
        isMLXAvailable || isAppleAvailable
    }
}

struct GenerationBackendSettingsStore {
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)

    func loadSelectedBackend() -> GenerationBackend {
        guard let raw = defaults?.string(forKey: AppConfig.appGenerationBackendKey)
            ?? defaults?.string(forKey: AppConfig.legacyGenerationBackendKey)
        else {
            return .local
        }
        if let backend = GenerationBackend(rawValue: raw) {
            return backend
        }
        if raw == ExecutionBackend.mlx.rawValue || raw == ExecutionBackend.appleIntelligence.rawValue {
            return .local
        }
        if raw == ExecutionBackend.byok.rawValue {
            return .byok
        }
        return .local
    }

    func saveSelectedBackend(_ backend: GenerationBackend) {
        defaults?.set(backend.rawValue, forKey: AppConfig.appGenerationBackendKey)
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
        let mlxConfigured = MLXModelStore().hasConfiguredModel()
        let appleAvailable = AppleIntelligenceAvailability.currentStatus() == .available
        return LocalModelAvailability(
            isMLXAvailable: mlxConfigured,
            isAppleAvailable: appleAvailable
        )
    }

    func preferredLocalBackend() -> ExecutionBackend? {
        let availability = localModelAvailability()
        let preference = AutoStrategySettingsStore.shared.localModelPreference()
        switch preference {
        case .appleIntelligence:
            if availability.isAppleAvailable { return .appleIntelligence }
            if availability.isMLXAvailable { return .mlx }
        case .mlx:
            if availability.isMLXAvailable { return .mlx }
            if availability.isAppleAvailable { return .appleIntelligence }
        }
        return nil
    }
}

struct ExtensionGenerationBackendSettingsStore {
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)

    func loadSelectedBackend() -> ExtensionGenerationBackendSelection {
        guard let raw = defaults?.string(forKey: AppConfig.extensionGenerationBackendKey)
            ?? defaults?.string(forKey: AppConfig.legacyGenerationBackendKey)
        else {
            return .auto
        }
        if let selection = ExtensionGenerationBackendSelection(rawValue: raw) {
            return selection
        }
        if raw == GenerationBackend.local.rawValue || raw == ExecutionBackend.appleIntelligence.rawValue {
            return .appleIntelligence
        }
        if raw == GenerationBackend.byok.rawValue || raw == ExecutionBackend.byok.rawValue {
            return .byok
        }
        return .auto
    }

    func saveSelectedBackend(_ backend: ExtensionGenerationBackendSelection) {
        defaults?.set(backend.rawValue, forKey: AppConfig.extensionGenerationBackendKey)
    }
}
