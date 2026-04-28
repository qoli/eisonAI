import Foundation
import Hub

struct Configuration {
    var modelID = "mlx-community/Qwen3.5-4B-MLX-4bit"
    var revision = "main"
    var patterns = [
        "*.safetensors",
        "*.json",
        "*.txt",
        "*.model",
        "*.tiktoken",
        "*.jinja",
    ]
    var downloadBase = URL(fileURLWithPath: "/tmp/eisonAI-mlx-download-probe", isDirectory: true)
    var pollInterval: TimeInterval = 1
    var callbackThrottle: TimeInterval = 1
    var clearFirst = false
    var metadataOnly = false
}

enum ProbeError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidValue(String)
    case helpRequested

    var description: String {
        switch self {
        case let .missingValue(flag):
            return "Missing value for \(flag)"
        case let .invalidValue(value):
            return "Invalid value: \(value)"
        case .helpRequested:
            return usage
        }
    }
}

let usage = """
Usage:
  swift run mlx-download-probe [options]

Options:
  --model <repo-id>        Hugging Face model repo. Default: mlx-community/Qwen3.5-4B-MLX-4bit
  --revision <revision>   Git revision. Default: main
  --pattern <glob>        File glob to download. Repeatable. Defaults to app MLX asset globs.
  --all                   Download all files in the snapshot.
  --download-base <path>  Snapshot output root. Default: /tmp/eisonAI-mlx-download-probe
  --poll <seconds>        Local byte polling interval. Default: 1
  --throttle <seconds>    Callback print throttle. Default: 1
  --clear                 Remove the model snapshot under download-base before starting.
  --metadata-only         Resolve metadata and print expected bytes without downloading.
  --help                  Show this help.

Example:
  swift run mlx-download-probe --clear --model mlx-community/Qwen3.5-4B-MLX-4bit
"""

@main
struct MLXDownloadProbe {
    static func main() async {
        do {
            let config = try parseArguments(Array(CommandLine.arguments.dropFirst()))
            try await run(config)
        } catch ProbeError.helpRequested {
            print(usage)
        } catch {
            fputs("error: \(error)\n\n\(usage)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run(_ config: Configuration) async throws {
        let hub = HubApi(downloadBase: config.downloadBase)
        let repo = HubApi.Repo(id: config.modelID)
        let repoURL = hub.localRepoLocation(repo)
        let fileManager = FileManager.default

        if config.clearFirst, fileManager.fileExists(atPath: repoURL.path) {
            try fileManager.removeItem(at: repoURL)
        }
        try fileManager.createDirectory(at: config.downloadBase, withIntermediateDirectories: true)

        print("model=\(config.modelID)")
        print("revision=\(config.revision)")
        print("patterns=\(config.patterns.isEmpty ? "[all]" : config.patterns.joined(separator: ","))")
        print("downloadBase=\(config.downloadBase.path)")
        print("repoPath=\(repoURL.path)")
        print("packageGraph=swift-transformers local -> swift-huggingface dependency from its Package.swift")

        let metadata = try await resolveMetadata(
            hub: hub,
            modelID: config.modelID,
            revision: config.revision,
            patterns: config.patterns
        )
        print("remoteFiles=\(metadata.count)")
        if let expectedBytes = metadata.expectedBytes {
            print("remoteExpectedBytes=\(formatBytes(expectedBytes)) (\(expectedBytes))")
        } else {
            print("remoteExpectedBytes=unknown")
        }

        if config.metadataOnly {
            return
        }

        let reporter = ProgressReporter(
            repoURL: repoURL,
            modelID: config.modelID,
            expectedBytes: metadata.expectedBytes,
            callbackThrottle: config.callbackThrottle
        )

        let pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(config.pollInterval * 1000)))
                reporter.poll()
            }
        }
        defer { pollTask.cancel() }

        let startedAt = Date()
        reporter.printHeader()
        let resultURL = try await hub.snapshot(
            from: config.modelID,
            revision: config.revision,
            matching: config.patterns
        ) { progress, speed in
            reporter.callback(progress: progress, speed: speed)
        }

        reporter.finish(resultURL: resultURL, elapsed: Date().timeIntervalSince(startedAt))
    }

    private static func resolveMetadata(
        hub: HubApi,
        modelID: String,
        revision: String,
        patterns: [String]
    ) async throws -> (count: Int, expectedBytes: Int64?) {
        let metadata = try await hub.getFileMetadata(
            from: modelID,
            revision: revision,
            matching: patterns
        )
        let expectedBytes = metadata.reduce(Int64(0)) { partial, item in
            partial + Int64(max(item.size ?? 0, 0))
        }
        return (metadata.count, expectedBytes > 0 ? expectedBytes : nil)
    }
}

final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private let repoURL: URL
    private let modelID: String
    private let expectedBytes: Int64?
    private let callbackThrottle: TimeInterval
    private let startedAt = Date()
    private var lastCallbackPrintedAt = Date.distantPast
    private var lastPollBytes: Int64 = 0

    init(repoURL: URL, modelID: String, expectedBytes: Int64?, callbackThrottle: TimeInterval) {
        self.repoURL = repoURL
        self.modelID = modelID
        self.expectedBytes = expectedBytes
        self.callbackThrottle = callbackThrottle
    }

    func printHeader() {
        print("time source callback localBytes expectedBytes localPercent callbackUnits callbackFraction speed")
    }

    func callback(progress: Progress, speed: Double?) {
        lock.lock()
        let now = Date()
        guard now.timeIntervalSince(lastCallbackPrintedAt) >= callbackThrottle ||
            progress.fractionCompleted >= 1
        else {
            lock.unlock()
            return
        }
        lastCallbackPrintedAt = now
        let localBytes = localObservedBytes()
        printLine(source: "callback", progress: progress, localBytes: localBytes, speed: speed)
        lock.unlock()
    }

    func poll() {
        lock.lock()
        let localBytes = localObservedBytes()
        guard localBytes != lastPollBytes else {
            lock.unlock()
            return
        }
        lastPollBytes = localBytes
        printLine(source: "poll", progress: nil, localBytes: localBytes, speed: nil)
        lock.unlock()
    }

    func finish(resultURL: URL, elapsed: TimeInterval) {
        lock.lock()
        let localBytes = localObservedBytes()
        let averageSpeed = elapsed > 0 ? Double(localBytes) / elapsed : 0
        printLine(source: "finish", progress: nil, localBytes: localBytes, speed: averageSpeed)
        print("result=\(resultURL.path)")
        print("elapsed=\(String(format: "%.2f", elapsed))s")
        print("averageSpeed=\(formatBytes(Int64(averageSpeed)))/s")
        print("finalBytes=\(formatBytes(localBytes)) (\(localBytes))")
        lock.unlock()
    }

    private func printLine(source: String, progress: Progress?, localBytes: Int64, speed: Double?) {
        let elapsed = Date().timeIntervalSince(startedAt)
        let localPercent = expectedBytes.map { expected -> String in
            guard expected > 0 else { return "n/a" }
            return String(format: "%.3f", min(1, Double(localBytes) / Double(expected)) * 100)
        } ?? "n/a"
        let callbackUnits: String
        let callbackFraction: String
        if let progress {
            callbackUnits = "\(progress.completedUnitCount)/\(progress.totalUnitCount)"
            callbackFraction = String(format: "%.3f", progress.fractionCompleted)
        } else {
            callbackUnits = "n/a"
            callbackFraction = "n/a"
        }
        let speedText = speed.map { "\(formatBytes(Int64($0)))/s" } ?? "n/a"
        print(
            "\(String(format: "%.2f", elapsed))s \(source) \(formatBytes(localBytes)) \(expectedBytes.map(formatBytes) ?? "unknown") \(localPercent)% \(callbackUnits) \(callbackFraction) \(speedText)"
        )
        fflush(stdout)
    }

    private func localObservedBytes() -> Int64 {
        max(
            trackedBytes(at: repoURL),
            cacheBlobBytes(modelID: modelID)
        )
    }
}

private func parseArguments(_ args: [String]) throws -> Configuration {
    var config = Configuration()
    var index = 0
    var customPatterns: [String] = []

    func value(after flag: String) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < args.count else { throw ProbeError.missingValue(flag) }
        return args[valueIndex]
    }

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--help", "-h":
            throw ProbeError.helpRequested
        case "--model":
            config.modelID = try value(after: arg)
            index += 1
        case "--revision":
            config.revision = try value(after: arg)
            index += 1
        case "--pattern":
            customPatterns.append(try value(after: arg))
            index += 1
        case "--all":
            customPatterns = []
            config.patterns = []
        case "--download-base":
            config.downloadBase = URL(fileURLWithPath: try value(after: arg), isDirectory: true)
            index += 1
        case "--poll":
            guard let value = TimeInterval(try value(after: arg)), value > 0 else {
                throw ProbeError.invalidValue(arg)
            }
            config.pollInterval = value
            index += 1
        case "--throttle":
            guard let value = TimeInterval(try value(after: arg)), value >= 0 else {
                throw ProbeError.invalidValue(arg)
            }
            config.callbackThrottle = value
            index += 1
        case "--clear":
            config.clearFirst = true
        case "--metadata-only":
            config.metadataOnly = true
        default:
            throw ProbeError.invalidValue(arg)
        }
        index += 1
    }

    if !customPatterns.isEmpty {
        config.patterns = customPatterns
    }
    return config
}

private func trackedBytes(at root: URL) -> Int64 {
    directoryBytes(at: root) { url in
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".safetensors") ||
            name.hasSuffix(".json") ||
            name.hasSuffix(".txt") ||
            name.hasSuffix(".model") ||
            name.hasSuffix(".tiktoken") ||
            name.hasSuffix(".jinja") ||
            name.hasSuffix(".incomplete")
    }
}

private func cacheBlobBytes(modelID: String) -> Int64 {
    let cacheName = "models--\(modelID.replacingOccurrences(of: "/", with: "--"))"
    return cacheRoots().map {
        directoryBytes(at: $0.appendingPathComponent(cacheName).appendingPathComponent("blobs")) { _ in true }
    }.max() ?? 0
}

private func cacheRoots() -> [URL] {
    let environment = ProcessInfo.processInfo.environment
    var roots: [URL] = []
    if let hubCache = environment["HF_HUB_CACHE"], !hubCache.isEmpty {
        roots.append(URL(fileURLWithPath: hubCache, isDirectory: true))
    }
    if let hfHome = environment["HF_HOME"], !hfHome.isEmpty {
        roots.append(URL(fileURLWithPath: hfHome, isDirectory: true).appendingPathComponent("hub"))
    }
    if let home = environment["HOME"], !home.isEmpty {
        roots.append(
            URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
        )
    }
    return roots
}

private func directoryBytes(at root: URL, include: (URL) -> Bool) -> Int64 {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
        options: [.skipsHiddenFiles]
    ) else {
        return 0
    }

    var total: Int64 = 0
    for case let url as URL in enumerator {
        guard include(url),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize
        else {
            continue
        }
        total += Int64(size)
    }
    return total
}

private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
