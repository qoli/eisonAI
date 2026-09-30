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
    case appleIntelligence = "apple"
    case byok = "byok"

    var displayName: String {
        switch self {
        case .appleIntelligence:
            return "Apple Intelligence"
        case .byok:
            return "BYOK"
        }
    }
}

struct GenerationBackendSettingsStore {
    private let defaults: UserDefaults?
    private let appleAvailability: () -> AppleIntelligenceAvailability.Status

    init(
        defaults: UserDefaults? = UserDefaults(suiteName: AppConfig.appGroupIdentifier),
        appleAvailability: @escaping () -> AppleIntelligenceAvailability.Status = {
            AppleIntelligenceAvailability.currentStatus()
        }
    ) {
        self.defaults = defaults
        self.appleAvailability = appleAvailability
    }

    private var isAppleAvailable: Bool {
        appleAvailability() == .available
    }

    func loadSelectedBackend() -> GenerationBackend {
        guard let raw = defaults?.string(forKey: AppConfig.appGenerationBackendKey)
            ?? defaults?.string(forKey: AppConfig.legacyGenerationBackendKey)
        else {
            return .local
        }
        if let backend = GenerationBackend(rawValue: raw) {
            return backend
        }
        if raw == "mlx" || raw == ExecutionBackend.appleIntelligence.rawValue {
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

    func validateSelectedBackendForGeneration() throws {
        guard loadSelectedBackend() == .local else { return }
        guard isAppleAvailable else {
            throw NSError(
                domain: "EisonAI.GenerationBackend",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Apple Intelligence is selected but unavailable. Enable it or choose BYOK in Settings."
                ]
            )
        }
    }

    func resolveExecutionBackendType(tokenCount: Int?) -> ExecutionBackendType {
        let selected = loadSelectedBackend()
        let appleAvailable = isAppleAvailable
        switch selected {
        case .auto:
            let threshold = AutoStrategySettingsStore.shared.strategyThreshold()
            let count = max(0, tokenCount ?? 0)
            let type: ExecutionBackendType = count <= threshold ? .local : .byok
            return type == .local && !appleAvailable ? .byok : type
        case .local:
            return .local
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
            return .appleIntelligence
        }
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
