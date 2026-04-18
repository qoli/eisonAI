import Foundation
import OSLog

#if canImport(EisonAIModelKit)
import EisonAIModelKit
#endif

#if canImport(AnyLanguageModel)
import AnyLanguageModel
#endif

#if canImport(MLXLMCommon)
import MLXLMCommon
#endif

#if canImport(Hub)
import Hub
#endif

#if canImport(MLXLMCommon) && canImport(Hub)
private struct MLXHubDownloaderBridge: Downloader {
    let upstream: HubApi

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        try await upstream.snapshot(
            from: id,
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: progressHandler
        )
    }
}

private enum MLXSimulatorDiagnostics {
    nonisolated(unsafe) private static let fileLock = NSLock()
    private static let logger = Logger(
        subsystem: "com.qoli.eisonAI",
        category: "MLXSimulatorDownload"
    )

    static var logFileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents
            .appending(path: "debug", directoryHint: .isDirectory)
            .appending(path: "mlx-simulator-download.log", directoryHint: .notDirectory)
    }

    static func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        append(level: "NOTICE", message: message)
    }

    static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        append(level: "WARN", message: message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append(level: "ERROR", message: message)
    }

    private static func append(level: String, message: String) {
        let line = "\(Date().ISO8601Format()) [\(level)] \(message)\n"
        fileLock.lock()
        defer { fileLock.unlock() }

        do {
            let directory = logFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                try line.write(to: logFileURL, atomically: true, encoding: .utf8)
                return
            }

            let handle = try FileHandle(forWritingTo: logFileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            logger.error("Failed to append diagnostics log: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct MLXSimulatorDownloadState: Equatable {
    let repoFileCount: Int
    let repoHasWeightFile: Bool
    let repoFiles: [String]
    let lockCount: Int
    let tempFileCount: Int
    let largestTempFileName: String?
    let largestTempFileSize: Int64?
    let largestTempFileModificationTime: TimeInterval?

    var summary: String {
        let repoFilesSummary = repoFiles.joined(separator: ",")
        let tempName = largestTempFileName ?? "none"
        let tempSize = largestTempFileSize.map(String.init) ?? "nil"
        let tempMTime = largestTempFileModificationTime.map { String(format: "%.3f", $0) } ?? "nil"
        return
            "repoFiles=\(repoFileCount) weightPresent=\(repoHasWeightFile) " +
            "lockCount=\(lockCount) tempFiles=\(tempFileCount) largestTemp=\(tempName) size=\(tempSize) mtime=\(tempMTime) " +
            "files=[\(repoFilesSummary)]"
    }
}
#endif

@MainActor
final class AnyLanguageModelClient {
    nonisolated private static let logger = Logger(
        subsystem: "com.qoli.eisonAI",
        category: "AnyLanguageModelClient"
    )

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

        #if canImport(EisonAIModelKit) || canImport(AnyLanguageModel)
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

    func prepareLocalModel(modelID: String) async throws {
        #if canImport(EisonAIModelKit)
            #if targetEnvironment(simulator)
                #if canImport(MLXLMCommon) && canImport(Hub)
                    try await prepareLocalModelAssetsForSimulator(modelID: modelID)
                #else
                    throw ClientError.invalidConfiguration("MLX download support is unavailable in this simulator target.")
                #endif
            #else
            let model = MLXLanguageModel(modelId: modelID)
            let session = LanguageModelSession(model: model, instructions: "Reply with OK.")
            _ = try await session.respond(
                to: "OK",
                options: GenerationOptions(
                    sampling: nil,
                    temperature: 0.1,
                    maximumResponseTokens: 1
                )
            )
            #endif
        #else
            throw ClientError.invalidConfiguration("MLX support is unavailable in this target.")
        #endif
    }

    func unloadLocalModel(modelID: String) async {
        #if canImport(EisonAIModelKit)
            #if targetEnvironment(simulator)
                Self.logger.notice(
                    "Skipping MLX cache unload on simulator for model '\(modelID, privacy: .public)'"
                )
                return
            #else
            let model = MLXLanguageModel(modelId: modelID)
            await model.removeFromCache()
            #endif
        #endif
    }

    func streamChat(
        systemPrompt: String,
        userPrompt: String,
        temperature: Double? = 0.2,
        maximumResponseTokens: Int? = 2048,
        backend: ExecutionBackend,
        byok: BYOKSettings? = nil,
        mlxModelID: String? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        let model = try buildModel(backend: backend, byok: byok, mlxModelID: mlxModelID)

        #if canImport(EisonAIModelKit) || canImport(AnyLanguageModel)
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

    #if canImport(EisonAIModelKit) || canImport(AnyLanguageModel)
        private func buildModel(
            backend: ExecutionBackend,
            byok: BYOKSettings?,
            mlxModelID: String?
        ) throws -> any AnyLanguageModel.LanguageModel {
            switch backend {
            case .mlx:
                #if canImport(EisonAIModelKit)
                    #if targetEnvironment(simulator)
                        throw ClientError.unavailable(
                            "MLX inference is unavailable in the simulator. Use a physical device for local MLX runs."
                        )
                    #else
                    let modelID = mlxModelID?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? MLXModelStore().loadSelectedModelID()
                    guard let modelID, !modelID.isEmpty else {
                        throw ClientError.invalidConfiguration("Select an MLX model first.")
                    }
                    return MLXLanguageModel(modelId: modelID)
                    #endif
                #else
                    throw ClientError.invalidConfiguration("MLX support is unavailable in this target.")
                #endif
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

        #if canImport(EisonAIModelKit) && canImport(MLXLMCommon) && canImport(Hub)
            private func prepareLocalModelAssetsForSimulator(modelID: String) async throws {
                MLXSimulatorDiagnostics.notice(
                    "begin resolve model=\(modelID) logFile=\(MLXSimulatorDiagnostics.logFileURL.path)"
                )

                let configuration = ModelConfiguration(id: modelID)
                let downloader = MLXHubDownloaderBridge(upstream: HubApi())
                let monitorTask = Task {
                    await monitorSimulatorModelDownload(modelID: modelID)
                }
                defer { monitorTask.cancel() }

                do {
                    let resolved = try await resolve(
                        configuration: configuration,
                        from: downloader,
                        useLatest: false
                    ) { progress in
                        let fraction = progress.totalUnitCount > 0
                            ? Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                            : 0
                        MLXSimulatorDiagnostics.notice(
                            "progress model=\(modelID) completed=\(progress.completedUnitCount) total=\(progress.totalUnitCount) fraction=\(String(format: "%.3f", fraction))"
                        )
                    }

                    let modelFileCount = try FileManager.default.contentsOfDirectory(
                        at: resolved.modelDirectory,
                        includingPropertiesForKeys: nil
                    ).count
                    let tokenizerFileCount = try FileManager.default.contentsOfDirectory(
                        at: resolved.tokenizerDirectory,
                        includingPropertiesForKeys: nil
                    ).count

                    let finalState = collectSimulatorDownloadState(modelID: modelID)
                    MLXSimulatorDiagnostics.notice(
                        """
                        resolved model=\(modelID) \
                        modelDir=\(resolved.modelDirectory.path) \
                        tokenizerDir=\(resolved.tokenizerDirectory.path) \
                        modelFiles=\(modelFileCount) \
                        tokenizerFiles=\(tokenizerFileCount) \
                        state={\(finalState.summary)}
                        """
                    )
                } catch {
                    let state = collectSimulatorDownloadState(modelID: modelID)
                    MLXSimulatorDiagnostics.error(
                        "resolve failed model=\(modelID) error=\(error.localizedDescription) state={\(state.summary)}"
                    )
                    throw error
                }
            }

            private func monitorSimulatorModelDownload(modelID: String) async {
                var lastState: MLXSimulatorDownloadState?
                var lastStallSignature: String?
                var unchangedTempSamples = 0

                while !Task.isCancelled {
                    let state = collectSimulatorDownloadState(modelID: modelID)
                    if state != lastState {
                        MLXSimulatorDiagnostics.notice("state model=\(modelID) \(state.summary)")
                        lastState = state
                    }

                    let tempSignature =
                        "\(state.largestTempFileName ?? "none"):" +
                        "\(state.largestTempFileSize ?? -1):" +
                        "\(state.largestTempFileModificationTime ?? -1)"

                    let hasObservableTransfer = state.lockCount > 0 || state.largestTempFileName != nil

                    if state.repoHasWeightFile || !hasObservableTransfer {
                        unchangedTempSamples = 0
                        lastStallSignature = nil
                    } else if tempSignature == lastStallSignature {
                        unchangedTempSamples += 1
                        if unchangedTempSamples == 5 {
                            MLXSimulatorDiagnostics.warning(
                                "download appears stalled model=\(modelID) \(state.summary)"
                            )
                        }
                    } else {
                        lastStallSignature = tempSignature
                        unchangedTempSamples = 0
                    }

                    try? await Task.sleep(for: .seconds(2))
                }
            }

            private func collectSimulatorDownloadState(modelID: String) -> MLXSimulatorDownloadState {
                let hub = HubApi()
                let repoURL = hub.localRepoLocation(Hub.Repo(id: modelID))
                let containerURL = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask)
                    .first?
                    .deletingLastPathComponent()
                    ?? repoURL
                let lockDirectory = containerURL
                    .appending(path: "Library/Caches/huggingface/hub/.locks", directoryHint: .isDirectory)
                    .appending(path: "models--\(modelID.replacingOccurrences(of: "/", with: "--"))", directoryHint: .isDirectory)
                    .appending(path: "blobs", directoryHint: .isDirectory)
                let tempDirectory = containerURL.appending(path: "tmp", directoryHint: .isDirectory)

                let repoFiles =
                    (try? FileManager.default.contentsOfDirectory(
                        at: repoURL,
                        includingPropertiesForKeys: nil
                    ).map(\.lastPathComponent).sorted()) ?? []
                let lockCount =
                    (try? FileManager.default.contentsOfDirectory(
                        at: lockDirectory,
                        includingPropertiesForKeys: nil
                    ).count) ?? 0

                let tempFiles =
                    (try? FileManager.default.contentsOfDirectory(
                        at: tempDirectory,
                        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
                    ).filter { $0.lastPathComponent.hasPrefix("CFNetworkDownload_") }) ?? []

                let largestTempFile = tempFiles.max { lhs, rhs in
                    let lhsSize =
                        (try? lhs.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap(Int64.init)
                        ?? 0
                    let rhsSize =
                        (try? rhs.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap(Int64.init)
                        ?? 0
                    return lhsSize < rhsSize
                }

                let largestTempValues = try? largestTempFile?.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey]
                )

                return MLXSimulatorDownloadState(
                    repoFileCount: repoFiles.count,
                    repoHasWeightFile: repoFiles.contains(where: { $0.hasSuffix(".safetensors") }),
                    repoFiles: repoFiles,
                    lockCount: lockCount,
                    tempFileCount: tempFiles.count,
                    largestTempFileName: largestTempFile?.lastPathComponent,
                    largestTempFileSize: largestTempValues?.fileSize.flatMap(Int64.init),
                    largestTempFileModificationTime: largestTempValues?.contentModificationDate?.timeIntervalSince1970
                )
            }
        #endif

    #endif
}
