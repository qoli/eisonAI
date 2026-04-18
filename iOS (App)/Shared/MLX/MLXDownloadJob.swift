import Foundation

struct MLXDownloadJob: Codable, Hashable, Identifiable {
    enum Source: String, Codable, Hashable {
        case catalog
        case custom
    }

    enum State: String, Codable, Hashable {
        case queued
        case running
        case finishing
        case completed
        case failed
        case cancelled

        var isActive: Bool {
            switch self {
            case .queued, .running, .finishing:
                return true
            case .completed, .failed, .cancelled:
                return false
            }
        }

        var displayLabel: String {
            switch self {
            case .queued:
                return "Queued"
            case .running:
                return "Downloading"
            case .finishing:
                return "Finalizing"
            case .completed:
                return "Completed"
            case .failed:
                return "Failed"
            case .cancelled:
                return "Cancelled"
            }
        }
    }

    let jobID: String
    let taskIdentifier: String
    let modelID: String
    let displayName: String
    let source: Source
    let autoSelectOnCompletion: Bool
    let requestedAt: Date
    var state: State
    var completedUnitCount: Int64
    var totalUnitCount: Int64
    var fractionCompleted: Double
    var errorMessage: String?
    var updatedAt: Date
    var catalogModel: MLXCatalogModel?

    var id: String { jobID }

    var isActive: Bool {
        state.isActive
    }

    var progressText: String {
        guard totalUnitCount > 0 || fractionCompleted > 0 else {
            return state.displayLabel
        }

        let percentValue = max(
            0,
            min(
                100,
                Int((fractionCompleted > 0 ? fractionCompleted : Double(completedUnitCount) / Double(max(totalUnitCount, 1))) * 100)
            )
        )
        return "\(state.displayLabel) \(percentValue)%"
    }

    init(
        jobID: String = UUID().uuidString,
        taskIdentifier: String,
        modelID: String,
        displayName: String,
        source: Source,
        state: State,
        completedUnitCount: Int64 = 0,
        totalUnitCount: Int64 = 0,
        fractionCompleted: Double = 0,
        errorMessage: String? = nil,
        autoSelectOnCompletion: Bool,
        requestedAt: Date = .now,
        updatedAt: Date = .now,
        catalogModel: MLXCatalogModel? = nil
    ) {
        self.jobID = jobID
        self.taskIdentifier = taskIdentifier
        self.modelID = modelID
        self.displayName = displayName
        self.source = source
        self.state = state
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.fractionCompleted = max(0, min(1, fractionCompleted))
        self.errorMessage = errorMessage
        self.autoSelectOnCompletion = autoSelectOnCompletion
        self.requestedAt = requestedAt
        self.updatedAt = updatedAt
        self.catalogModel = catalogModel
    }

    func updating(
        state: State? = nil,
        completedUnitCount: Int64? = nil,
        totalUnitCount: Int64? = nil,
        fractionCompleted: Double? = nil,
        errorMessage: String?? = nil,
        catalogModel: MLXCatalogModel?? = nil,
        updatedAt: Date = .now
    ) -> Self {
        Self(
            jobID: jobID,
            taskIdentifier: taskIdentifier,
            modelID: modelID,
            displayName: displayName,
            source: source,
            state: state ?? self.state,
            completedUnitCount: completedUnitCount ?? self.completedUnitCount,
            totalUnitCount: totalUnitCount ?? self.totalUnitCount,
            fractionCompleted: fractionCompleted ?? self.fractionCompleted,
            errorMessage: errorMessage ?? self.errorMessage,
            autoSelectOnCompletion: autoSelectOnCompletion,
            requestedAt: requestedAt,
            updatedAt: updatedAt,
            catalogModel: catalogModel ?? self.catalogModel
        )
    }
}

struct MLXDownloadJobStore {
    private let fileManager: FileManager
    private let baseDirectoryOverride: URL?

    init(
        fileManager: FileManager = .default,
        baseDirectoryOverride: URL? = nil
    ) {
        self.fileManager = fileManager
        self.baseDirectoryOverride = baseDirectoryOverride
    }

    func loadCurrentJob() -> MLXDownloadJob? {
        guard let fileURL = try? currentJobFileURL(),
              fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MLXDownloadJob.self, from: data)
    }

    func saveCurrentJob(_ job: MLXDownloadJob) throws {
        let fileURL = try currentJobFileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(job)
        try data.write(to: fileURL, options: [.atomic])
    }

    func clearCurrentJob() throws {
        let fileURL = try currentJobFileURL()
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func currentJobFileURL() throws -> URL {
        try directoryURL().appendingPathComponent(AppConfig.mlxDownloadCurrentJobFilename, isDirectory: false)
    }

    private func directoryURL() throws -> URL {
        let rootURL: URL
        if let baseDirectoryOverride {
            rootURL = baseDirectoryOverride
        } else {
            guard let containerURL = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: AppConfig.appGroupIdentifier
            ) else {
                throw NSError(
                    domain: "EisonAI.MLXDownloadJobStore",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "App Group container is unavailable."]
                )
            }
            rootURL = containerURL
        }

        var url = rootURL
        for component in AppConfig.mlxDownloadPathComponents {
            url.appendPathComponent(component, isDirectory: true)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
