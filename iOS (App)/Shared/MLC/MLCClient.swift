import Foundation

#if canImport(MLCSwift)
import MLCSwift
#endif

@MainActor
final class MLCClient {
    enum ClientError: LocalizedError {
        case notAvailable
        case disabledOnSimulator

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "MLCSwift not integrated."
            case .disabledOnSimulator:
                return "MLC is disabled on Simulator. Set EISONAI_ENABLE_MLC_SIMULATOR=1 to enable."
            }
        }
    }

    private(set) var loadedModelID: String?
    private var isLoaded = false
    private let enableSimulatorMLC: Bool

#if canImport(MLCSwift)
    private let engine = MLCEngine()
#endif

    init(enableSimulatorMLC: Bool? = nil) {
        if let override = enableSimulatorMLC {
            self.enableSimulatorMLC = override
        } else {
            self.enableSimulatorMLC = MLCClient.resolveSimulatorMLCOverride()
        }
    }

    func loadIfNeeded() async throws {
        guard !isLoaded else { return }
        guard enableSimulatorMLC else { throw ClientError.disabledOnSimulator }

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
        guard enableSimulatorMLC else { return }
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
                var responseCount = 0
                var deltaCount = 0
                var deltaCharCount = 0
                var lastChoiceDescription = ""
                var lastDeltaDescription = ""
                for try await res in stream {
                    responseCount += 1
                    if Task.isCancelled { break }
                    if let choice = res.choices.first {
                        lastChoiceDescription = String(describing: choice)
                        lastDeltaDescription = String(describing: choice.delta)
                    }
                    if let delta = res.choices.first?.delta.content?.asText() {
                        if !delta.isEmpty {
                            deltaCount += 1
                            deltaCharCount += delta.count
                        }
                        continuation.yield(delta)
                    }
                }
                #if DEBUG
                if deltaCount == 0 {
                    print("[MLC] streamChat produced no text delta responseCount=\(responseCount)")
                    if !lastChoiceDescription.isEmpty {
                        print("[MLC] lastChoice=\(lastChoiceDescription)")
                    }
                    if !lastDeltaDescription.isEmpty {
                        print("[MLC] lastDelta=\(lastDeltaDescription)")
                    }
                } else {
                    print("[MLC] streamChat deltaCount=\(deltaCount) deltaChars=\(deltaCharCount)")
                }
                #endif
                continuation.finish()
            }
        }
#else
        throw ClientError.notAvailable
#endif
    }

    private static func resolveSimulatorMLCOverride() -> Bool {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["EISONAI_ENABLE_MLC_SIMULATOR"] == "1"
        #else
        return true
        #endif
    }
}
