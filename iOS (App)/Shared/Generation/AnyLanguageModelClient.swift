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

#if canImport(HuggingFace)
import HuggingFace
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
        logger.xcodeNotice(message)
        append(level: "NOTICE", message: message)
    }

    static func warning(_ message: String) {
        logger.xcodeWarning(message)
        append(level: "WARN", message: message)
    }

    static func error(_ message: String) {
        logger.xcodeError(message)
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
            logger.xcodeError("Failed to append diagnostics log: \(error.localizedDescription)")
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

private enum MLXDownloadDiagnostics {
    nonisolated(unsafe) private static let fileLock = NSLock()
    private static let logger = Logger(
        subsystem: "com.qoli.eisonAI",
        category: "MLXDownload"
    )

    static var logFileURL: URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConfig.appGroupIdentifier
        ) else {
            return nil
        }

        var url = containerURL
        for component in AppConfig.mlxDownloadPathComponents {
            url.appendPathComponent(component, isDirectory: true)
        }
        return url.appendingPathComponent("mlx-download.log", isDirectory: false)
    }

    static func notice(_ message: String) {
        logger.xcodeNotice(message)
        append(level: "NOTICE", message: message)
    }

    static func warning(_ message: String) {
        logger.xcodeWarning(message)
        append(level: "WARN", message: message)
    }

    static func error(_ message: String) {
        logger.xcodeError(message)
        append(level: "ERROR", message: message)
    }

    private static func append(level: String, message: String) {
        guard let logFileURL else { return }
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
            logger.xcodeError("Failed to append MLX download diagnostics log: \(error.localizedDescription)")
        }
    }
}

private final class MLXDownloadProgressLogState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = -1

    func shouldLog(fraction: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if fraction >= 1 || value < 0 || fraction - value >= 0.05 {
            value = fraction
            return true
        }
        return false
    }
}
#endif

@MainActor
final class AnyLanguageModelClient {
    struct DownloadedLocalModelAssets: Sendable {
        let modelDirectory: URL
        let tokenizerDirectory: URL
    }

    struct LocalModelAssetProgress: Sendable {
        let repoBytes: Int64
        let cacheBlobBytes: Int64
        let localBytes: Int64
        let expectedBytes: Int64?

        var fractionCompleted: Double? {
            guard let expectedBytes, expectedBytes > 0 else { return nil }
            return min(1, max(0, Double(localBytes) / Double(expectedBytes)))
        }

        var summary: String {
            let expected = expectedBytes.map(String.init) ?? "nil"
            return "repoBytes=\(repoBytes) cacheBlobBytes=\(cacheBlobBytes) localBytes=\(localBytes) expectedBytes=\(expected)"
        }
    }

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
                _ = try await downloadLocalModelAssets(modelID: modelID)
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

    func downloadLocalModelAssets(
        modelID: String,
        progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }
    ) async throws -> DownloadedLocalModelAssets {
        try await Self.downloadLocalModelAssets(
            modelID: modelID,
            progressHandler: progressHandler
        )
    }

    func hasDownloadedLocalModelAssets(modelID: String) -> Bool {
        Self.hasDownloadedLocalModelAssets(modelID: modelID)
    }

    nonisolated static func downloadLocalModelAssets(
        modelID: String,
        progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }
    ) async throws -> DownloadedLocalModelAssets {
        #if canImport(EisonAIModelKit) && canImport(MLXLMCommon) && canImport(Hub)
            MLXDownloadDiagnostics.notice(
                "download begin model=\(modelID) logFile=\(MLXDownloadDiagnostics.logFileURL?.path ?? "unavailable") state={\(describeDownloadedLocalModelAssets(modelID: modelID))}"
            )
            return try await resolveLocalModelAssets(
                modelID: modelID,
                progressHandler: progressHandler
            )
        #else
            throw ClientError.invalidConfiguration("MLX download support is unavailable in this target.")
        #endif
    }

    nonisolated static func hasDownloadedLocalModelAssets(modelID: String) -> Bool {
        #if canImport(Hub)
            let repoURL = HubApi().localRepoLocation(Hub.Repo(id: modelID))
            guard let repoFiles = try? FileManager.default.contentsOfDirectory(
                at: repoURL,
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent)
            else {
                return false
            }

            let hasWeightFile = repoFiles.contains(where: { $0.hasSuffix(".safetensors") })
            let hasConfigFile = repoFiles.contains("config.json")
            let hasTokenizer = repoFiles.contains("tokenizer.json")
            return hasWeightFile && hasConfigFile && hasTokenizer
        #else
            return false
        #endif
    }

    nonisolated static func describeDownloadedLocalModelAssets(modelID: String) -> String {
        #if canImport(Hub)
            let repoURL = HubApi().localRepoLocation(Hub.Repo(id: modelID))
            let repoFiles = (try? FileManager.default.contentsOfDirectory(
                at: repoURL,
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent).sorted()) ?? []

            let hasWeightFile = repoFiles.contains(where: { $0.hasSuffix(".safetensors") })
            let hasConfigFile = repoFiles.contains("config.json")
            let hasTokenizer = repoFiles.contains("tokenizer.json")
            let byteProgress = localModelAssetProgress(modelID: modelID)

            return "repo=\(repoURL.path) fileCount=\(repoFiles.count) hasWeight=\(hasWeightFile) hasConfig=\(hasConfigFile) hasTokenizer=\(hasTokenizer) bytes={\(byteProgress.summary)} files=[\(repoFiles.joined(separator: ","))]"
        #else
            return "hub-unavailable"
        #endif
    }

    nonisolated static func localModelAssetProgress(
        modelID: String,
        expectedBytes: Int64? = nil
    ) -> LocalModelAssetProgress {
        #if canImport(Hub) && canImport(HuggingFace)
            let hub = HubApi()
            let repoURL = hub.localRepoLocation(Hub.Repo(id: modelID))
            let repoBytes = trackedLocalModelAssetBytes(at: repoURL)
            let cacheBlobBytes = trackedHubCacheBlobBytes(modelID: modelID)
            return LocalModelAssetProgress(
                repoBytes: repoBytes,
                cacheBlobBytes: cacheBlobBytes,
                localBytes: max(repoBytes, cacheBlobBytes),
                expectedBytes: expectedBytes
            )
        #else
            return LocalModelAssetProgress(
                repoBytes: 0,
                cacheBlobBytes: 0,
                localBytes: 0,
                expectedBytes: expectedBytes
            )
        #endif
    }

    nonisolated static func inferredExpectedLocalModelBytes(modelID: String) -> Int64? {
        #if canImport(Hub)
            let repoURL = HubApi().localRepoLocation(Hub.Repo(id: modelID))
            let indexURL = repoURL.appendingPathComponent("model.safetensors.index.json", isDirectory: false)
            guard let data = try? Data(contentsOf: indexURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let metadata = json["metadata"] as? [String: Any]
            else {
                return nil
            }

            if let totalSize = metadata["total_size"] as? NSNumber {
                return totalSize.int64Value
            }
            if let totalSize = metadata["totalSize"] as? NSNumber {
                return totalSize.int64Value
            }
            return nil
        #else
            return nil
        #endif
    }

    nonisolated static func expectedLocalModelAssetBytes(
        modelID: String,
        fallbackWeightBytes: Int64? = nil
    ) async -> Int64? {
        #if canImport(Hub)
            let repo = Hub.Repo(id: modelID)
            if let remoteSum = try? await HubApi().getFileMetadata(
                from: repo,
                matching: trackedLocalModelAssetGlobs
            ).reduce(Int64(0), { partialResult, metadata in
                partialResult + Int64(max(metadata.size ?? 0, 0))
            }), remoteSum > 0 {
                return remoteSum
            }
        #endif

        if let fallbackWeightBytes, fallbackWeightBytes > 0 {
            return max(
                fallbackWeightBytes,
                fallbackWeightBytes + nonWeightLocalModelAssetBytes(modelID: modelID)
            )
        }

        if let inferred = inferredExpectedLocalModelBytes(modelID: modelID), inferred > 0 {
            return inferred
        }

        return nil
    }

    func unloadLocalModel(modelID: String) async {
        #if canImport(EisonAIModelKit)
            #if targetEnvironment(simulator)
                Self.logger.xcodeNotice("Skipping MLX cache unload on simulator for model '\(modelID)'")
                return
            #else
            let model = MLXLanguageModel(modelId: modelID)
            await model.removeFromCache()
            #endif
        #endif
    }

    func deleteLocalModel(modelID: String) async throws {
        await unloadLocalModel(modelID: modelID)
        try Self.deleteLocalModelArtifacts(modelID: modelID)
    }

    nonisolated static func deleteLocalModelArtifacts(modelID: String) throws {
        #if canImport(Hub)
            let fileManager = FileManager.default
            let hub = HubApi()
            let repoURL = hub.localRepoLocation(Hub.Repo(id: modelID))
            let repoCacheName = "models--\(modelID.replacingOccurrences(of: "/", with: "--"))"

            let containerURL = fileManager
                .urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .deletingLastPathComponent()

            var candidatePaths: [URL] = [repoURL]
            if let containerURL {
                let hubCacheRoot = containerURL
                    .appending(path: "Library/Caches/huggingface/hub", directoryHint: .isDirectory)
                candidatePaths.append(
                    hubCacheRoot.appending(path: repoCacheName, directoryHint: .isDirectory)
                )
                candidatePaths.append(
                    hubCacheRoot
                        .appending(path: ".locks", directoryHint: .isDirectory)
                        .appending(path: repoCacheName, directoryHint: .isDirectory)
                )
            }

            for url in candidatePaths {
                guard fileManager.fileExists(atPath: url.path) else { continue }
                try fileManager.removeItem(at: url)
            }

            MLXDownloadDiagnostics.notice(
                "deleted local model artifacts model=\(modelID) state={\(describeDownloadedLocalModelAssets(modelID: modelID))}"
            )
        #else
            throw ClientError.invalidConfiguration("MLX delete support is unavailable in this target.")
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
            nonisolated private static func resolveLocalModelAssets(
                modelID: String,
                progressHandler: @Sendable @escaping (Progress) -> Void
            ) async throws -> DownloadedLocalModelAssets {
                let configuration = ModelConfiguration(id: modelID)
                let downloader = MLXHubDownloaderBridge(upstream: HubApi())
                let progressLogState = MLXDownloadProgressLogState()
                #if targetEnvironment(simulator)
                    MLXSimulatorDiagnostics.notice(
                        "begin resolve model=\(modelID) logFile=\(MLXSimulatorDiagnostics.logFileURL.path)"
                    )
                let monitorTask = Task {
                    await monitorSimulatorModelDownload(modelID: modelID)
                }
                defer { monitorTask.cancel() }
                #endif

                do {
                    let resolved = try await resolve(
                        configuration: configuration,
                        from: downloader,
                        useLatest: false
                    ) { progress in
                        progressHandler(progress)
                        let fraction = progress.totalUnitCount > 0
                            ? Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                            : progress.fractionCompleted
                        if progressLogState.shouldLog(fraction: fraction) {
                            MLXDownloadDiagnostics.notice(
                                "download progress model=\(modelID) completed=\(progress.completedUnitCount) total=\(progress.totalUnitCount) fraction=\(String(format: "%.3f", fraction))"
                            )
                        }
                        #if targetEnvironment(simulator)
                        MLXSimulatorDiagnostics.notice(
                            "progress model=\(modelID) completed=\(progress.completedUnitCount) total=\(progress.totalUnitCount) fraction=\(String(format: "%.3f", fraction))"
                        )
                        #endif
                    }

                    #if targetEnvironment(simulator)
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
                    #endif
                    MLXDownloadDiagnostics.notice(
                        "download resolved model=\(modelID) modelDir=\(resolved.modelDirectory.path) tokenizerDir=\(resolved.tokenizerDirectory.path) state={\(describeDownloadedLocalModelAssets(modelID: modelID))}"
                    )
                    return DownloadedLocalModelAssets(
                        modelDirectory: resolved.modelDirectory,
                        tokenizerDirectory: resolved.tokenizerDirectory
                    )
                } catch {
                    MLXDownloadDiagnostics.error(
                        "download resolve failed model=\(modelID) error=\(error.localizedDescription) state={\(describeDownloadedLocalModelAssets(modelID: modelID))}"
                    )
                    #if targetEnvironment(simulator)
                    let state = collectSimulatorDownloadState(modelID: modelID)
                    MLXSimulatorDiagnostics.error(
                        "resolve failed model=\(modelID) error=\(error.localizedDescription) state={\(state.summary)}"
                    )
                    #endif
                    throw error
                }
            }

            nonisolated private static func monitorSimulatorModelDownload(modelID: String) async {
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
                                "download idle without observable temp-file growth model=\(modelID) \(state.summary)"
                            )
                        }
                    } else {
                        lastStallSignature = tempSignature
                        unchangedTempSamples = 0
                    }

                    try? await Task.sleep(for: .seconds(2))
                }
            }

            nonisolated private static func collectSimulatorDownloadState(modelID: String) -> MLXSimulatorDownloadState {
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

            nonisolated private static func directorySize(at url: URL) -> Int64 {
                let fileManager = FileManager.default
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                    return 0
                }

                if !isDirectory.boolValue {
                    return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap(Int64.init) ?? 0
                }

                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    return 0
                }

                var total: Int64 = 0
                for case let fileURL as URL in enumerator {
                    guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                          values.isRegularFile == true,
                          let fileSize = values.fileSize
                    else {
                        continue
                    }
                    total += Int64(fileSize)
                }
                return total
            }

            nonisolated private static let trackedLocalModelAssetGlobs: [String] = [
                "*.safetensors",
                "*.json",
                "*.txt",
                "*.model",
                "*.tiktoken",
                "*.jinja",
            ]

            nonisolated private static func isTrackedLocalModelAssetFile(_ url: URL) -> Bool {
                let filename = url.lastPathComponent.lowercased()
                return filename.hasSuffix(".safetensors") ||
                    filename.hasSuffix(".json") ||
                    filename.hasSuffix(".txt") ||
                    filename.hasSuffix(".model") ||
                    filename.hasSuffix(".tiktoken") ||
                    filename.hasSuffix(".jinja")
            }

            nonisolated private static func trackedLocalModelAssetBytes(at repoURL: URL) -> Int64 {
                let fileManager = FileManager.default
                guard let enumerator = fileManager.enumerator(
                    at: repoURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    return 0
                }

                var total: Int64 = 0
                for case let fileURL as URL in enumerator {
                    guard isTrackedLocalModelAssetFile(fileURL),
                          let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                          values.isRegularFile == true,
                          let fileSize = values.fileSize
                    else {
                        continue
                    }
                    total += Int64(fileSize)
                }
                return total
            }

            nonisolated private static func nonWeightLocalModelAssetBytes(modelID: String) -> Int64 {
                #if canImport(Hub)
                    let repoURL = HubApi().localRepoLocation(Hub.Repo(id: modelID))
                    let fileManager = FileManager.default
                    guard let enumerator = fileManager.enumerator(
                        at: repoURL,
                        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                        options: [.skipsHiddenFiles]
                    ) else {
                        return 0
                    }

                    var total: Int64 = 0
                    for case let fileURL as URL in enumerator {
                        let filename = fileURL.lastPathComponent.lowercased()
                        guard isTrackedLocalModelAssetFile(fileURL),
                              !filename.hasSuffix(".safetensors"),
                              let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                              values.isRegularFile == true,
                              let fileSize = values.fileSize
                        else {
                            continue
                        }
                        total += Int64(fileSize)
                    }
                    return total
                #else
                    return 0
                #endif
            }

            nonisolated private static func trackedHubCacheBlobBytes(modelID: String) -> Int64 {
                #if canImport(Hub) && canImport(HuggingFace)
                    let components = modelID.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
                    guard components.count == 2 else { return 0 }
                    let cache = HubCache.default
                    let blobsURL = cache.blobsDirectory(
                        repo: HuggingFace.Repo.ID(
                            namespace: String(components[0]),
                            name: String(components[1])
                        ),
                        kind: .model
                    )
                    return directorySize(at: blobsURL)
                #else
                    return 0
                #endif
            }
        #endif

    #endif
}
