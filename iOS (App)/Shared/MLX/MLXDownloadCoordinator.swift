import Combine
import Foundation
import OSLog

final class MLXDownloadCoordinator: ObservableObject {
    private enum ProgressRefreshSource: String {
        case callback
        case poll
    }

    enum DownloadError: LocalizedError {
        case anotherJobInProgress(String)

        var errorDescription: String? {
            switch self {
            case let .anotherJobInProgress(modelID):
                return "Another MLX download is already in progress: \(modelID)"
            }
        }
    }

    static let shared = MLXDownloadCoordinator()

    @Published private(set) var currentJob: MLXDownloadJob?

    private let jobStore: MLXDownloadJobStore
    private let modelStore: MLXModelStore
    private let catalogService: MLXModelCatalogService
    private let logger = Logger(subsystem: "com.qoli.eisonAI", category: "MLXDownloadCoordinator")

    private var activeTask: Task<Void, Never>?
    private var pendingCancellationReason: String?
    private var lastPersistedProgressAt: Date = .distantPast
    private var lastLoggedProgressFraction = -1.0
    private var lastProgressEventAt: Date = .distantPast
    private var lastObservedCompletedUnitCount: Int64 = 0
    private var lastObservedDownloadedBytes: Int64 = 0

    init(
        jobStore: MLXDownloadJobStore = MLXDownloadJobStore(),
        modelStore: MLXModelStore = MLXModelStore(),
        catalogService: MLXModelCatalogService = MLXModelCatalogService()
    ) {
        self.jobStore = jobStore
        self.modelStore = modelStore
        self.catalogService = catalogService
        self.currentJob = jobStore.loadCurrentJob()
    }

    var hasActiveJob: Bool {
        currentJob?.isActive == true
    }

    var currentJobLogSummary: String {
        jobSummary(currentJob)
    }

    func refreshState() {
        guard let persisted = jobStore.loadCurrentJob() else {
            publish(nil, persist: false)
            logNotice("Refreshed MLX download state: nil")
            return
        }

        if persisted.isActive, activeTask == nil {
            let recoveredJob = persisted.updating(
                state: .failed,
                errorMessage: .some("Download was interrupted. Retry the installation."),
                updatedAt: .now
            )
            publish(recoveredJob, persist: true)
            logWarning("Recovered interrupted foreground-only MLX download job={\(jobSummary(recoveredJob))}")
            return
        }

        publish(persisted, persist: false)
        logNotice("Refreshed MLX download state: \(jobSummary(persisted))")
    }

    func startInstall(
        model: MLXCatalogModel,
        source: MLXDownloadJob.Source,
        autoSelect: Bool = true
    ) async throws {
        if let currentJob, currentJob.isActive {
            throw DownloadError.anotherJobInProgress(currentJob.modelID)
        }

        let taskIdentifier = UUID().uuidString
        let job = MLXDownloadJob(
            taskIdentifier: taskIdentifier,
            modelID: model.id,
            displayName: model.displayName,
            source: source,
            state: .queued,
            expectedTotalBytes: model.rawSafeTensorTotal,
            autoSelectOnCompletion: autoSelect,
            catalogModel: model
        )

        await MainActor.run {
            applyPublishedJob(job, persist: true, throttleProgressPersistence: false)
            logNotice("Install requested source=\(source.rawValue) job={\(jobSummary(job))}")
            startForegroundDownload(for: job)
        }
    }

    func cancelCurrentJob() async {
        guard let currentJob else { return }

        logWarning("User requested cancellation for job={\(jobSummary(currentJob))}")
        pendingCancellationReason = "Cancelled by user."

        if let activeTask {
            activeTask.cancel()
            return
        }

        guard currentJob.isActive else { return }
        await cancelDownload(forJobID: currentJob.jobID)
    }

    func dismissCurrentJob() {
        guard let currentJob else { return }
        guard !currentJob.isActive else { return }

        logNotice("Dismissing terminal MLX download job={\(jobSummary(currentJob))}")
        publish(nil, persist: true)
    }

    private func startForegroundDownload(for job: MLXDownloadJob) {
        guard activeTask == nil else { return }
        pendingCancellationReason = nil
        lastLoggedProgressFraction = -1.0
        logNotice("Starting foreground MLX download job={\(jobSummary(job))}")
        activeTask = Task { [weak self] in
            await self?.runDownload(forJobID: job.jobID)
        }
    }

    private func runDownload(forJobID jobID: String) async {
        guard let initialJob = currentJobForID(jobID) else {
            await clearActiveTask()
            return
        }

        let runningJob = initialJob.updating(state: .running, errorMessage: .some(nil))
        publish(runningJob, persist: true)
        lastProgressEventAt = .now
        lastObservedCompletedUnitCount = runningJob.completedUnitCount
        lastObservedDownloadedBytes = 0
        let stallMonitorTask = makeStallMonitorTask(for: runningJob)
        let assetProgressTask = makeObservedProgressMonitorTask(for: runningJob)
        defer { stallMonitorTask.cancel() }
        defer { assetProgressTask.cancel() }
        logNotice(
            "MLX download run begin job={\(jobSummary(runningJob))} assetState={\(AnyLanguageModelClient.describeDownloadedLocalModelAssets(modelID: runningJob.modelID))}"
        )

        if runningJob.expectedTotalBytes == nil {
            Task { [weak self] in
                guard let self else { return }
                guard let expectedTotalBytes = await AnyLanguageModelClient.expectedLocalModelAssetBytes(
                    modelID: runningJob.modelID,
                    fallbackWeightBytes: runningJob.catalogModel?.rawSafeTensorTotal
                ),
                let currentRunningJob = self.currentJobForID(jobID),
                currentRunningJob.isActive
                else {
                    return
                }

                self.publish(
                    currentRunningJob.updating(
                        totalUnitCount: expectedTotalBytes,
                        expectedTotalBytes: .some(expectedTotalBytes)
                    ),
                    persist: true
                )
            }
        }

        do {
            _ = try await AnyLanguageModelClient.downloadLocalModelAssets(modelID: runningJob.modelID) { [weak self] progress in
                self?.handleProgress(forJobID: jobID, progress: progress)
            }
            try Task.checkCancellation()

            await finalizeSuccessfulDownload(forJobID: jobID)
        } catch is CancellationError {
            logWarning("MLX download cancelled via task cancellation jobID=\(jobID)")
            await cancelDownload(forJobID: jobID)
        } catch {
            logError(
                "MLX download run failed jobID=\(jobID) error=\(error.localizedDescription) assetState={\(AnyLanguageModelClient.describeDownloadedLocalModelAssets(modelID: runningJob.modelID))}"
            )
            await failDownload(forJobID: jobID, message: error.localizedDescription)
        }
    }

    private func handleProgress(forJobID jobID: String, progress: Progress) {
        guard let currentJob = currentJobForID(jobID) else { return }
        refreshObservedProgress(for: currentJob, source: .callback, callbackProgress: progress)
    }

    private func finalizeSuccessfulDownload(forJobID jobID: String) async {
        guard let currentJob = currentJobForID(jobID) else {
            await clearActiveTask()
            return
        }

        let finishedTotal = max(max(currentJob.totalUnitCount, currentJob.completedUnitCount), 1)
        let finishingJob = currentJob.updating(
            state: .finishing,
            completedUnitCount: finishedTotal,
            totalUnitCount: finishedTotal,
            fractionCompleted: 1,
            errorMessage: .some(nil)
        )
        publish(finishingJob, persist: true)
        logNotice(
            "MLX download entering finalize job={\(jobSummary(finishingJob))} assetState={\(AnyLanguageModelClient.describeDownloadedLocalModelAssets(modelID: finishingJob.modelID))}"
        )

        do {
            guard AnyLanguageModelClient.hasDownloadedLocalModelAssets(modelID: finishingJob.modelID) else {
                throw NSError(
                    domain: "EisonAI.MLXDownloadCoordinator",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Downloaded MLX model assets are incomplete."]
                )
            }

            let model = try await resolveCatalogModel(for: finishingJob)
            modelStore.upsertInstalledModel(model)
            if finishingJob.autoSelectOnCompletion {
                modelStore.saveSelectedModelID(model.id)
            }

            let completedJob = finishingJob.updating(
                state: .completed,
                completedUnitCount: finishedTotal,
                totalUnitCount: finishedTotal,
                fractionCompleted: 1,
                errorMessage: .some(nil),
                catalogModel: .some(model)
            )
            publish(completedJob, persist: true)
            logNotice(
                "MLX download completed job={\(jobSummary(completedJob))} selected=\(completedJob.autoSelectOnCompletion) assetState={\(AnyLanguageModelClient.describeDownloadedLocalModelAssets(modelID: completedJob.modelID))}"
            )
            await clearActiveTask()
        } catch {
            await failDownload(forJobID: jobID, message: error.localizedDescription)
        }
    }

    private func resolveCatalogModel(for job: MLXDownloadJob) async throws -> MLXCatalogModel {
        if let catalogModel = job.catalogModel {
            logNotice("Using persisted catalog metadata for \(job.modelID)")
            return catalogModel
        }
        logNotice("Fetching catalog metadata for custom repo \(job.modelID)")
        return try await catalogService.fetchModel(repoID: job.modelID)
    }

    private func cancelDownload(forJobID jobID: String) async {
        guard let currentJob = currentJobForID(jobID) else {
            await clearActiveTask()
            return
        }

        let message = pendingCancellationReason ?? "Download cancelled."
        let cancelledJob = currentJob.updating(
            state: .cancelled,
            errorMessage: .some(message)
        )
        publish(cancelledJob, persist: true)
        logWarning(
            "MLX download cancelled job={\(jobSummary(cancelledJob))} assetState={\(AnyLanguageModelClient.describeDownloadedLocalModelAssets(modelID: cancelledJob.modelID))}"
        )
        await clearActiveTask()
    }

    private func failDownload(forJobID jobID: String, message: String) async {
        guard let currentJob = currentJobForID(jobID) else {
            await clearActiveTask()
            return
        }

        let failedJob = currentJob.updating(
            state: .failed,
            errorMessage: .some(message)
        )
        publish(failedJob, persist: true)
        logError(
            "MLX download failed job={\(jobSummary(failedJob))} assetState={\(AnyLanguageModelClient.describeDownloadedLocalModelAssets(modelID: failedJob.modelID))}"
        )
        await clearActiveTask()
    }

    private func currentJobForID(_ jobID: String) -> MLXDownloadJob? {
        if let currentJob, currentJob.jobID == jobID {
            return currentJob
        }

        guard let persisted = jobStore.loadCurrentJob(),
              persisted.jobID == jobID
        else {
            return nil
        }

        publish(persisted, persist: false)
        return persisted
    }

    private func clearActiveTask() async {
        activeTask = nil
        pendingCancellationReason = nil
        lastLoggedProgressFraction = -1.0
        lastProgressEventAt = .distantPast
        lastObservedCompletedUnitCount = 0
        lastObservedDownloadedBytes = 0
        logNotice("Cleared active MLX download task state")
    }

    private func publish(
        _ job: MLXDownloadJob?,
        persist: Bool,
        throttleProgressPersistence: Bool = false
    ) {
        if Thread.isMainThread {
            applyPublishedJob(job, persist: persist, throttleProgressPersistence: throttleProgressPersistence)
        } else {
            DispatchQueue.main.async {
                self.applyPublishedJob(job, persist: persist, throttleProgressPersistence: throttleProgressPersistence)
            }
        }
    }

    private func applyPublishedJob(
        _ job: MLXDownloadJob?,
        persist: Bool,
        throttleProgressPersistence: Bool
    ) {
        let previousJob = self.currentJob
        self.currentJob = job

        guard persist else { return }

        do {
            if let job {
                if throttleProgressPersistence,
                   job.isActive,
                   Date.now.timeIntervalSince(self.lastPersistedProgressAt) < 1
                {
                    return
                }
                try self.jobStore.saveCurrentJob(job)
                self.lastPersistedProgressAt = .now
            } else {
                try self.jobStore.clearCurrentJob()
                self.lastPersistedProgressAt = .distantPast
            }
        } catch {
            self.logError("Failed to persist MLX download job: \(error.localizedDescription)")
        }

        if previousJob != job {
            self.logNotice(
                "Persisted MLX download state change previous={\(self.jobSummary(previousJob))} current={\(self.jobSummary(job))}"
            )
        }
    }

    private func jobSummary(_ job: MLXDownloadJob?) -> String {
        guard let job else { return "nil" }
        let error = job.errorMessage?.replacingOccurrences(of: "\n", with: " ") ?? "nil"
        return "id=\(job.jobID) task=\(job.taskIdentifier) model=\(job.modelID) state=\(job.state.rawValue) completed=\(job.completedUnitCount) total=\(job.totalUnitCount) fraction=\(String(format: "%.3f", job.fractionCompleted)) source=\(job.source.rawValue) autoSelect=\(job.autoSelectOnCompletion) error=\(error)"
    }

    private func makeStallMonitorTask(for job: MLXDownloadJob) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            self.logNotice("Started stall monitor for job={\(self.jobSummary(job))}")
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                guard let currentJob = self.currentJobForID(job.jobID), currentJob.isActive else {
                    self.logNotice("Stopping stall monitor because job is no longer active jobID=\(job.jobID)")
                    break
                }

                let idleSeconds = Date.now.timeIntervalSince(self.lastProgressEventAt)
                let assetState = AnyLanguageModelClient.describeDownloadedLocalModelAssets(modelID: currentJob.modelID)
                let hasObservedProgress = max(currentJob.completedUnitCount, self.lastObservedCompletedUnitCount) > 0 ||
                    self.lastObservedDownloadedBytes > 0
                if idleSeconds < 20 {
                    self.logNotice(
                        "MLX download heartbeat job={\(self.jobSummary(currentJob))} idleSeconds=\(String(format: "%.1f", idleSeconds)) lastCompleted=\(self.lastObservedCompletedUnitCount) lastObservedBytes=\(self.lastObservedDownloadedBytes) assetState={\(assetState)}"
                    )
                } else if !hasObservedProgress {
                    self.logNotice(
                        "MLX download waiting for first progress job={\(self.jobSummary(currentJob))} idleSeconds=\(String(format: "%.1f", idleSeconds)) lastCompleted=\(self.lastObservedCompletedUnitCount) lastObservedBytes=\(self.lastObservedDownloadedBytes) assetState={\(assetState)}"
                    )
                } else if idleSeconds >= 60 {
                    self.logWarning(
                        "MLX download idle after progress job={\(self.jobSummary(currentJob))} idleSeconds=\(String(format: "%.1f", idleSeconds)) lastCompleted=\(self.lastObservedCompletedUnitCount) lastObservedBytes=\(self.lastObservedDownloadedBytes) assetState={\(assetState)}"
                    )
                } else {
                    self.logNotice(
                        "MLX download idle after progress job={\(self.jobSummary(currentJob))} idleSeconds=\(String(format: "%.1f", idleSeconds)) lastCompleted=\(self.lastObservedCompletedUnitCount) lastObservedBytes=\(self.lastObservedDownloadedBytes) assetState={\(assetState)}"
                    )
                }
            }
        }
    }

    private func makeObservedProgressMonitorTask(for job: MLXDownloadJob) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            self.logNotice("Started asset progress monitor for job={\(self.jobSummary(job))}")
            var tick: Int = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                guard let currentJob = self.currentJobForID(job.jobID), currentJob.isActive else {
                    break
                }
                tick += 1
                self.refreshObservedProgress(for: currentJob, source: .poll, pollTick: tick)
            }
        }
    }

    private func refreshObservedProgress(
        for currentJob: MLXDownloadJob,
        source: ProgressRefreshSource,
        pollTick: Int? = nil,
        callbackProgress: Progress? = nil
    ) {
        let assetProgress = observedAssetProgress(for: currentJob)
        let observedDownloadedBytesForProgress = assetProgress.localBytes

        let previousCompleted = currentJob.completedUnitCount
        let previousTotal = currentJob.totalUnitCount
        let previousFraction = currentJob.fractionCompleted
        let previousBytesPerSecond = currentJob.bytesPerSecond
        let deltaObservedBytes = observedDownloadedBytesForProgress - previousCompleted

        var totalUnitCount: Int64 = currentJob.expectedTotalBytes ?? 0
        var completedUnitCount: Int64 = currentJob.completedUnitCount
        var fractionCompleted: Double = currentJob.fractionCompleted
        var bytesPerSecond: Double? = source == .poll ? nil : currentJob.bytesPerSecond
        var callbackReportedActivity = false

        if let callbackProgress {
            let callbackFraction: Double = {
                if callbackProgress.totalUnitCount > 0 {
                    return Double(callbackProgress.completedUnitCount) / Double(callbackProgress.totalUnitCount)
                }
                return callbackProgress.fractionCompleted
            }()
            let callbackIsByteProgress = isByteProgress(
                callbackProgress,
                expectedBytes: assetProgress.expectedBytes
            )

            if callbackFraction.isFinite, callbackFraction > 0 {
                if let expectedBytes = assetProgress.expectedBytes, expectedBytes > 0, callbackIsByteProgress {
                    fractionCompleted = max(currentJob.fractionCompleted, min(1, callbackFraction))
                    totalUnitCount = expectedBytes
                    completedUnitCount = max(
                        currentJob.completedUnitCount,
                        min(expectedBytes, Int64((Double(expectedBytes) * fractionCompleted).rounded(.down)))
                    )
                } else if assetProgress.expectedBytes == nil, callbackProgress.totalUnitCount > 0 {
                    fractionCompleted = max(currentJob.fractionCompleted, min(1, callbackFraction))
                    totalUnitCount = callbackProgress.totalUnitCount
                    completedUnitCount = max(currentJob.completedUnitCount, callbackProgress.completedUnitCount)
                }
            }

            bytesPerSecond = callbackProgress.userInfo[.throughputKey] as? Double
            callbackReportedActivity = callbackProgress.completedUnitCount > 0 || (bytesPerSecond ?? 0) > 0
        }

        if let expectedBytes = assetProgress.expectedBytes, expectedBytes > 0 {
            let observedFraction = min(1, Double(observedDownloadedBytesForProgress) / Double(expectedBytes))
            if observedFraction.isFinite {
                if totalUnitCount <= 0 {
                    totalUnitCount = expectedBytes
                }
                if observedFraction > fractionCompleted {
                    fractionCompleted = observedFraction
                    completedUnitCount = min(expectedBytes, observedDownloadedBytesForProgress)
                }
            }
        }

        if observedDownloadedBytesForProgress > lastObservedDownloadedBytes ||
            completedUnitCount > lastObservedCompletedUnitCount ||
            callbackReportedActivity
        {
            lastProgressEventAt = .now
        }

        lastObservedDownloadedBytes = max(lastObservedDownloadedBytes, observedDownloadedBytesForProgress)
        lastObservedCompletedUnitCount = max(lastObservedCompletedUnitCount, completedUnitCount)

        let updatedJob = currentJob.updating(
            state: .running,
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            fractionCompleted: fractionCompleted,
            expectedTotalBytes: .some(
                source == .callback
                    ? currentJob.expectedTotalBytes
                    : (totalUnitCount > 0 ? totalUnitCount : currentJob.expectedTotalBytes)
            ),
            bytesPerSecond: .some(bytesPerSecond),
            errorMessage: .some(nil)
        )

        if source == .poll {
            let tickDescription = pollTick.map(String.init) ?? "?"
            let expectedBytesDescription = assetProgress.expectedBytes.map(String.init) ?? "nil"
            let fractionDescription = String(format: "%.3f", fractionCompleted)
            logNotice(
                "MLX asset poll tick=\(tickDescription) jobID=\(currentJob.jobID) model=\(currentJob.modelID) localBytes=\(observedDownloadedBytesForProgress) expectedBytes=\(expectedBytesDescription) deltaBytes=\(deltaObservedBytes) previousCompleted=\(previousCompleted) previousTotal=\(previousTotal) fraction=\(fractionDescription) assetBytes={\(assetProgress.summary)}"
            )
        }

        if updatedJob.completedUnitCount != previousCompleted ||
            updatedJob.totalUnitCount != previousTotal ||
            abs(updatedJob.fractionCompleted - previousFraction) >= 0.001 ||
            speedDidChange(previous: previousBytesPerSecond, current: updatedJob.bytesPerSecond)
        {
            publish(updatedJob, persist: true, throttleProgressPersistence: true)
        }

        if fractionCompleted >= 1 ||
            lastLoggedProgressFraction < 0 ||
            fractionCompleted - lastLoggedProgressFraction >= 0.05
        {
            lastLoggedProgressFraction = fractionCompleted
            logNotice(
                "MLX download progress source=\(source.rawValue) job={\(jobSummary(updatedJob))} assetBytes={\(assetProgress.summary)} progressObservedBytes=\(observedDownloadedBytesForProgress)"
            )
        }
    }

    private func isByteProgress(_ progress: Progress, expectedBytes: Int64?) -> Bool {
        guard progress.totalUnitCount > 0 else { return false }
        guard let expectedBytes, expectedBytes > 0 else { return true }

        if progress.totalUnitCount == expectedBytes {
            return true
        }

        let tolerance = max(Int64(1_048_576), expectedBytes / 100)
        if abs(progress.totalUnitCount - expectedBytes) <= tolerance {
            return true
        }

        return progress.totalUnitCount >= 1_048_576
    }

    private func observedAssetProgress(for job: MLXDownloadJob) -> AnyLanguageModelClient.LocalModelAssetProgress {
        let expectedBytes = expectedDownloadBytes(for: job)
        return AnyLanguageModelClient.localModelAssetProgress(
            modelID: job.modelID,
            expectedBytes: expectedBytes
        )
    }

    private func expectedDownloadBytes(for job: MLXDownloadJob) -> Int64? {
        if let expectedTotalBytes = job.expectedTotalBytes, expectedTotalBytes > 0 {
            return expectedTotalBytes
        }
        if let rawSafeTensorTotal = job.catalogModel?.rawSafeTensorTotal, rawSafeTensorTotal > 0 {
            return rawSafeTensorTotal
        }
        if let inferred = AnyLanguageModelClient.inferredExpectedLocalModelBytes(modelID: job.modelID), inferred > 0 {
            return inferred
        }
        return nil
    }

    private func logNotice(_ message: String) {
        logger.xcodeNotice(message)
    }

    private func logWarning(_ message: String) {
        logger.xcodeWarning(message)
    }

    private func logError(_ message: String) {
        logger.xcodeError(message)
    }

    private func speedDidChange(previous: Double?, current: Double?) -> Bool {
        switch (previous, current) {
        case (nil, nil):
            return false
        case (.some, nil), (nil, .some):
            return true
        case let (.some(previous), .some(current)):
            return abs(previous - current) >= 1
        }
    }
}
