@preconcurrency import BackgroundTasks
import Combine
import Foundation
import OSLog

private protocol MLXDownloadTaskBridge: AnyObject, Sendable {
    var onExpiration: (() -> Void)? { get set }
    func setInitialProgress(totalUnitCount: Int64, completedUnitCount: Int64)
    func update(title: String, subtitle: String, totalUnitCount: Int64, completedUnitCount: Int64)
    func complete(success: Bool, title: String, subtitle: String, totalUnitCount: Int64, completedUnitCount: Int64)
}

@available(iOS 26.0, *)
private final class BGContinuedProcessingTaskBridge: MLXDownloadTaskBridge, @unchecked Sendable {
    private let task: BGContinuedProcessingTask

    init(task: BGContinuedProcessingTask) {
        self.task = task
    }

    var onExpiration: (() -> Void)? {
        get { nil }
        set { task.expirationHandler = newValue }
    }

    func setInitialProgress(totalUnitCount: Int64, completedUnitCount: Int64) {
        task.progress.totalUnitCount = max(totalUnitCount, 100)
        task.progress.completedUnitCount = completedUnitCount
    }

    func update(title: String, subtitle: String, totalUnitCount: Int64, completedUnitCount: Int64) {
        task.updateTitle(title, subtitle: subtitle)
        task.progress.totalUnitCount = max(totalUnitCount, 100)
        task.progress.completedUnitCount = completedUnitCount
    }

    func complete(success: Bool, title: String, subtitle: String, totalUnitCount: Int64, completedUnitCount: Int64) {
        update(title: title, subtitle: subtitle, totalUnitCount: totalUnitCount, completedUnitCount: completedUnitCount)
        task.setTaskCompleted(success: success)
    }
}

final class MLXDownloadCoordinator: ObservableObject {
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
    private let scheduler: BGTaskScheduler
    private let logger = Logger(subsystem: "com.qoli.eisonAI", category: "MLXDownloadCoordinator")

    private var activeTask: Task<Void, Never>?
    private var registeredTaskIdentifiers = Set<String>()
    private var pendingCancellationReason: String?
    private var lastPersistedProgressAt: Date = .distantPast

    init(
        jobStore: MLXDownloadJobStore = MLXDownloadJobStore(),
        modelStore: MLXModelStore = MLXModelStore(),
        catalogService: MLXModelCatalogService = MLXModelCatalogService(),
        scheduler: BGTaskScheduler = .shared
    ) {
        self.jobStore = jobStore
        self.modelStore = modelStore
        self.catalogService = catalogService
        self.scheduler = scheduler
        self.currentJob = jobStore.loadCurrentJob()
    }

    var hasActiveJob: Bool {
        currentJob?.isActive == true
    }

    func refreshState() {
        publish(jobStore.loadCurrentJob(), persist: false)
    }

    func startInstall(
        model: MLXCatalogModel,
        source: MLXDownloadJob.Source,
        autoSelect: Bool = true
    ) async throws {
        if let currentJob, currentJob.isActive {
            throw DownloadError.anotherJobInProgress(currentJob.modelID)
        }

        let taskIdentifier = "\(AppConfig.mlxDownloadTaskIdentifierPrefix).\(UUID().uuidString)"
        let job = MLXDownloadJob(
            taskIdentifier: taskIdentifier,
            modelID: model.id,
            displayName: model.displayName,
            source: source,
            state: .queued,
            autoSelectOnCompletion: autoSelect,
            catalogModel: model
        )

        publish(job, persist: true)

        if shouldUseContinuedProcessingTask {
            do {
                try registerTaskHandlerIfNeeded(for: taskIdentifier)
                if #available(iOS 26.0, *) {
                    try submitContinuedProcessingTask(for: job)
                }
                logger.notice("Submitted continued task for \(job.modelID, privacy: .public)")
                return
            } catch {
                logger.error(
                    "Failed to submit continued task for \(job.modelID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        startForegroundDownload(for: job)
    }

    func registerPersistedBackgroundTaskHandlerIfNeeded() {
        refreshState()
        guard shouldUseContinuedProcessingTask,
              let currentJob,
              currentJob.isActive
        else {
            return
        }

        do {
            try registerTaskHandlerIfNeeded(for: currentJob.taskIdentifier)
        } catch {
            logger.error(
                "Failed to register persisted continued task \(currentJob.taskIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private var shouldUseContinuedProcessingTask: Bool {
        #if targetEnvironment(simulator)
            return false
        #else
            if #available(iOS 26.0, *) {
                return true
            }
            return false
        #endif
    }

    private func startForegroundDownload(for job: MLXDownloadJob) {
        guard activeTask == nil else { return }
        pendingCancellationReason = nil
        activeTask = Task { [weak self] in
            await self?.runDownload(forJobID: job.jobID, taskBridge: nil)
        }
    }

    private func registerTaskHandlerIfNeeded(for taskIdentifier: String) throws {
        guard shouldUseContinuedProcessingTask else { return }
        guard !registeredTaskIdentifiers.contains(taskIdentifier) else { return }

        let success = scheduler.register(forTaskWithIdentifier: taskIdentifier, using: nil) { [weak self] task in
            guard let self else { return }
            if #available(iOS 26.0, *),
               let continuedTask = task as? BGContinuedProcessingTask
            {
                self.handleContinuedProcessingTask(continuedTask)
            }
        }

        guard success else {
            throw NSError(
                domain: "EisonAI.MLXDownloadCoordinator",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Background task identifier isn't permitted: \(taskIdentifier)"]
            )
        }

        registeredTaskIdentifiers.insert(taskIdentifier)
    }

    @available(iOS 26.0, *)
    private func submitContinuedProcessingTask(for job: MLXDownloadJob) throws {
        let request = BGContinuedProcessingTaskRequest(
            identifier: job.taskIdentifier,
            title: "Downloading MLX Model",
            subtitle: job.displayName
        )
        request.strategy = .queue
        try scheduler.submit(request)
    }

    @available(iOS 26.0, *)
    private func handleContinuedProcessingTask(_ task: BGContinuedProcessingTask) {
        let taskIdentifier = task.identifier
        guard let job = matchingJob(for: taskIdentifier) else {
            logger.error("No persisted MLX download job matches task \(taskIdentifier, privacy: .public)")
            task.setTaskCompleted(success: false)
            return
        }

        if activeTask != nil {
            logger.error("Ignoring duplicate continued task for \(taskIdentifier, privacy: .public)")
            task.setTaskCompleted(success: false)
            return
        }

        let taskBridge = BGContinuedProcessingTaskBridge(task: task)
        taskBridge.update(
            title: "Downloading MLX Model",
            subtitle: job.displayName,
            totalUnitCount: job.totalUnitCount,
            completedUnitCount: job.completedUnitCount
        )
        taskBridge.onExpiration = { [weak self] in
            self?.pendingCancellationReason = "Background download was cancelled by the system."
            self?.activeTask?.cancel()
        }

        activeTask = Task { [weak self] in
            await self?.runDownload(forJobID: job.jobID, taskBridge: taskBridge)
        }
    }

    private func matchingJob(for taskIdentifier: String) -> MLXDownloadJob? {
        if let currentJob, currentJob.taskIdentifier == taskIdentifier {
            return currentJob
        }

        guard let persisted = jobStore.loadCurrentJob(),
              persisted.taskIdentifier == taskIdentifier
        else {
            return nil
        }

        publish(persisted, persist: false)
        return persisted
    }

    private func runDownload(
        forJobID jobID: String,
        taskBridge: MLXDownloadTaskBridge?
    ) async {
        guard let initialJob = currentJobForID(jobID) else {
            taskBridge?.complete(
                success: false,
                title: "MLX Download Failed",
                subtitle: "Missing download state",
                totalUnitCount: 1,
                completedUnitCount: 0
            )
            await clearActiveTask()
            return
        }

        let runningJob = initialJob.updating(state: .running, errorMessage: .some(nil))
        publish(runningJob, persist: true)

        do {
            _ = try await AnyLanguageModelClient.downloadLocalModelAssets(modelID: runningJob.modelID) { [weak self] progress in
                self?.handleProgress(progress, forJobID: jobID, taskBridge: taskBridge)
            }
            try Task.checkCancellation()

            await finalizeSuccessfulDownload(forJobID: jobID, taskBridge: taskBridge)
        } catch is CancellationError {
            await cancelDownload(forJobID: jobID, taskBridge: taskBridge)
        } catch {
            await failDownload(
                forJobID: jobID,
                message: error.localizedDescription,
                taskBridge: taskBridge
            )
        }
    }

    private func handleProgress(
        _ progress: Progress,
        forJobID jobID: String,
        taskBridge: MLXDownloadTaskBridge?
    ) {
        guard let currentJob = currentJobForID(jobID) else { return }

        let totalUnitCount = max(progress.totalUnitCount, currentJob.totalUnitCount)
        let completedUnitCount = max(progress.completedUnitCount, currentJob.completedUnitCount)
        let fractionCompleted: Double
        if totalUnitCount > 0 {
            fractionCompleted = min(1, Double(completedUnitCount) / Double(totalUnitCount))
        } else {
            fractionCompleted = max(currentJob.fractionCompleted, progress.fractionCompleted)
        }

        let updatedJob = currentJob.updating(
            state: .running,
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            fractionCompleted: fractionCompleted,
            errorMessage: .some(nil)
        )
        publish(updatedJob, persist: true, throttleProgressPersistence: true)

        taskBridge?.update(
            title: "Downloading MLX Model",
            subtitle: updatedJob.progressText,
            totalUnitCount: totalUnitCount,
            completedUnitCount: completedUnitCount
        )
    }

    private func finalizeSuccessfulDownload(
        forJobID jobID: String,
        taskBridge: MLXDownloadTaskBridge?
    ) async {
        guard let currentJob = currentJobForID(jobID) else {
            taskBridge?.complete(
                success: false,
                title: "MLX Download Failed",
                subtitle: "Missing download state",
                totalUnitCount: 1,
                completedUnitCount: 0
            )
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
            taskBridge?.complete(
                success: true,
                title: "Downloaded MLX Model",
                subtitle: model.displayName,
                totalUnitCount: finishedTotal,
                completedUnitCount: finishedTotal
            )
            await clearActiveTask()
        } catch {
            await failDownload(
                forJobID: jobID,
                message: error.localizedDescription,
                taskBridge: taskBridge
            )
        }
    }

    private func resolveCatalogModel(for job: MLXDownloadJob) async throws -> MLXCatalogModel {
        if let catalogModel = job.catalogModel {
            return catalogModel
        }
        return try await catalogService.fetchModel(repoID: job.modelID)
    }

    private func cancelDownload(
        forJobID jobID: String,
        taskBridge: MLXDownloadTaskBridge?
    ) async {
        guard let currentJob = currentJobForID(jobID) else {
            taskBridge?.complete(
                success: false,
                title: "MLX Download Cancelled",
                subtitle: "Missing download state",
                totalUnitCount: 1,
                completedUnitCount: 0
            )
            await clearActiveTask()
            return
        }

        let message = pendingCancellationReason ?? "Download cancelled."
        let cancelledJob = currentJob.updating(
            state: .cancelled,
            errorMessage: .some(message)
        )
        publish(cancelledJob, persist: true)
        taskBridge?.complete(
            success: false,
            title: "MLX Download Cancelled",
            subtitle: currentJob.displayName,
            totalUnitCount: max(max(currentJob.totalUnitCount, currentJob.completedUnitCount), 1),
            completedUnitCount: currentJob.completedUnitCount
        )
        await clearActiveTask()
    }

    private func failDownload(
        forJobID jobID: String,
        message: String,
        taskBridge: MLXDownloadTaskBridge?
    ) async {
        guard let currentJob = currentJobForID(jobID) else {
            taskBridge?.complete(
                success: false,
                title: "MLX Download Failed",
                subtitle: "Missing download state",
                totalUnitCount: 1,
                completedUnitCount: 0
            )
            await clearActiveTask()
            return
        }

        let failedJob = currentJob.updating(
            state: .failed,
            errorMessage: .some(message)
        )
        publish(failedJob, persist: true)
        taskBridge?.complete(
            success: false,
            title: "MLX Download Failed",
            subtitle: currentJob.displayName,
            totalUnitCount: max(max(currentJob.totalUnitCount, currentJob.completedUnitCount), 1),
            completedUnitCount: currentJob.completedUnitCount
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
    }

    private func publish(
        _ job: MLXDownloadJob?,
        persist: Bool,
        throttleProgressPersistence: Bool = false
    ) {
        let apply = {
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
                self.logger.error("Failed to persist MLX download job: \(error.localizedDescription, privacy: .public)")
            }
        }

        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}
