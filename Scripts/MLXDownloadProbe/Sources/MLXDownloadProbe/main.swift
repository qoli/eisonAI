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
    var clearCache = false
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
  --clear-cache           Remove this model from the default Hugging Face cache before starting.
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
        if config.clearCache {
            try clearModelCache(modelID: config.modelID)
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
        reporter.printBaseline()

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
    private let baselineSnapshotBytes: Int64
    private let baselineCacheBytes: Int64
    private var lastCallbackPrintedAt = Date.distantPast
    private var lastPollObservedBytes: Int64 = -1

    init(repoURL: URL, modelID: String, expectedBytes: Int64?, callbackThrottle: TimeInterval) {
        self.repoURL = repoURL
        self.modelID = modelID
        self.expectedBytes = expectedBytes
        self.callbackThrottle = callbackThrottle
        self.baselineSnapshotBytes = trackedBytes(at: repoURL)
        self.baselineCacheBytes = cacheBlobBytes(modelID: modelID)
    }

    func printBaseline() {
        print("baselineSnapshotBytes=\(formatBytes(baselineSnapshotBytes)) (\(baselineSnapshotBytes))")
        print("baselineCacheBytes=\(formatBytes(baselineCacheBytes)) (\(baselineCacheBytes))")
        if let expectedBytes, expectedBytes > 0 {
            let percent = min(1, Double(baselineCacheBytes) / Double(expectedBytes)) * 100
            print("baselineCachePercent=\(String(format: "%.3f", percent))%")
        }
    }

    func printHeader() {
        print("time source phase livePercent liveBytes materializedBytes materializedDelta cacheNewBytes cacheTotalBytes callbackUnits callbackFraction speed")
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
        printLine(source: "callback", progress: progress, speed: speed)
        lock.unlock()
    }

    func poll() {
        lock.lock()
        let sample = currentSample(progress: nil)
        guard sample.observedRunBytes != lastPollObservedBytes else {
            lock.unlock()
            return
        }
        lastPollObservedBytes = sample.observedRunBytes
        printLine(source: "poll", progress: nil, speed: nil)
        lock.unlock()
    }

    func finish(resultURL: URL, elapsed: TimeInterval) {
        lock.lock()
        let sample = currentSample(progress: nil)
        let averageSpeed = elapsed > 0 ? Double(sample.observedRunBytes) / elapsed : 0
        printLine(source: "finish", progress: nil, speed: averageSpeed)
        print("result=\(resultURL.path)")
        print("elapsed=\(String(format: "%.2f", elapsed))s")
        print("averageEffectiveSpeed=\(formatBytes(Int64(averageSpeed)))/s")
        print("finalMaterializedBytes=\(formatBytes(sample.materializedBytes)) (\(sample.materializedBytes))")
        print("finalMaterializedDelta=\(formatBytes(sample.materializedDelta)) (\(sample.materializedDelta))")
        print("finalCacheNewBytes=\(formatBytes(sample.cacheDelta)) (\(sample.cacheDelta))")
        lock.unlock()
    }

    private func printLine(source: String, progress: Progress?, speed: Double?) {
        let sample = currentSample(progress: progress)
        let elapsed = Date().timeIntervalSince(startedAt)
        let livePercent = expectedBytes.map { expected -> String in
            guard expected > 0 else { return "n/a" }
            return String(format: "%.3f", min(1, Double(sample.liveBytes) / Double(expected)) * 100)
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
            "\(String(format: "%.2f", elapsed))s \(source) \(sample.phase) \(livePercent)% \(formatBytes(sample.liveBytes)) \(formatBytes(sample.materializedBytes)) \(formatBytes(sample.materializedDelta)) \(formatBytes(sample.cacheDelta)) \(formatBytes(sample.cacheBytes)) \(callbackUnits) \(callbackFraction) \(speedText)"
        )
        fflush(stdout)
    }

    private func currentSample(progress: Progress?) -> ProgressSample {
        let materializedBytes = trackedBytes(at: repoURL)
        let cacheBytes = cacheBlobBytes(modelID: modelID)
        let materializedDelta = max(0, materializedBytes - baselineSnapshotBytes)
        let cacheDelta = max(0, cacheBytes - baselineCacheBytes)
        let callbackBytes = callbackEstimatedBytes(progress: progress)
        let observedRunBytes = max(materializedDelta, cacheDelta)
        let liveBytes = max(observedRunBytes, callbackBytes ?? 0)
        let phase = phaseDescription(
            materializedDelta: materializedDelta,
            cacheDelta: cacheDelta,
            callbackBytes: callbackBytes,
            liveBytes: liveBytes
        )

        return ProgressSample(
            phase: phase,
            liveBytes: liveBytes,
            observedRunBytes: observedRunBytes,
            materializedBytes: materializedBytes,
            materializedDelta: materializedDelta,
            cacheBytes: cacheBytes,
            cacheDelta: cacheDelta
        )
    }

    private func callbackEstimatedBytes(progress: Progress?) -> Int64? {
        guard let progress, let expectedBytes, expectedBytes > 0 else {
            return nil
        }
        let fraction = min(1, max(0, progress.fractionCompleted))
        guard fraction.isFinite else {
            return nil
        }
        return Int64((Double(expectedBytes) * fraction).rounded(.down))
    }

    private func phaseDescription(
        materializedDelta: Int64,
        cacheDelta: Int64,
        callbackBytes: Int64?,
        liveBytes: Int64
    ) -> String {
        let cacheWasWarm = expectedBytes.map { baselineCacheBytes >= $0 } ?? false
        if liveBytes == 0 {
            return cacheWasWarm ? "cache-warm" : "starting"
        }
        if cacheDelta > materializedDelta {
            return "network-cache"
        }
        if materializedDelta > 0 {
            return cacheWasWarm ? "materializing-cache" : "materialized"
        }
        if callbackBytes != nil {
            return cacheWasWarm ? "callback-cache" : "callback-transfer"
        }
        return "observing"
    }
}

private struct ProgressSample {
    let phase: String
    let liveBytes: Int64
    let observedRunBytes: Int64
    let materializedBytes: Int64
    let materializedDelta: Int64
    let cacheBytes: Int64
    let cacheDelta: Int64
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
        case "--clear-cache":
            config.clearCache = true
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

private func clearModelCache(modelID: String) throws {
    let cacheName = "models--\(modelID.replacingOccurrences(of: "/", with: "--"))"
    let fileManager = FileManager.default
    for root in cacheRoots() {
        let repoCache = root.appendingPathComponent(cacheName, isDirectory: true)
        let lockCache = root
            .appendingPathComponent(".locks", isDirectory: true)
            .appendingPathComponent(cacheName, isDirectory: true)
        for url in [repoCache, lockCache] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
            print("removedCache=\(url.path)")
        }
    }
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
