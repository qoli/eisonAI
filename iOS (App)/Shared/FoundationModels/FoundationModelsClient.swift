import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

@MainActor
final class FoundationModelsClient {
    private var prewarmSystemPrompt: String?
    private var prewarmPromptPrefix: String?
    private var prewarmedSession: AnyObject?

    enum ClientError: LocalizedError {
        case notSupported
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .notSupported:
                return "Foundation Models requires iOS 26+ with Apple Intelligence."
            case let .unavailable(reason):
                return reason
            }
        }
    }

    static func ensureAvailable() throws {
        switch FoundationModelsAvailability.currentStatus() {
        case .available:
            return
        case .notSupported:
            throw ClientError.notSupported
        case let .unavailable(reason):
            throw ClientError.unavailable(reason)
        }
    }

    func prewarm(systemPrompt: String, promptPrefix: String? = nil) {
        guard FoundationModelsAvailability.currentStatus() == .available else { return }

        #if canImport(FoundationModels)
            guard #available(iOS 26.0, *) else { return }

            let trimmedPrefix = promptPrefix?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let prewarmedSession,
               prewarmSystemPrompt == systemPrompt,
               prewarmPromptPrefix == trimmedPrefix {
                return
            }

            let model = SystemLanguageModel(useCase: .general, guardrails: .default)
            let session = LanguageModelSession(model: model, instructions: Instructions(systemPrompt))
            session.prewarm(promptPrefix: Prompt(trimmedPrefix ?? ""))

            prewarmedSession = session
            prewarmSystemPrompt = systemPrompt
            prewarmPromptPrefix = trimmedPrefix
        #endif
    }

    func streamChat(
        systemPrompt: String,
        userPrompt: String,
        temperature: Double? = 0.4,
        maximumResponseTokens: Int? = 2048
    ) async throws -> AsyncThrowingStream<String, Error> {
        try Self.ensureAvailable()

        #if canImport(FoundationModels)
            guard #available(iOS 26.0, *) else {
                throw ClientError.notSupported
            }

            let options = GenerationOptions(
                sampling: nil,
                temperature: temperature,
                maximumResponseTokens: maximumResponseTokens
            )

            let session = takePrewarmedSession(systemPrompt: systemPrompt, userPrompt: userPrompt)
                ?? LanguageModelSession(
                    model: SystemLanguageModel(useCase: .general, guardrails: .default),
                    instructions: Instructions(systemPrompt)
                )
            let stream = session.streamResponse(to: Prompt(userPrompt), options: options)

            return AsyncThrowingStream { continuation in
                Task { @MainActor in
                    var previous = ""
                    do {
                        for try await partial in stream {
                            if Task.isCancelled { break }
                            let current = partial.content
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

    #if canImport(FoundationModels)
        @available(iOS 26.0, *)
        private func takePrewarmedSession(systemPrompt: String, userPrompt: String) -> LanguageModelSession? {
            guard let prewarmedSession = prewarmedSession as? LanguageModelSession,
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
    #endif
}
