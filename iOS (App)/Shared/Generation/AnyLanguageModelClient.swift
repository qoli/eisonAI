import Foundation

#if canImport(AnyLanguageModel)
import AnyLanguageModel
#endif

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
    private var prewarmedSession: AnyObject?

    func prewarm(
        systemPrompt: String,
        promptPrefix: String? = nil,
        backend: ExecutionBackend,
        byok: BYOKSettings? = nil
    ) {
        guard backend == .appleIntelligence else { return }
        guard AppleIntelligenceAvailability.currentStatus() == .available else { return }

        #if canImport(AnyLanguageModel)
            guard #available(iOS 26.0, *) else { return }
            let trimmedPrefix = promptPrefix?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let prewarmedSession,
               prewarmSystemPrompt == systemPrompt,
               prewarmPromptPrefix == trimmedPrefix {
                return
            }

            let model = SystemLanguageModel()
            let session = LanguageModelSession(model: model, instructions: systemPrompt)
            session.prewarm(promptPrefix: Prompt(trimmedPrefix ?? ""))

            prewarmedSession = session
            prewarmSystemPrompt = systemPrompt
            prewarmPromptPrefix = trimmedPrefix
        #endif
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

        #if canImport(AnyLanguageModel)
            let session =
                takePrewarmedSession(systemPrompt: systemPrompt, userPrompt: userPrompt)
                ?? LanguageModelSession(model: model, instructions: systemPrompt)

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
                            let delta: String
                            if current.hasPrefix(previous) {
                                delta = String(current.dropFirst(previous.count))
                            } else {
                                delta = current
                            }
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
        #else
            throw ClientError.notSupported
        #endif
    }

    #if canImport(AnyLanguageModel)
        private func buildModel(
            backend: ExecutionBackend,
            byok: BYOKSettings?
        ) throws -> any LanguageModel {
            switch backend {
            case .mlc:
                throw ClientError.invalidConfiguration("MLC is not supported by AnyLanguageModel.")
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
                let modelID = byok.trimmedModel

                switch byok.provider {
                case .openAIChat:
                    return OpenAILanguageModel(
                        baseURL: baseURL,
                        apiKey: byok.apiKey,
                        model: modelID,
                        apiVariant: .chatCompletions
                    )
                case .openAIResponses:
                    return OpenAILanguageModel(
                        baseURL: baseURL,
                        apiKey: byok.apiKey,
                        model: modelID,
                        apiVariant: .responses
                    )
                case .ollama:
                    return OllamaLanguageModel(
                        baseURL: baseURL,
                        model: modelID
                    )
                case .anthropic:
                    return AnthropicLanguageModel(
                        baseURL: baseURL,
                        apiKey: byok.apiKey,
                        model: modelID
                    )
                case .gemini:
                    return GeminiLanguageModel(
                        baseURL: baseURL,
                        apiKey: byok.apiKey,
                        model: modelID
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
            guard let prewarmedSession = prewarmedSession as? LanguageModelSession,
                  prewarmSystemPrompt == systemPrompt
            else {
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

    #endif
}
