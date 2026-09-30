import AnyLanguageModel
import Foundation

@MainActor
final class AnyLanguageModelClient {
    enum ClientError: LocalizedError {
        case notSupported
        case unavailable(String)
        case invalidConfiguration(String)

        var errorDescription: String? {
            switch self {
            case .notSupported:
                return "Apple Intelligence requires iOS 26+."
            case let .unavailable(reason):
                return reason
            case let .invalidConfiguration(message):
                return message
            }
        }
    }

    private var prewarmSystemPrompt: String?
    private var prewarmPromptPrefix: String?
    private var prewarmedSession: LanguageModelSession?

    func prewarm(
        systemPrompt: String,
        promptPrefix: String? = nil,
        backend: ExecutionBackend,
        byok: BYOKSettings? = nil
    ) {
        guard backend == .appleIntelligence else { return }
        guard AppleIntelligenceAvailability.currentStatus() == .available else { return }
        guard #available(iOS 26.0, *) else { return }

        let trimmedPrefix = promptPrefix?.trimmingCharacters(in: .whitespacesAndNewlines)
        if prewarmedSession != nil,
           prewarmSystemPrompt == systemPrompt,
           prewarmPromptPrefix == trimmedPrefix {
            return
        }

        let session = LanguageModelSession(
            model: SystemLanguageModel(),
            instructions: systemPrompt
        )
        session.prewarm(promptPrefix: Prompt(trimmedPrefix ?? ""))

        prewarmedSession = session
        prewarmSystemPrompt = systemPrompt
        prewarmPromptPrefix = trimmedPrefix
    }

    func streamChat(
        systemPrompt: String,
        userPrompt: String,
        temperature: Double? = 0.2,
        maximumResponseTokens: Int? = 2048,
        backend: ExecutionBackend,
        byok: BYOKSettings? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        let model = try buildModel(backend: backend, byok: byok)
        let session = takePrewarmedSession(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        ) ?? LanguageModelSession(model: model, instructions: systemPrompt)

        let options = GenerationOptions(
            sampling: nil,
            temperature: temperature,
            maximumResponseTokens: maximumResponseTokens
        )
        let stream = session.streamResponse(to: Prompt(userPrompt), options: options)

        return AsyncThrowingStream { continuation in
            Task {
                var previous = ""
                do {
                    for try await snapshot in stream {
                        if Task.isCancelled { break }
                        let current = String(snapshot.content)
                        let delta = current.hasPrefix(previous)
                            ? String(current.dropFirst(previous.count))
                            : current
                        previous = current
                        if !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func buildModel(
        backend: ExecutionBackend,
        byok: BYOKSettings?
    ) throws -> any AnyLanguageModel.LanguageModel {
        switch backend {
        case .appleIntelligence:
            try ensureAppleAvailable()
            if #available(iOS 26.0, *) {
                return SystemLanguageModel()
            }
            throw ClientError.notSupported
        case .byok:
            guard let byok else {
                throw ClientError.invalidConfiguration("BYOK settings are missing.")
            }
            let store = BYOKSettingsStore()
            if let error = store.validationError(for: byok) {
                throw ClientError.invalidConfiguration(error.message)
            }

            let baseURL: URL
            do {
                baseURL = try BYOKURLResolver.resolveBaseURL(
                    for: byok.provider,
                    rawValue: byok.apiURL
                )
            } catch {
                throw ClientError.invalidConfiguration("API URL 無效")
            }

            switch byok.provider {
            case .openAIChat:
                return OpenAILanguageModel(
                    baseURL: baseURL,
                    apiKey: byok.apiKey,
                    model: byok.trimmedModel,
                    apiVariant: .chatCompletions
                )
            case .openAIResponses:
                return OpenAILanguageModel(
                    baseURL: baseURL,
                    apiKey: byok.apiKey,
                    model: byok.trimmedModel,
                    apiVariant: .responses
                )
            case .ollama:
                return OllamaLanguageModel(
                    baseURL: baseURL,
                    model: byok.trimmedModel
                )
            case .anthropic:
                return AnthropicLanguageModel(
                    baseURL: baseURL,
                    apiKey: byok.apiKey,
                    model: byok.trimmedModel
                )
            case .gemini:
                return GeminiLanguageModel(
                    baseURL: baseURL,
                    apiKey: byok.apiKey,
                    model: byok.trimmedModel
                )
            }
        }
    }

    private func ensureAppleAvailable() throws {
        switch AppleIntelligenceAvailability.currentStatus() {
        case .available:
            return
        case .notSupported:
            throw ClientError.notSupported
        case let .unavailable(reason):
            throw ClientError.unavailable(reason)
        }
    }

    private func takePrewarmedSession(
        systemPrompt: String,
        userPrompt: String
    ) -> LanguageModelSession? {
        guard let prewarmedSession,
              prewarmSystemPrompt == systemPrompt else {
            return nil
        }

        if let prefix = prewarmPromptPrefix,
           !prefix.isEmpty,
           !userPrompt.hasPrefix(prefix) {
            return nil
        }

        self.prewarmedSession = nil
        prewarmSystemPrompt = nil
        prewarmPromptPrefix = nil
        return prewarmedSession
    }
}
