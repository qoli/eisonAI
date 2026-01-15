import Foundation
import os

#if !targetEnvironment(simulator)
    #if canImport(MLCSwift)
        import MLCSwift
    #endif
#endif

@MainActor
final class MLCClient {
    enum ClientError: LocalizedError {
        case notAvailable
        case disabledOnSimulator
        case streamBusy

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "MLCSwift not integrated."
            case .disabledOnSimulator:
                return "MLC is disabled on Simulator/SwiftUI Preview."
            case .streamBusy:
                return "MLC engine is busy. Try again in a moment."
            }
        }
    }

    private(set) var loadedModelID: String?
    private var loadedSelection: MLCModelSelection?
    private var isLoaded = false
    private let enableSimulatorMLC: Bool
    private let logger = Logger(subsystem: "com.qoli.eisonAI", category: "MLCClient")
    private var activeStreamTask: Task<Void, Never>?
    private var activeStreamID: UUID?

    #if !targetEnvironment(simulator)
        #if canImport(MLCSwift)
            private let engine = MLCEngine()
        #endif
    #endif

    init(enableSimulatorMLC: Bool? = nil) {
        if let override = enableSimulatorMLC {
            self.enableSimulatorMLC = override
        } else {
            self.enableSimulatorMLC = MLCClient.resolveSimulatorMLCOverride()
        }
    }

    func loadIfNeeded(forceReload: Bool = false) async throws {
        guard !isLoaded || forceReload else {
            log("loadIfNeeded: already loaded model=\(loadedModelID ?? "nil")")
            return
        }
        guard enableSimulatorMLC else {
            log("loadIfNeeded: disabled on simulator")
            throw ClientError.disabledOnSimulator
        }

        #if !targetEnvironment(simulator)
            #if canImport(MLCSwift)
                if forceReload {
                    let finished = await cancelActiveStreamAndWait(timeoutSeconds: 2, reason: "reload")
                    if !finished {
                        log("loadIfNeeded: reload blocked, active stream still running")
                        throw ClientError.streamBusy
                    }
                }
                let selection: MLCModelSelection
                if let cached = loadedSelection {
                    selection = cached
                } else {
                    log("loadIfNeeded: resolving model selection")
                    selection = try MLCModelLocator().resolveSelection()
                    loadedSelection = selection
                }
                log("loadIfNeeded: loading modelID=\(selection.modelID) forceReload=\(forceReload)")
                await engine.reload(modelPath: selection.modelPath, modelLib: selection.modelLib)
                isLoaded = true
                loadedModelID = selection.modelID
                log("loadIfNeeded: loaded modelID=\(selection.modelID)")
            #else
                log("loadIfNeeded: MLCSwift not integrated")
                throw ClientError.notAvailable
            #endif
        #else
            log("loadIfNeeded: disabled on simulator (targetEnvironment)")
            throw ClientError.disabledOnSimulator
        #endif
    }

    func reset() async {
        guard enableSimulatorMLC else { return }
        #if !targetEnvironment(simulator)
            #if canImport(MLCSwift)
                let finished = await cancelActiveStreamAndWait(timeoutSeconds: 2, reason: "reset")
                if !finished {
                    log("reset skipped: active stream still running")
                    return
                }
                log("reset: engine reset")
                await engine.reset()
            #endif
        #endif
    }

    func streamChat(
        systemPrompt: String,
        userPrompt: String,
        forceReload: Bool = false
    ) async throws -> AsyncThrowingStream<String, Error> {
        #if !targetEnvironment(simulator)
            #if canImport(MLCSwift)
                log("streamChat: start")
                try await loadIfNeeded(forceReload: forceReload)
                try await finishActiveStreamIfNeeded(reason: "new stream")
                await engine.reset()

                let stream = await engine.chat.completions.create(
                    messages: [
                        ChatCompletionMessage(role: .system, content: systemPrompt),
                        ChatCompletionMessage(role: .user, content: userPrompt),
                    ]
                )

                return AsyncThrowingStream { continuation in
                    let streamID = UUID()
                    Task { @MainActor [weak self] in
                        self?.activeStreamID = streamID
                    }
                    let task = Task { [weak self] in
                        defer {
                            Task { @MainActor in
                                guard let self else { return }
                                if self.activeStreamID == streamID {
                                    self.activeStreamTask = nil
                                    self.activeStreamID = nil
                                }
                            }
                        }
                        var responseCount = 0
                        var deltaCount = 0
                        var deltaCharCount = 0
                        var lastChoiceDescription = ""
                        var lastDeltaDescription = ""
                        do {
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
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                    Task { @MainActor [weak self] in
                        self?.activeStreamTask = task
                    }
                    continuation.onTermination = { @Sendable _ in
                        task.cancel()
                    }
                }
            #else
                log("streamChat: MLCSwift not integrated")
                throw ClientError.notAvailable
            #endif
        #else
            log("streamChat: disabled on simulator (targetEnvironment)")
            throw ClientError.disabledOnSimulator
        #endif
    }

    private static func resolveSimulatorMLCOverride() -> Bool {
        #if targetEnvironment(simulator)
            return false
        #else
            return true
        #endif
    }

    private func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    private func finishActiveStreamIfNeeded(reason: String) async throws {
        guard activeStreamTask != nil else { return }
        log("finishActiveStreamIfNeeded: \(reason)")
        let finished = await cancelActiveStreamAndWait(timeoutSeconds: 2, reason: reason)
        guard finished else {
            log("finishActiveStreamIfNeeded: timed out")
            throw ClientError.streamBusy
        }
    }

    private func cancelActiveStreamAndWait(timeoutSeconds: Double, reason: String) async -> Bool {
        guard let task = activeStreamTask else { return true }
        log("cancelActiveStream: \(reason)")
        task.cancel()
        return await waitForActiveStreamCompletion(task: task, timeoutSeconds: timeoutSeconds)
    }

    private func waitForActiveStreamCompletion(task: Task<Void, Never>, timeoutSeconds: Double) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = await task.result
                return true
            }
            group.addTask {
                let nanos = UInt64(max(0, timeoutSeconds) * 1000000000)
                try? await Task.sleep(nanoseconds: nanos)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}
