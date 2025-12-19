import Foundation

#if canImport(MLCSwift)
import MLCSwift
#endif

@MainActor
final class MLCClient {
    enum ClientError: LocalizedError {
        case notAvailable

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "MLCSwift not integrated."
            }
        }
    }

    private(set) var loadedModelID: String?
    private var isLoaded = false

#if canImport(MLCSwift)
    private let engine = MLCEngine()
#endif

    func loadIfNeeded() async throws {
        guard !isLoaded else { return }

#if canImport(MLCSwift)
        let selection = try MLCModelLocator().resolveSelection()
        await engine.reload(modelPath: selection.modelPath, modelLib: selection.modelLib)
        isLoaded = true
        loadedModelID = selection.modelID
#else
        throw ClientError.notAvailable
#endif
    }

    func reset() async {
#if canImport(MLCSwift)
        await engine.reset()
#endif
    }

    func streamChat(systemPrompt: String, userPrompt: String) async throws -> AsyncThrowingStream<String, Error> {
#if canImport(MLCSwift)
        try await loadIfNeeded()
        await engine.reset()

        let stream = await engine.chat.completions.create(
            messages: [
                ChatCompletionMessage(role: .system, content: systemPrompt),
                ChatCompletionMessage(role: .user, content: userPrompt),
            ]
        )

        return AsyncThrowingStream { continuation in
            Task {
                for try await res in stream {
                    if Task.isCancelled { break }
                    if let delta = res.choices.first?.delta.content?.asText() {
                        continuation.yield(delta)
                    }
                }
                continuation.finish()
            }
        }
#else
        throw ClientError.notAvailable
#endif
    }
}

