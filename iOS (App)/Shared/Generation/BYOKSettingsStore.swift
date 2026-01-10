import Foundation

enum BYOKProvider: String, CaseIterable, Codable {
    case ollama = "ollama"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case openAIChat = "openai.chat"
    case openAIResponses = "openai.responses"
    // case appleIntelligence = "apple" // Non-HTTP provider (handled via backend)
    // case mlx = "mlx" // Hidden for now

    var displayName: String {
        switch self {
        case .ollama:
            return "Ollama"
        case .anthropic:
            return "Anthropic"
        case .gemini:
            return "Gemini"
        case .openAIChat:
            return "OpenAI (Chat)"
        case .openAIResponses:
            return "OpenAI (Responses)"
        }
    }

    static var httpOptions: [BYOKProvider] {
        [.ollama, .anthropic, .gemini, .openAIChat, .openAIResponses]
    }
}

struct BYOKSettings: Equatable {
    var provider: BYOKProvider
    var apiURL: String
    var apiKey: String
    var model: String
}

enum BYOKValidationError: Equatable {
    case apiURLMissing
    case apiURLMissingV1
    case apiURLInvalid
    case modelMissing

    var message: String {
        switch self {
        case .apiURLMissing:
            return "Enter an API base URL."
        case .apiURLMissingV1:
            return "Base URL must end with /v1."
        case .apiURLInvalid:
            return "Invalid URL."
        case .modelMissing:
            return "Enter a model ID."
        }
    }
}

struct BYOKSettingsStore {
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)

    func loadSettings() -> BYOKSettings {
        let providerRaw = defaults?.string(forKey: AppConfig.byokProviderKey)
        let provider = BYOKProvider(rawValue: providerRaw ?? "") ?? .openAIChat
        let apiURL = defaults?.string(forKey: AppConfig.byokApiURLKey) ?? ""
        let apiKey = defaults?.string(forKey: AppConfig.byokApiKeyKey) ?? ""
        let model = defaults?.string(forKey: AppConfig.byokModelKey) ?? ""
        return BYOKSettings(
            provider: provider,
            apiURL: apiURL,
            apiKey: apiKey,
            model: model
        )
    }

    func saveSettings(_ settings: BYOKSettings) {
        defaults?.set(settings.provider.rawValue, forKey: AppConfig.byokProviderKey)
        defaults?.set(normalizeAPIURL(settings.apiURL), forKey: AppConfig.byokApiURLKey)
        defaults?.set(settings.apiKey, forKey: AppConfig.byokApiKeyKey)
        defaults?.set(settings.model, forKey: AppConfig.byokModelKey)
    }

    func validationError(for settings: BYOKSettings) -> BYOKValidationError? {
        let trimmedURL = normalizeAPIURL(settings.apiURL)
        if trimmedURL.isEmpty {
            return .apiURLMissing
        }
        let lower = trimmedURL.lowercased()
        if !(lower.hasSuffix("/v1") || lower.hasSuffix("/v1/")) {
            return .apiURLMissingV1
        }
        guard URL(string: trimmedURL) != nil else {
            return .apiURLInvalid
        }
        if settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .modelMissing
        }
        return nil
    }

    func normalizeAPIURL(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension BYOKSettings {
    var trimmedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedApiURL: String {
        apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
