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

    static var httpOptions: [ProviderOption] {
        let baseProviders: [BYOKProvider] = [.ollama, .anthropic, .gemini, .openAIChat, .openAIResponses]
        var options = baseProviders.map { provider in
            ProviderOption(
                id: provider.rawValue,
                displayName: provider.displayName,
                provider: provider,
                preset: ProviderPresets.defaultPreset(for: provider)
            )
        }

        let extraOptions = ProviderPresets.additionalPresets.map { preset in
            ProviderOption(
                id: "preset.\(preset.id)",
                displayName: preset.displayName,
                provider: preset.provider,
                preset: preset
            )
        }
        options.append(contentsOf: extraOptions)
        return options
    }
}

extension BYOKProvider {
    var supportsModelList: Bool {
        switch self {
        case .ollama, .openAIChat, .openAIResponses:
            return true
        case .anthropic, .gemini:
            return false
        }
    }

    var shouldStripTrailingV1: Bool {
        switch self {
        case .openAIChat, .openAIResponses:
            return false
        case .ollama, .anthropic, .gemini:
            return true
        }
    }

    struct ProviderPreset: Identifiable, Equatable {
        let id: String
        let displayName: String
        let provider: BYOKProvider
        let apiURL: String
        let docsURL: URL
        let isDefault: Bool
    }

    struct ProviderOption: Identifiable {
        let id: String
        let displayName: String
        let provider: BYOKProvider
        let preset: ProviderPreset?
    }

    enum ProviderPresets {
        static let all: [ProviderPreset] = [
            ProviderPreset(
                id: "ollama",
                displayName: "Ollama",
                provider: .ollama,
                apiURL: "http://localhost:11434",
                docsURL: URL(string: "https://ollama.com/")!,
                isDefault: true
            ),
            ProviderPreset(
                id: "anthropic",
                displayName: "Anthropic",
                provider: .anthropic,
                apiURL: "https://api.anthropic.com/v1",
                docsURL: URL(string: "https://docs.anthropic.com/")!,
                isDefault: true
            ),
            ProviderPreset(
                id: "gemini",
                displayName: "Gemini",
                provider: .gemini,
                apiURL: "https://generativelanguage.googleapis.com/v1beta",
                docsURL: URL(string: "https://ai.google.dev/gemini-api/docs")!,
                isDefault: true
            ),
            ProviderPreset(
                id: "openai.chat",
                displayName: "OpenAI (Chat)",
                provider: .openAIChat,
                apiURL: "https://api.openai.com/v1",
                docsURL: URL(string: "https://platform.openai.com/docs")!,
                isDefault: true
            ),
            ProviderPreset(
                id: "openai.responses",
                displayName: "OpenAI (Responses)",
                provider: .openAIResponses,
                apiURL: "https://api.openai.com/v1",
                docsURL: URL(string: "https://platform.openai.com/docs")!,
                isDefault: true
            ),
            ProviderPreset(
                id: "siliconflow",
                displayName: "SiliconFlow",
                provider: .openAIChat,
                apiURL: "https://api.siliconflow.cn/v1",
                docsURL: URL(string: "https://docs.siliconflow.cn/cn/userguide/quickstart")!,
                isDefault: false
            )
        ]

        static func defaultPreset(for provider: BYOKProvider) -> ProviderPreset? {
            all.first { $0.provider == provider && $0.isDefault }
        }

        static var additionalPresets: [ProviderPreset] {
            all.filter { !$0.isDefault }
        }

        static func match(url: String, provider: BYOKProvider? = nil) -> ProviderPreset? {
            guard let components = URLComponents(string: url), let host = components.host else {
                return nil
            }
            let candidates = all.filter { preset in
                guard let provider else { return true }
                return preset.provider == provider
            }

            if let exact = candidates.first(where: { $0.apiURL == url }) {
                return exact
            }

            return candidates.first { preset in
                guard let presetHost = URLComponents(string: preset.apiURL)?.host else {
                    return false
                }
                return presetHost == host
            }
        }

        static func optionID(
            provider: BYOKProvider,
            apiURL: String
        ) -> String {
            if let preset = match(url: apiURL, provider: provider),
               !preset.isDefault {
                return "preset.\(preset.id)"
            }
            return provider.rawValue
        }
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
    case apiURLInvalid
    case modelMissing

    var message: String {
        switch self {
        case .apiURLMissing:
            return "Enter an API base URL."
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

enum BYOKURLResolverError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL."
        }
    }
}

struct BYOKURLResolver {
    static func resolveBaseURL(for provider: BYOKProvider, rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw BYOKURLResolverError.invalidURL
        }
        return normalizeBaseURL(url, removingTrailingV1: provider.shouldStripTrailingV1)
    }

    static func normalizeBaseURL(_ url: URL, removingTrailingV1: Bool) -> URL {
        var resolved = url
        if removingTrailingV1 {
            let lowercasedPath = resolved.path.lowercased()
            if lowercasedPath.hasSuffix("/v1") || lowercasedPath.hasSuffix("/v1/") {
                resolved.deleteLastPathComponent()
            }
        }
        if !resolved.path.hasSuffix("/") {
            resolved.appendPathComponent("")
        }
        return resolved
    }
}
