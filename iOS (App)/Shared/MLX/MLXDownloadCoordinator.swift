import Combine
import Foundation
import OSLog

final class MLXDownloadCoordinator: ObservableObject {
    private enum ProgressRefreshSource: String {
        case callback
        case poll
    }

    private struct ProgressBaseline {
        let jobID: String
        let modelID: String
        let snapshotBytes: Int64
        let cacheBlobBytes: Int64

        init(job: MLXDownloadJob, assetProgress: AnyLanguageModelClient.LocalModelAssetProgress) {
            self.jobID = job.jobID
            self.modelID = job.modelID
            self.snapshotBytes = assetProgress.repoBytes
            self.cacheBlobBytes = assetProgress.cacheBlobBytes
        }

        var summary: String {
            "snapshotBytes=\(snapshotBytes) cacheBlobBytes=\(cacheBlobBytes)"
        }
    }

    private struct ProgressSample {
        let baseline: ProgressBaseline
        let assetProgress: AnyLanguageModelClient.LocalModelAssetProgress
        let materializedDelta: Int64
        let cacheDelta: Int64
        let observedRunBytes: Int64
        let callbackFraction: Double?
        let callbackEstimatedBytes: Int64?
        let liveBytes: Int64
        let phase: String

        var summary: String {
            let callbackBytes = callbackEstimatedBytes.map(String.init) ?? "nil"
            let callbackFractionDescription = callbackFraction.map { String(format: "%.3f", $0) } ?? "nil"
            return
                "phase=\(phase) liveBytes=\(liveBytes) observedRunBytes=\(observedRunBytes) " +
                "materializedBytes=\(assetProgress.repoBytes) materializedDelta=\(materializedDelta) " +
                "cacheBlobBytes=\(assetProgress.cacheBlobBytes) cacheDelta=\(cacheDelta) " +
                "callbackBytes=\(callbackBytes) callbackFraction=\(callbackFractionDescription) baseline={\(baseline.summary)}"
        }
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
    private var lastPublishedProgressAt: Date = .distantPast
    private var lastObservedCompletedUnitCount: Int64 = 0
    private var lastObservedDownloadedBytes: Int64 = 0
    private var activeProgressBaseline: ProgressBaseline?

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
        lastPublishedProgressAt = .distantPast
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
        establishProgressBaseline(for: runningJob)
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
        lastPublishedProgressAt = .distantPast
        lastObservedCompletedUnitCount = 0
        lastObservedDownloadedBytes = 0
        activeProgressBaseline = nil
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
        let progressSample = makeProgressSample(
            for: currentJob,
            assetProgress: assetProgress,
            callbackProgress: callbackProgress
        )

        let previousCompleted = currentJob.completedUnitCount
        let previousTotal = currentJob.totalUnitCount
        let previousFraction = currentJob.fractionCompleted
        let previousBytesPerSecond = currentJob.bytesPerSecond
        let effectiveLiveBytes = assetProgress.expectedBytes == nil
            ? progressSample.liveBytes
            : max(progressSample.liveBytes, currentJob.completedUnitCount)
        let deltaLiveBytes = effectiveLiveBytes - previousCompleted

        var totalUnitCount: Int64 = currentJob.expectedTotalBytes ?? assetProgress.expectedBytes ?? 0
        var completedUnitCount: Int64 = currentJob.completedUnitCount
        var fractionCompleted: Double = currentJob.fractionCompleted
        var bytesPerSecond: Double? = currentJob.bytesPerSecond
        var callbackReportedActivity = false

        if let callbackProgress {
            if assetProgress.expectedBytes == nil,
               let callbackFraction = progressSample.callbackFraction,
               callbackProgress.totalUnitCount > 0
            {
                fractionCompleted = max(currentJob.fractionCompleted, callbackFraction)
                totalUnitCount = callbackProgress.totalUnitCount
                completedUnitCount = max(currentJob.completedUnitCount, callbackProgress.completedUnitCount)
            }

            let reportedBytesPerSecond = callbackProgress.userInfo[.throughputKey] as? Double
            if let reportedBytesPerSecond, reportedBytesPerSecond > 0 {
                bytesPerSecond = reportedBytesPerSecond
            }
            callbackReportedActivity =
                (progressSample.callbackEstimatedBytes ?? 0) > 0 ||
                (progressSample.callbackFraction ?? 0) > 0 ||
                callbackProgress.completedUnitCount > 0 ||
                (reportedBytesPerSecond ?? 0) > 0
        }

        if let expectedBytes = assetProgress.expectedBytes, expectedBytes > 0 {
            totalUnitCount = expectedBytes
            let liveFraction = min(1, Double(effectiveLiveBytes) / Double(expectedBytes))
            if liveFraction.isFinite, liveFraction > fractionCompleted {
                fractionCompleted = liveFraction
                completedUnitCount = max(
                    currentJob.completedUnitCount,
                    min(expectedBytes, effectiveLiveBytes)
                )
            }
        }

        if totalUnitCount > 0 {
            completedUnitCount = max(0, min(completedUnitCount, totalUnitCount))
            fractionCompleted = min(1, max(0, fractionCompleted))
        }

        if effectiveLiveBytes > lastObservedDownloadedBytes ||
            completedUnitCount > lastObservedCompletedUnitCount ||
            callbackReportedActivity
        {
            lastProgressEventAt = .now
        }

        lastObservedDownloadedBytes = max(lastObservedDownloadedBytes, effectiveLiveBytes)
        lastObservedCompletedUnitCount = max(lastObservedCompletedUnitCount, completedUnitCount)
        let updatedExpectedTotalBytes =
            currentJob.expectedTotalBytes ??
            assetProgress.expectedBytes ??
            (totalUnitCount > 0 ? totalUnitCount : nil)

        let updatedJob = currentJob.updating(
            state: .running,
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            fractionCompleted: fractionCompleted,
            expectedTotalBytes: .some(updatedExpectedTotalBytes),
            bytesPerSecond: .some(bytesPerSecond),
            errorMessage: .some(nil)
        )

        if source == .poll {
            let tickDescription = pollTick.map(String.init) ?? "?"
            let expectedBytesDescription = assetProgress.expectedBytes.map(String.init) ?? "nil"
            let fractionDescription = String(format: "%.3f", fractionCompleted)
            logNotice(
                "MLX asset poll tick=\(tickDescription) jobID=\(currentJob.jobID) model=\(currentJob.modelID) expectedBytes=\(expectedBytesDescription) deltaLiveBytes=\(deltaLiveBytes) previousCompleted=\(previousCompleted) previousTotal=\(previousTotal) fraction=\(fractionDescription) progress={\(progressSample.summary)} assetBytes={\(assetProgress.summary)}"
            )
        }

        if shouldPublishProgressUpdate(
            source: source,
            updatedJob: updatedJob,
            previousCompleted: previousCompleted,
            previousTotal: previousTotal,
            previousFraction: previousFraction,
            previousBytesPerSecond: previousBytesPerSecond
        ) {
            publish(updatedJob, persist: true, throttleProgressPersistence: true)
        }

        if fractionCompleted >= 1 ||
            lastLoggedProgressFraction < 0 ||
            fractionCompleted - lastLoggedProgressFraction >= 0.05
        {
            lastLoggedProgressFraction = fractionCompleted
            logNotice(
                "MLX download progress source=\(source.rawValue) job={\(jobSummary(updatedJob))} progress={\(progressSample.summary)} assetBytes={\(assetProgress.summary)}"
            )
        }
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

    private func establishProgressBaseline(for job: MLXDownloadJob) {
        let assetProgress = observedAssetProgress(for: job)
        let baseline = ProgressBaseline(job: job, assetProgress: assetProgress)
        activeProgressBaseline = baseline
        let expectedBytesDescription = assetProgress.expectedBytes.map(String.init) ?? "nil"
        logNotice(
            "MLX download progress baseline jobID=\(job.jobID) model=\(job.modelID) expectedBytes=\(expectedBytesDescription) baseline={\(baseline.summary)} assetBytes={\(assetProgress.summary)}"
        )
    }

    private func progressBaseline(
        for job: MLXDownloadJob,
        assetProgress: AnyLanguageModelClient.LocalModelAssetProgress
    ) -> ProgressBaseline {
        if let activeProgressBaseline,
           activeProgressBaseline.jobID == job.jobID,
           activeProgressBaseline.modelID == job.modelID
        {
            return activeProgressBaseline
        }

        let baseline = ProgressBaseline(job: job, assetProgress: assetProgress)
        activeProgressBaseline = baseline
        logWarning(
            "Created missing MLX download progress baseline jobID=\(job.jobID) model=\(job.modelID) baseline={\(baseline.summary)} assetBytes={\(assetProgress.summary)}"
        )
        return baseline
    }

    private func makeProgressSample(
        for job: MLXDownloadJob,
        assetProgress: AnyLanguageModelClient.LocalModelAssetProgress,
        callbackProgress: Progress?
    ) -> ProgressSample {
        let baseline = progressBaseline(for: job, assetProgress: assetProgress)
        let materializedDelta = max(0, assetProgress.repoBytes - baseline.snapshotBytes)
        let cacheDelta = max(0, assetProgress.cacheBlobBytes - baseline.cacheBlobBytes)
        let observedRunBytes = max(materializedDelta, cacheDelta)
        let callbackFraction = normalizedCallbackFraction(callbackProgress)
        let callbackEstimatedBytes = callbackEstimatedBytes(
            fraction: callbackFraction,
            expectedBytes: assetProgress.expectedBytes
        )
        let liveBytes = max(observedRunBytes, callbackEstimatedBytes ?? 0)
        let phase = progressPhaseDescription(
            baseline: baseline,
            assetProgress: assetProgress,
            materializedDelta: materializedDelta,
            cacheDelta: cacheDelta,
            callbackEstimatedBytes: callbackEstimatedBytes,
            liveBytes: liveBytes
        )

        return ProgressSample(
            baseline: baseline,
            assetProgress: assetProgress,
            materializedDelta: materializedDelta,
            cacheDelta: cacheDelta,
            observedRunBytes: observedRunBytes,
            callbackFraction: callbackFraction,
            callbackEstimatedBytes: callbackEstimatedBytes,
            liveBytes: liveBytes,
            phase: phase
        )
    }

    private func normalizedCallbackFraction(_ progress: Progress?) -> Double? {
        guard let progress else { return nil }

        let directFraction = progress.fractionCompleted
        if directFraction.isFinite, directFraction > 0 {
            return min(1, max(0, directFraction))
        }

        guard progress.totalUnitCount > 0 else { return nil }
        let unitFraction = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
        guard unitFraction.isFinite, unitFraction > 0 else { return nil }
        return min(1, max(0, unitFraction))
    }

    private func callbackEstimatedBytes(fraction: Double?, expectedBytes: Int64?) -> Int64? {
        guard let fraction,
              let expectedBytes,
              expectedBytes > 0
        else {
            return nil
        }
        return Int64((Double(expectedBytes) * fraction).rounded(.down))
    }

    private func progressPhaseDescription(
        baseline: ProgressBaseline,
        assetProgress: AnyLanguageModelClient.LocalModelAssetProgress,
        materializedDelta: Int64,
        cacheDelta: Int64,
        callbackEstimatedBytes: Int64?,
        liveBytes: Int64
    ) -> String {
        let cacheWasWarm = assetProgress.expectedBytes.map { expectedBytes in
            expectedBytes > 0 && baseline.cacheBlobBytes >= expectedBytes
        } ?? false

        if liveBytes == 0 {
            return cacheWasWarm ? "cache-warm" : "starting"
        }
        if cacheDelta > materializedDelta {
            return "network-cache"
        }
        if materializedDelta > 0 {
            return cacheWasWarm ? "materializing-cache" : "materialized"
        }
        if callbackEstimatedBytes != nil {
            return cacheWasWarm ? "callback-cache" : "callback-transfer"
        }
        return "observing"
    }

    private func shouldPublishProgressUpdate(
        source: ProgressRefreshSource,
        updatedJob: MLXDownloadJob,
        previousCompleted: Int64,
        previousTotal: Int64,
        previousFraction: Double,
        previousBytesPerSecond: Double?
    ) -> Bool {
        let completedDelta = abs(updatedJob.completedUnitCount - previousCompleted)
        let fractionDelta = abs(updatedJob.fractionCompleted - previousFraction)
        let totalDidChange = updatedJob.totalUnitCount != previousTotal
        let speedChanged = speedDidChange(previous: previousBytesPerSecond, current: updatedJob.bytesPerSecond)

        guard completedDelta > 0 ||
            totalDidChange ||
            fractionDelta >= 0.001 ||
            speedChanged
        else {
            return false
        }

        guard source == .callback else {
            lastPublishedProgressAt = .now
            return true
        }

        let now = Date.now
        let elapsed = now.timeIntervalSince(lastPublishedProgressAt)

        guard totalDidChange || elapsed >= 1 else {
            return false
        }

        lastPublishedProgressAt = now
        return true
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
