#!/usr/bin/env swift

import Foundation

struct Config: Codable {
    var afmPath = "/opt/homebrew/bin/afm-cli"
    var wikiTitle = "Artificial intelligence"
    var githubOwner = "rust-lang"
    var githubRepo = "rust"
    var githubIssue = 152334
    var chunkSizes = [768, 896, 1024, 1280, 1536, 1792, 2048]
    var maxChunks = 5
    var execute = false
    var timeoutSeconds: TimeInterval = 90
    var outputDir = "logs/allowed-chunk-probe"
}

struct Corpus {
    let id: String
    let title: String
    let sourceURL: String
    let text: String
}

struct CorpusMeta: Codable {
    let id: String
    let title: String
    let sourceURL: String
    let characterCount: Int
    let estimatedTokens: Int
}

struct Chunk: Codable {
    let index: Int
    let estimatedTokens: Int
    let characterCount: Int
    let text: String
}

struct InvocationResult: Codable {
    let status: String
    let exitCode: Int32?
    let durationSeconds: Double
    let outputCharacters: Int
    let outputSnippet: String?
    let errorSnippet: String?
}

struct AFMRun {
    let invocation: InvocationResult
    let output: String
}

struct CorpusProbeResult: Codable {
    let corpusId: String
    let totalEstimatedTokens: Int
    let processedEstimatedTokens: Int
    let truncatedEstimatedTokens: Int
    let chunkCount: Int
    let chunkTokenEstimates: [Int]
    let chunkCharacterCounts: [Int]
    let chunkInvocations: [InvocationResult]
    let reduceInvocation: InvocationResult?
    let status: String
}

struct CandidateResult: Codable {
    let chunkSize: Int
    let corpusResults: [CorpusProbeResult]
    let status: String
}

struct ProbeReport: Codable {
    let generatedAt: String
    let config: Config
    let corpora: [CorpusMeta]
    let candidates: [CandidateResult]
}

enum ProbeError: Error, CustomStringConvertible {
    case usage(String)
    case network(String)
    case parse(String)
    case process(String)

    var description: String {
        switch self {
        case .usage(let message), .network(let message), .parse(let message), .process(let message):
            return message
        }
    }
}

func printUsage() {
    print("""
    Usage:
      swift Scripts/probe_allowed_chunk_sizes.swift [options]

    Default mode is dry-run: fetch corpora, estimate tokens, split chunks, and write a JSON report.
    Add --execute to call afm-cli for each chunk and final anchor reduce prompt.

    Options:
      --execute                         Actually invoke afm-cli.
      --afm PATH                        afm-cli path. Default: /opt/homebrew/bin/afm-cli
      --wiki-title TITLE                Wikipedia article title. Default: Artificial intelligence
      --github ISSUE                    GitHub issue as owner/repo#number. Default: rust-lang/rust#152334
      --chunk-sizes CSV                 Candidate sizes. Default: 768,896,1024,1280,1536,1792,2048
      --max-chunks N                    Long-document max chunks. Default: 5
      --timeout SECONDS                 Per afm-cli call timeout. Default: 90
      --output-dir PATH                 Report directory. Default: logs/allowed-chunk-probe
      --help                            Show this help.

    Example:
      swift Scripts/probe_allowed_chunk_sizes.swift --execute --chunk-sizes 896,1024,1280,1536,1792 --max-chunks 5
    """)
}

func parseArguments() throws -> Config {
    var config = Config()
    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--help", "-h":
            printUsage()
            exit(0)
        case "--execute":
            config.execute = true
        case "--afm":
            config.afmPath = try popValue(&args, for: arg)
        case "--wiki-title":
            config.wikiTitle = try popValue(&args, for: arg)
        case "--github":
            let value = try popValue(&args, for: arg)
            let pieces = value.split(separator: "#", maxSplits: 1).map(String.init)
            guard pieces.count == 2,
                  let issue = Int(pieces[1]),
                  pieces[0].split(separator: "/").count == 2 else {
                throw ProbeError.usage("--github must look like owner/repo#123")
            }
            let repoPieces = pieces[0].split(separator: "/").map(String.init)
            config.githubOwner = repoPieces[0]
            config.githubRepo = repoPieces[1]
            config.githubIssue = issue
        case "--chunk-sizes":
            let value = try popValue(&args, for: arg)
            let sizes = value
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            guard !sizes.isEmpty, sizes.allSatisfy({ $0 > 0 }) else {
                throw ProbeError.usage("--chunk-sizes must contain positive integers")
            }
            config.chunkSizes = Array(Set(sizes)).sorted()
        case "--max-chunks":
            guard let value = Int(try popValue(&args, for: arg)), value > 0 else {
                throw ProbeError.usage("--max-chunks must be a positive integer")
            }
            config.maxChunks = value
        case "--timeout":
            guard let value = Double(try popValue(&args, for: arg)), value > 0 else {
                throw ProbeError.usage("--timeout must be a positive number")
            }
            config.timeoutSeconds = value
        case "--output-dir":
            config.outputDir = try popValue(&args, for: arg)
        default:
            throw ProbeError.usage("Unknown argument: \(arg)")
        }
    }
    return config
}

func popValue(_ args: inout [String], for option: String) throws -> String {
    guard !args.isEmpty else { throw ProbeError.usage("\(option) requires a value") }
    return args.removeFirst()
}

func fetchURL(_ url: URL, headers: [String: String] = [:]) throws -> Data {
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    for (key, value) in headers {
        request.setValue(value, forHTTPHeaderField: key)
    }

    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<Data, Error>!
    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        if let error {
            result = .failure(error)
            return
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            result = .failure(ProbeError.network("HTTP \(http.statusCode) for \(url.absoluteString)"))
            return
        }
        result = .success(data ?? Data())
    }.resume()
    semaphore.wait()
    return try result.get()
}

func fetchWikipedia(title: String) throws -> Corpus {
    guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: "https://en.wikipedia.org/w/api.php?action=query&prop=extracts&explaintext=1&format=json&formatversion=2&titles=\(encodedTitle)") else {
        throw ProbeError.network("Invalid Wikipedia title: \(title)")
    }
    let data = try fetchURL(url, headers: ["User-Agent": "eisonAI-allowed-chunk-probe/1.0"])
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let query = object?["query"] as? [String: Any],
          let pages = query["pages"] as? [[String: Any]],
          let page = pages.first,
          let resolvedTitle = page["title"] as? String,
          let extract = page["extract"] as? String,
          !extract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ProbeError.parse("Unable to parse Wikipedia extract")
    }
    return Corpus(
        id: "wikipedia",
        title: resolvedTitle,
        sourceURL: "https://en.wikipedia.org/wiki/\(encodedTitle)",
        text: normalizeText(extract)
    )
}

func fetchGitHubIssue(owner: String, repo: String, issue: Int) throws -> Corpus {
    guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/issues/\(issue)") else {
        throw ProbeError.network("Invalid GitHub issue")
    }
    let data = try fetchURL(url, headers: [
        "Accept": "application/vnd.github+json",
        "User-Agent": "eisonAI-allowed-chunk-probe/1.0",
    ])
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let title = object?["title"] as? String else {
        throw ProbeError.parse("Unable to parse GitHub issue title")
    }
    let body = object?["body"] as? String ?? ""
    let htmlURL = object?["html_url"] as? String ?? "https://github.com/\(owner)/\(repo)/issues/\(issue)"
    let text = """
    # \(title)

    \(body)
    """
    return Corpus(
        id: "github-issue",
        title: "\(owner)/\(repo)#\(issue): \(title)",
        sourceURL: htmlURL,
        text: normalizeText(text)
    )
}

func normalizeText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func estimatedTokenCost(of character: Character) -> Double {
    var hasCJK = false
    var scalarCount = 0
    for scalar in String(character).unicodeScalars {
        scalarCount += 1
        let value = scalar.value
        if (0x4E00...0x9FFF).contains(value) ||
            (0x3400...0x4DBF).contains(value) ||
            (0x3040...0x30FF).contains(value) ||
            (0xAC00...0xD7AF).contains(value) {
            hasCJK = true
        }
    }
    return hasCJK ? Double(max(1, scalarCount)) : Double(max(1, scalarCount)) / 4.0
}

func estimateTokens(_ text: String) -> Int {
    let raw = text.reduce(0.0) { $0 + estimatedTokenCost(of: $1) }
    return Int(ceil(raw))
}

func splitByEstimatedTokens(_ text: String, chunkSize: Int, maxChunks: Int) -> (chunks: [Chunk], totalTokens: Int, processedTokens: Int) {
    let totalTokens = estimateTokens(text)
    var chunks: [Chunk] = []
    var buffer = ""
    var currentCost = 0.0

    func flush() {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, chunks.count < maxChunks else {
            buffer.removeAll(keepingCapacity: true)
            currentCost = 0
            return
        }
        chunks.append(Chunk(
            index: chunks.count,
            estimatedTokens: Int(ceil(currentCost)),
            characterCount: trimmed.count,
            text: trimmed
        ))
        buffer.removeAll(keepingCapacity: true)
        currentCost = 0
    }

    for character in text {
        if chunks.count >= maxChunks { break }
        buffer.append(character)
        currentCost += estimatedTokenCost(of: character)
        if currentCost >= Double(chunkSize) {
            flush()
        }
    }
    if chunks.count < maxChunks {
        flush()
    }
    let processedTokens = chunks.reduce(0) { $0 + $1.estimatedTokens }
    return (chunks, totalTokens, processedTokens)
}

func runAFM(afmPath: String, systemPrompt: String, prompt: String, timeout: TimeInterval) -> AFMRun {
    let start = Date()
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("eisonai-afm-probe-\(UUID().uuidString).txt")
    do {
        try prompt.write(to: tempURL, atomically: true, encoding: .utf8)
    } catch {
        return AFMRun(invocation: InvocationResult(
            status: "prompt_write_failed",
            exitCode: nil,
            durationSeconds: Date().timeIntervalSince(start),
            outputCharacters: 0,
            outputSnippet: nil,
            errorSnippet: String(describing: error)
        ), output: "")
    }
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: afmPath)
    process.arguments = ["--system-prompt", systemPrompt, "--file", tempURL.path]

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        return AFMRun(invocation: InvocationResult(
            status: "launch_failed",
            exitCode: nil,
            durationSeconds: Date().timeIntervalSince(start),
            outputCharacters: 0,
            outputSnippet: nil,
            errorSnippet: String(describing: error)
        ), output: "")
    }

    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
    }
    var timedOut = false
    if process.isRunning {
        timedOut = true
        process.terminate()
    }
    process.waitUntilExit()

    let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let combinedError = [stderrText, stdoutText].joined(separator: "\n")
    let lower = combinedError.lowercased()
    let status: String
    if timedOut {
        status = "timeout"
    } else if lower.contains("context") && (lower.contains("exceed") || lower.contains("too large") || lower.contains("maximum")) {
        status = "context_limit"
    } else if process.terminationStatus != 0 {
        status = "failed"
    } else {
        status = "ok"
    }

    return AFMRun(invocation: InvocationResult(
        status: status,
        exitCode: process.terminationStatus,
        durationSeconds: Date().timeIntervalSince(start),
        outputCharacters: stdoutText.count,
        outputSnippet: stdoutText.isEmpty ? nil : String(stdoutText.prefix(800)),
        errorSnippet: status == "ok" ? nil : String(combinedError.prefix(800))
    ), output: stdoutText)
}

func chunkPrompt(corpus: Corpus, chunk: Chunk, chunkCount: Int) -> String {
    """
    You are probing Apple Foundation Models context behavior for a long-document chunking pipeline.
    Return concise reading anchors only. Use at most 120 words.

    Source: \(corpus.title)
    Chunk: \(chunk.index + 1) of \(chunkCount)
    Estimated chunk tokens: \(chunk.estimatedTokens)

    CONTENT
    \(chunk.text)
    """
}

func reducePrompt(corpus: Corpus, chunkSize: Int, anchors: [String]) -> String {
    """
    You are probing the final reduce step for a long-document reading pipeline.
    Return a compact summary and state whether the input was coherent. Use at most 160 words.

    Source: \(corpus.title)
    Candidate chunk size: \(chunkSize)
    Reading anchor count: \(anchors.count)

    \(anchors.enumerated().map { index, anchor in "Chunk \(index + 1)\n\(anchor)" }.joined(separator: "\n\n"))
    """
}

func probeCorpus(config: Config, corpus: Corpus, chunkSize: Int) -> CorpusProbeResult {
    let split = splitByEstimatedTokens(corpus.text, chunkSize: chunkSize, maxChunks: config.maxChunks)
    var invocations: [InvocationResult] = []
    var reduceInvocation: InvocationResult?
    var status = "dry_run"

    if config.execute {
        let systemPrompt = "You are a terse long-document reading probe. Do not explain the test."
        var anchors: [String] = []
        for chunk in split.chunks {
            let run = runAFM(
                afmPath: config.afmPath,
                systemPrompt: systemPrompt,
                prompt: chunkPrompt(corpus: corpus, chunk: chunk, chunkCount: split.chunks.count),
                timeout: config.timeoutSeconds
            )
            let result = run.invocation
            invocations.append(result)
            if result.status != "ok" {
                status = result.status
                break
            }
            anchors.append(run.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if invocations.allSatisfy({ $0.status == "ok" }) {
            let run = runAFM(
                afmPath: config.afmPath,
                systemPrompt: systemPrompt,
                prompt: reducePrompt(corpus: corpus, chunkSize: chunkSize, anchors: anchors),
                timeout: config.timeoutSeconds
            )
            reduceInvocation = run.invocation
            status = reduceInvocation?.status ?? "reduce_missing"
        }
    }

    return CorpusProbeResult(
        corpusId: corpus.id,
        totalEstimatedTokens: split.totalTokens,
        processedEstimatedTokens: split.processedTokens,
        truncatedEstimatedTokens: max(0, split.totalTokens - split.processedTokens),
        chunkCount: split.chunks.count,
        chunkTokenEstimates: split.chunks.map(\.estimatedTokens),
        chunkCharacterCounts: split.chunks.map(\.characterCount),
        chunkInvocations: invocations,
        reduceInvocation: reduceInvocation,
        status: status
    )
}

func writeReport(_ report: ProbeReport, outputDir: String) throws -> URL {
    let formatter = ISO8601DateFormatter()
    let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    let directoryURL = URL(fileURLWithPath: outputDir, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let reportURL = directoryURL.appendingPathComponent("allowed-chunk-probe-\(timestamp).json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: reportURL)
    return reportURL
}

func printSummary(report: ProbeReport, reportURL: URL) {
    print("Report: \(reportURL.path)")
    print("Mode: \(report.config.execute ? "execute" : "dry-run")")
    print("Sources:")
    for corpus in report.corpora {
        print("- \(corpus.id): \(corpus.title) chars=\(corpus.characterCount) estimatedTokens=\(corpus.estimatedTokens)")
    }
    print("")
    print("chunkSize\tstatus\tcorpus\tchunks\tprocessed\ttruncated\tchunkTokens")
    for candidate in report.candidates {
        for corpus in candidate.corpusResults {
            print([
                String(candidate.chunkSize),
                corpus.status,
                corpus.corpusId,
                String(corpus.chunkCount),
                String(corpus.processedEstimatedTokens),
                String(corpus.truncatedEstimatedTokens),
                corpus.chunkTokenEstimates.map(String.init).joined(separator: "+"),
            ].joined(separator: "\t"))
        }
    }
}

func main() throws {
    let config = try parseArguments()
    if config.execute && !FileManager.default.isExecutableFile(atPath: config.afmPath) {
        throw ProbeError.process("afm-cli is not executable at \(config.afmPath)")
    }

    print("Fetching Wikipedia: \(config.wikiTitle)")
    let wiki = try fetchWikipedia(title: config.wikiTitle)
    print("Fetching GitHub issue: \(config.githubOwner)/\(config.githubRepo)#\(config.githubIssue)")
    let issue = try fetchGitHubIssue(owner: config.githubOwner, repo: config.githubRepo, issue: config.githubIssue)
    let corpora = [wiki, issue]

    let candidates = config.chunkSizes.map { size in
        print("Probing chunkSize=\(size)\(config.execute ? "" : " (dry-run)")")
        let results = corpora.map { probeCorpus(config: config, corpus: $0, chunkSize: size) }
        let status = results.allSatisfy { $0.status == "ok" || $0.status == "dry_run" }
            ? (config.execute ? "ok" : "dry_run")
            : "failed"
        return CandidateResult(chunkSize: size, corpusResults: results, status: status)
    }

    let now = ISO8601DateFormatter().string(from: Date())
    let report = ProbeReport(
        generatedAt: now,
        config: config,
        corpora: corpora.map {
            CorpusMeta(
                id: $0.id,
                title: $0.title,
                sourceURL: $0.sourceURL,
                characterCount: $0.text.count,
                estimatedTokens: estimateTokens($0.text)
            )
        },
        candidates: candidates
    )
    let reportURL = try writeReport(report, outputDir: config.outputDir)
    printSummary(report: report, reportURL: reportURL)
}

do {
    try main()
} catch let error as ProbeError {
    fputs("error: \(error.description)\n", stderr)
    exit(2)
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
