import Foundation

@MainActor
final class ModelDownloadManager {
    static let shared = ModelDownloadManager()

    struct Status: Codable {
        var state: String
        var progress: Double
        var error: String?
        var repoId: String
        var revision: String
        var updatedAt: TimeInterval
    }

    private enum Constants {
        static let appGroupID = "group.com.qoli.eisonAI"
        static let repoId = "lmstudio-community/Qwen3-0.6B-MLX-4bit"
        static let revision = "75429955681c1850a9c8723767fe4252da06eb57"

        static let requiredFiles: [String] = [
            "added_tokens.json",
            "config.json",
            "merges.txt",
            "model.safetensors",
            "model.safetensors.index.json",
            "special_tokens_map.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "vocab.json",
        ]
    }

    var onStatusChange: ((Status) -> Void)?

    private(set) var status: Status {
        didSet {
            persistStatus(status)
            onStatusChange?(status)
        }
    }

    private var downloadTask: Task<Void, Never>?

    private init() {
        self.status = Status(
            state: "notInstalled",
            progress: 0,
            error: nil,
            repoId: Constants.repoId,
            revision: Constants.revision,
            updatedAt: Date().timeIntervalSince1970
        )
    }

    func refreshStatus() async -> Status {
        if let stored = loadPersistedStatus() {
            status = stored
        }

        let fileReady = isModelFilesReady()
        if fileReady {
            status = Status(
                state: "ready",
                progress: 1,
                error: nil,
                repoId: Constants.repoId,
                revision: Constants.revision,
                updatedAt: Date().timeIntervalSince1970
            )
        } else if status.state == "ready" {
            status = Status(
                state: "notInstalled",
                progress: 0,
                error: nil,
                repoId: Constants.repoId,
                revision: Constants.revision,
                updatedAt: Date().timeIntervalSince1970
            )
        }

        return status
    }

    func startDownload() async throws {
        if downloadTask != nil {
            return
        }

        status = Status(
            state: "downloading",
            progress: 0,
            error: nil,
            repoId: Constants.repoId,
            revision: Constants.revision,
            updatedAt: Date().timeIntervalSince1970
        )

        downloadTask = Task {
            await performDownload()
        }

        await downloadTask?.value
        downloadTask = nil

        if status.state == "failed" {
            throw NSError(domain: "ModelDownload", code: 1, userInfo: [NSLocalizedDescriptionKey: status.error ?? "Download failed"])
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        status = Status(
            state: "notInstalled",
            progress: 0,
            error: nil,
            repoId: Constants.repoId,
            revision: Constants.revision,
            updatedAt: Date().timeIntervalSince1970
        )
    }

    private func performDownload() async {
        do {
            let sizeByPath = try await fetchRemoteFileSizes()
            let totalBytes: Int64 = max(sizeByPath.values.reduce(0, +), 1)
            let destinationDir = try modelDirectoryURL()
            try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

            var completedBytes: Int64 = 0

            for file in Constants.requiredFiles {
                try Task.checkCancellation()

                let destination = destinationDir.appendingPathComponent(file)
                let expected = max(sizeByPath[file] ?? 1, 1)

                let progressCallback: (Int64) -> Void = { [weak self] bytesWritten in
                    guard let self else { return }
                    let current = min(bytesWritten, expected)
                    let fraction = Double(completedBytes + current) / Double(totalBytes)
                    self.status = Status(
                        state: "downloading",
                        progress: fraction,
                        error: nil,
                        repoId: Constants.repoId,
                        revision: Constants.revision,
                        updatedAt: Date().timeIntervalSince1970
                    )
                }

                try await downloadFile(named: file, to: destination, onBytesWritten: progressCallback)
                completedBytes += expected

                status = Status(
                    state: "downloading",
                    progress: min(Double(completedBytes) / Double(totalBytes), 1),
                    error: nil,
                    repoId: Constants.repoId,
                    revision: Constants.revision,
                    updatedAt: Date().timeIntervalSince1970
                )
            }

            status = Status(
                state: "verifying",
                progress: 1,
                error: nil,
                repoId: Constants.repoId,
                revision: Constants.revision,
                updatedAt: Date().timeIntervalSince1970
            )

            if !isModelFilesReady() {
                throw NSError(domain: "ModelDownload", code: 2, userInfo: [NSLocalizedDescriptionKey: "Files missing after download"])
            }

            status = Status(
                state: "ready",
                progress: 1,
                error: nil,
                repoId: Constants.repoId,
                revision: Constants.revision,
                updatedAt: Date().timeIntervalSince1970
            )
        } catch is CancellationError {
            status = Status(
                state: "notInstalled",
                progress: 0,
                error: nil,
                repoId: Constants.repoId,
                revision: Constants.revision,
                updatedAt: Date().timeIntervalSince1970
            )
        } catch {
            status = Status(
                state: "failed",
                progress: status.progress,
                error: error.localizedDescription,
                repoId: Constants.repoId,
                revision: Constants.revision,
                updatedAt: Date().timeIntervalSince1970
            )
        }
    }

    private func fetchRemoteFileSizes() async throws -> [String: Int64] {
        var result: [String: Int64] = [:]

        for file in Constants.requiredFiles {
            let url = resolvedFileURL(file)
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            let (_, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse,
               let lengthHeader = http.value(forHTTPHeaderField: "Content-Length"),
               let length = Int64(lengthHeader),
               length > 0
            {
                result[file] = length
            } else {
                result[file] = 1
            }
        }

        return result
    }

    private func resolvedFileURL(_ file: String) -> URL {
        URL(string: "https://huggingface.co/\(Constants.repoId)/resolve/\(Constants.revision)/\(file)")!
    }

    private func downloadFile(named file: String, to destination: URL, onBytesWritten: @escaping (Int64) -> Void) async throws {
        let url = resolvedFileURL(file)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let delegate = DownloadDelegate(destination: destination, onBytesWritten: onBytesWritten)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let (_, response) = try await delegate.download(request, using: session)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(
                domain: "ModelDownload",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) downloading \(file)"]
            )
        }
        session.invalidateAndCancel()
    }

    private func isModelFilesReady() -> Bool {
        guard let destinationDir = try? modelDirectoryURL() else {
            return false
        }
        for file in Constants.requiredFiles {
            let url = destinationDir.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: url.path) {
                return false
            }
        }

        return true
    }

    private func modelDirectoryURL() throws -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupID) else {
            throw NSError(domain: "ModelDownload", code: 3, userInfo: [NSLocalizedDescriptionKey: "App Group container unavailable"])
        }

        return container
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Constants.repoId, isDirectory: true)
            .appendingPathComponent(Constants.revision, isDirectory: true)
    }

    private func statusFileURL() -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupID) else {
            return nil
        }

        return container
            .appendingPathComponent("Config", isDirectory: true)
            .appendingPathComponent("modelStatus.json", isDirectory: false)
    }

    private func persistStatus(_ status: Status) {
        guard let statusURL = statusFileURL() else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: statusURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(status)
            try data.write(to: statusURL, options: [.atomic])
        } catch {
            // ignore persistence errors
        }
    }

    private func loadPersistedStatus() -> Status? {
        guard let statusURL = statusFileURL(),
              let data = try? Data(contentsOf: statusURL),
              let stored = try? JSONDecoder().decode(Status.self, from: data),
              stored.repoId == Constants.repoId,
              stored.revision == Constants.revision else {
            return nil
        }
        return stored
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let onBytesWritten: (Int64) -> Void

    private var downloadedLocation: URL?
    private var response: URLResponse?
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var moveError: Error?

    init(destination: URL, onBytesWritten: @escaping (Int64) -> Void) {
        self.destination = destination
        self.onBytesWritten = onBytesWritten
    }

    func download(_ request: URLRequest, using session: URLSession) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = session.downloadTask(with: request)
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onBytesWritten(totalBytesWritten)
        _ = bytesWritten
        _ = totalBytesExpectedToWrite
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            downloadedLocation = destination
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        response = task.response

        if let moveError {
            continuation?.resume(throwing: moveError)
            continuation = nil
            return
        }

        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
            return
        }

        guard let location = downloadedLocation, let response else {
            continuation?.resume(throwing: URLError(.unknown))
            continuation = nil
            return
        }

        continuation?.resume(returning: (location, response))
        continuation = nil
    }
}
