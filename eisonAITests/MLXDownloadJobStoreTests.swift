import XCTest
@testable import eisonAI

final class MLXDownloadJobStoreTests: XCTestCase {
    func testStoreRoundTripAndClear() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = MLXDownloadJobStore(baseDirectoryOverride: directoryURL)

        let model = MLXCatalogModel(
            id: "mlx-community/Test-Model",
            pipelineTag: "text-generation",
            baseModel: "org/Test-Base",
            lastModified: Date(timeIntervalSince1970: 1234),
            estimatedParameterCount: 1_700_000_000,
            rawSafeTensorTotal: 4567
        )
        let job = MLXDownloadJob(
            taskIdentifier: "com.qoli.eisonAI.mlx-download.test",
            modelID: model.id,
            displayName: model.displayName,
            source: .catalog,
            state: .running,
            completedUnitCount: 3,
            totalUnitCount: 9,
            fractionCompleted: 1.0 / 3.0,
            autoSelectOnCompletion: true,
            catalogModel: model
        )

        try store.saveCurrentJob(job)
        let loaded = try XCTUnwrap(store.loadCurrentJob())

        XCTAssertEqual(loaded.jobID, job.jobID)
        XCTAssertEqual(loaded.taskIdentifier, job.taskIdentifier)
        XCTAssertEqual(loaded.modelID, job.modelID)
        XCTAssertEqual(loaded.state, .running)
        XCTAssertEqual(loaded.completedUnitCount, 3)
        XCTAssertEqual(loaded.totalUnitCount, 9)
        XCTAssertEqual(loaded.catalogModel, model)

        try store.clearCurrentJob()
        XCTAssertNil(store.loadCurrentJob())
    }

    func testJobStateActivityFlags() {
        XCTAssertTrue(MLXDownloadJob.State.queued.isActive)
        XCTAssertTrue(MLXDownloadJob.State.running.isActive)
        XCTAssertTrue(MLXDownloadJob.State.finishing.isActive)
        XCTAssertFalse(MLXDownloadJob.State.completed.isActive)
        XCTAssertFalse(MLXDownloadJob.State.failed.isActive)
        XCTAssertFalse(MLXDownloadJob.State.cancelled.isActive)
    }

    @MainActor
    func testCoordinatorRejectsSecondInstallWhenActiveJobExists() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = MLXDownloadJobStore(baseDirectoryOverride: directoryURL)
        let activeJob = MLXDownloadJob(
            taskIdentifier: "com.qoli.eisonAI.mlx-download.active",
            modelID: "mlx-community/Active-Model",
            displayName: "Active-Model",
            source: .catalog,
            state: .running,
            autoSelectOnCompletion: true
        )
        try store.saveCurrentJob(activeJob)

        let coordinator = MLXDownloadCoordinator(jobStore: store)
        let nextModel = MLXCatalogModel(
            id: "mlx-community/Next-Model",
            pipelineTag: "text-generation",
            baseModel: nil,
            lastModified: nil,
            estimatedParameterCount: 900_000_000,
            rawSafeTensorTotal: 1234
        )

        do {
            try await coordinator.startInstall(model: nextModel, source: .catalog)
            XCTFail("Expected active job guard to reject a second install.")
        } catch let error as MLXDownloadCoordinator.DownloadError {
            switch error {
            case let .anotherJobInProgress(modelID):
                XCTAssertEqual(modelID, activeJob.modelID)
            }
        }
    }
}
