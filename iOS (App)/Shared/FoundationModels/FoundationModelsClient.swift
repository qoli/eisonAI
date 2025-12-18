import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class FoundationModelsClient {
    enum ClientError: LocalizedError {
        case notSupported
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .notSupported:
                return "Foundation Models requires iOS 26+ with Apple Intelligence."
            case .unavailable(let reason):
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
        case .unavailable(let reason):
            throw ClientError.unavailable(reason)
        }
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

        let model = SystemLanguageModel(useCase: .general, guardrails: .default)
        let session = LanguageModelSession(model: model, instructions: Instructions(systemPrompt))
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
}

