//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import os.log
import SafariServices
import EisonAIKit
import Foundation

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let profile: UUID?
        if #available(iOS 17.0, macOS 14.0, *) {
            profile = request?.userInfo?[SFExtensionProfileKey] as? UUID
        } else {
            profile = request?.userInfo?["profile"] as? UUID
        }

        let message: Any?
        if #available(iOS 17.0, macOS 14.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        os_log(.default, "Received message from browser.runtime.sendNativeMessage: %@ (profile: %@)", String(describing: message), profile?.uuidString ?? "none")

        let sendableContext = UnsafeSendable(context)
        Task { [message] in
            let responseMessage = await handleMessage(message)

            await MainActor.run {
                let response = NSExtensionItem()
                response.userInfo = [SFExtensionMessageKey: responseMessage]
                sendableContext.value.completeRequest(returningItems: [response], completionHandler: nil)
            }
        }
    }
}

private struct UnsafeSendable<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

private func handleMessage(_ message: Any?) async -> [String: Any] {
    guard let dict = message as? [String: Any] else {
        return makeError(requestId: nil, code: "INVALID_INPUT", message: "Message must be an object")
    }

    let requestId = dict["id"] as? String
    let name = dict["name"] as? String

    if name == "model.getStatus" {
        return [
            "v": dict["v"] as? Int ?? 1,
            "id": requestId ?? "",
            "type": "response",
            "name": "model.status",
            "payload": modelStatusPayload(),
        ]
    }

    let modelStatus = modelStatusPayload()
    let modelState = modelStatus["state"] as? String ?? "notInstalled"
    if modelState != "ready" {
        return makeError(
            requestId: requestId,
            code: "MODEL_NOT_READY",
            message: "模型尚未下載，請打開 App 完成模型下載。"
        )
    }

    let payload = dict["payload"] as? [String: Any]
    let title = payload?["title"] as? String ?? ""

    // Chunked native messaging to work around Safari message size limitations.
    if name == "summarize.begin" {
        let sessionId = payload?["sessionId"] as? String ?? requestId ?? ""
        let chunkCount = payload?["chunkCount"] as? Int ?? 0
        let url = payload?["url"] as? String ?? ""
        do {
            try await NativeSummarizer.shared.beginChunkedSession(sessionId: sessionId, title: title, url: url, chunkCount: chunkCount)
            return [
                "v": dict["v"] as? Int ?? 1,
                "id": requestId ?? "",
                "type": "response",
                "name": "summarize.ack",
                "payload": [
                    "sessionId": sessionId,
                    "kind": "begin",
                    "chunkCount": chunkCount,
                ],
            ]
        } catch {
            return makeError(requestId: requestId, code: "INVALID_INPUT", message: error.localizedDescription)
        }
    }

    if name == "summarize.chunk" {
        let sessionId = payload?["sessionId"] as? String ?? requestId ?? ""
        let index = payload?["index"] as? Int ?? -1
        let chunkText = payload?["text"] as? String ?? ""
        do {
            try await NativeSummarizer.shared.appendChunk(sessionId: sessionId, index: index, text: chunkText)
            return [
                "v": dict["v"] as? Int ?? 1,
                "id": requestId ?? "",
                "type": "response",
                "name": "summarize.ack",
                "payload": [
                    "sessionId": sessionId,
                    "kind": "chunk",
                    "index": index,
                ],
            ]
        } catch {
            return makeError(requestId: requestId, code: "INVALID_INPUT", message: error.localizedDescription)
        }
    }

    if name == "summarize.end" {
        let sessionId = payload?["sessionId"] as? String ?? requestId ?? ""
        do {
            let assembled = try await NativeSummarizer.shared.consumeChunkedSession(sessionId: sessionId)
            return try await summarizeAndRespond(dict: dict, requestId: requestId, title: assembled.title, text: assembled.text)
        } catch {
            return makeError(requestId: requestId, code: "INVALID_INPUT", message: error.localizedDescription)
        }
    }

    guard name == "summarize.start" else {
        return makeError(requestId: requestId, code: "INVALID_INPUT", message: "Unsupported request: \(name ?? "unknown")")
    }

    let text = payload?["text"] as? String ?? ""

    do {
        return try await summarizeAndRespond(dict: dict, requestId: requestId, title: title, text: text)
    } catch {
        os_log(.error, "[Eison-Native] summarize.failed (requestId=%@): %@", requestId ?? "none", String(describing: error))
        return makeError(requestId: requestId, code: "INFERENCE_FAILED", message: error.localizedDescription)
    }
}

private func summarizeAndRespond(dict: [String: Any], requestId: String?, title: String, text: String) async throws -> [String: Any] {
    let start = Date()
    os_log(.default, "[Eison-Native] summarize.start (requestId=%@, titleLen=%d, textLen=%d)", requestId ?? "none", title.count, text.count)
    let summary = try await NativeSummarizer.shared.summarize(title: title, text: text)
    os_log(.default, "[Eison-Native] summarize.done (requestId=%@, elapsed=%.3fs, outLen=%d)", requestId ?? "none", Date().timeIntervalSince(start), summary.count)
    return [
        "v": dict["v"] as? Int ?? 1,
        "id": requestId ?? "",
        "type": "response",
        "name": "summarize.done",
        "payload": [
            "requestId": requestId ?? "",
            "result": [
                "titleText": title.isEmpty ? "Summary" : title,
                "summaryText": summary,
            ],
        ],
    ]
}

private actor NativeSummarizer {
    static let shared = NativeSummarizer()
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
    private var model: AnyLanguageModel.CoreMLLanguageModel?
    private let appGroupID = "group.com.qoli.eisonAI"

    private struct ChunkedSessionMeta: Codable {
        let createdAt: TimeInterval
        let title: String
        let url: String
        let chunkCount: Int
    }

    private func validateSessionId(_ sessionId: String) throws {
        guard !sessionId.isEmpty, sessionId.count <= 128 else {
            throw NSError(domain: "EisonAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid sessionId"])
        }
        if sessionId.contains("/") || sessionId.contains("\\") {
            throw NSError(domain: "EisonAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid sessionId"])
        }
    }

    private func sessionsRootURL() throws -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            throw NSError(domain: "EisonAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group 容器不可用"])
        }
        return container
            .appendingPathComponent("Config", isDirectory: true)
            .appendingPathComponent("ChunkedSessions", isDirectory: true)
    }

    private func sessionDirURL(sessionId: String) throws -> URL {
        try validateSessionId(sessionId)
        return try sessionsRootURL().appendingPathComponent(sessionId, isDirectory: true)
    }

    func beginChunkedSession(sessionId: String, title: String, url: String, chunkCount: Int) throws {
        try validateSessionId(sessionId)
        guard chunkCount >= 1, chunkCount <= 10_000 else {
            throw NSError(domain: "EisonAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid chunkCount"])
        }

        let root = try sessionsRootURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let dir = try sessionDirURL(sessionId: sessionId)
        // Clean existing (best-effort)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let meta = ChunkedSessionMeta(
            createdAt: Date().timeIntervalSince1970,
            title: title,
            url: url,
            chunkCount: chunkCount
        )
        let metaURL = dir.appendingPathComponent("meta.json")
        let data = try JSONEncoder().encode(meta)
        try data.write(to: metaURL, options: [.atomic])
    }

    func appendChunk(sessionId: String, index: Int, text: String) throws {
        let dir = try sessionDirURL(sessionId: sessionId)
        let metaURL = dir.appendingPathComponent("meta.json")
        guard let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(ChunkedSessionMeta.self, from: metaData) else {
            throw NSError(domain: "EisonAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown sessionId"])
        }
        guard index >= 0, index < meta.chunkCount else {
            throw NSError(domain: "EisonAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid chunk index"])
        }
        let chunkURL = dir.appendingPathComponent("chunk_\(index).txt")
        try text.data(using: .utf8)?.write(to: chunkURL, options: [.atomic])
    }

    func consumeChunkedSession(sessionId: String) throws -> (title: String, url: String, text: String) {
        let dir = try sessionDirURL(sessionId: sessionId)
        let metaURL = dir.appendingPathComponent("meta.json")
        guard let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(ChunkedSessionMeta.self, from: metaData) else {
            throw NSError(domain: "EisonAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown sessionId"])
        }

        var parts: [String] = []
        parts.reserveCapacity(meta.chunkCount)
        var missing: [Int] = []
        for i in 0..<meta.chunkCount {
            let chunkURL = dir.appendingPathComponent("chunk_\(i).txt")
            if let data = try? Data(contentsOf: chunkURL),
               let text = String(data: data, encoding: .utf8) {
                parts.append(text)
            } else {
                missing.append(i)
            }
        }

        if !missing.isEmpty {
            throw NSError(domain: "EisonAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing chunks: \(missing.prefix(20))"])
        }

        // Cleanup (best-effort)
        try? FileManager.default.removeItem(at: dir)
        return (title: meta.title, url: meta.url, text: parts.joined())
    }

    func summarize(title: String, text: String) async throws -> String {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else {
            throw NSError(domain: "EisonAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "CoreML model requires iOS 18 / macOS 15"])
        }

        let maxInputCharacters = 16_000
        let normalizedText = normalizeInputText(text, limit: maxInputCharacters)

        let systemText = """
        你是一個網頁文章摘要助手。請用繁體中文輸出，並嚴格遵守格式：

        總結：<一行>
        要點：
        - <每行一個要點，開頭請用 emoji>

        除了以上格式，不要輸出任何多餘文字。
        禁止輸出任何推理過程或標籤（例如 <think>、<analysis>、<summary>）。
        請不要輸出英文。
        """

        let userPrompt = """
        請摘要以下文章：

        【標題】
        \(title)

        【正文】
        \(normalizedText)
        """

        let model = try await getModel()
        let session = AnyLanguageModel.LanguageModelSession(model: model, instructions: systemText)
        let options = AnyLanguageModel.GenerationOptions(
            temperature: 0.4,
            maximumResponseTokens: 512
        )
        let response: AnyLanguageModel.LanguageModelSession.Response<String> = try await session.respond(
            to: AnyLanguageModel.Prompt(userPrompt),
            options: options
        )

        return normalizeSummaryOutput(response.content)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
    private func getModel() async throws -> AnyLanguageModel.CoreMLLanguageModel {
        if let model {
            return model
        }

        let repoId = "XDGCC/coreml-Qwen3-0.6B"
        let revision = "fc6bdeb0b02573744ee2cba7e3f408f2851adf57"

        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            throw NSError(domain: "EisonAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group 容器不可用"])
        }

        let modelRoot = container
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(repoId, isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)

        let compiledURL = modelRoot.appendingPathComponent("Qwen3-0.6B.mlmodelc", isDirectory: true)
        let loaded = try await AnyLanguageModel.CoreMLLanguageModel(url: compiledURL, computeUnits: .all)
        self.model = loaded
        return loaded
    }
}

private func normalizeInputText(_ text: String, limit: Int) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > limit else { return trimmed }
    let prefix = String(trimmed.prefix(limit))
    return prefix + "\n\n（內容過長，已截斷）"
}

private func normalizeSummaryOutput(_ raw: String) -> String {
    let stripped = stripModelArtifacts(raw)
    return enforceSummaryFormat(stripped)
}

private func stripModelArtifacts(_ raw: String) -> String {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    // Remove common reasoning blocks.
    text = text.replacingOccurrences(of: "<think>", with: "<think>\n")
    text = text.replacingOccurrences(of: "</think>", with: "\n</think>")
    text = text.replacingOccurrences(of: "<analysis>", with: "<analysis>\n")
    text = text.replacingOccurrences(of: "</analysis>", with: "\n</analysis>")

    text = text.replacingOccurrences(of: "```", with: "")

    // Strip <think>...</think> and <analysis>...</analysis> entirely.
    for pattern in [#"(?s)<think>.*?</think>"#, #"(?s)<analysis>.*?</analysis>"#] {
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }
    }

    // Remove summary tags but keep their contents.
    text = text.replacingOccurrences(of: "<summary>", with: "")
    text = text.replacingOccurrences(of: "</summary>", with: "")

    // Normalize whitespace.
    let lines = text
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

private func enforceSummaryFormat(_ raw: String) -> String {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty {
        return "總結：（模型未輸出內容）\n要點：\n- 🧾（模型未輸出內容）"
    }

    let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

    // Extract summary candidate.
    var summaryCandidate: String? = nil
    for line in lines {
        if line.hasPrefix("總結：") {
            let rest = line.replacingOccurrences(of: "總結：", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { summaryCandidate = rest; break }
        }
    }
    if summaryCandidate == nil {
        // First non-bullet meaningful line.
        for line in lines {
            if line == "要點：" { continue }
            if line.hasPrefix("-") { continue }
            if line.hasPrefix("總結：") { continue }
            summaryCandidate = line
            break
        }
    }
    let summaryLine = (summaryCandidate ?? "（模型未輸出總結）")
        .replacingOccurrences(of: "總結：", with: "")
        .replacingOccurrences(of: "要點：", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    // Extract bullets after 要點： if present; otherwise collect any lines starting with '-'.
    var bullets: [String] = []
    var isInBulletSection = false
    for line in lines {
        if line == "要點：" { isInBulletSection = true; continue }
        if line.hasPrefix("要點：") { isInBulletSection = true; continue }
        if isInBulletSection, line.hasPrefix("-") {
            bullets.append(line)
        }
    }
    if bullets.isEmpty {
        for line in lines where line.hasPrefix("-") {
            bullets.append(line)
        }
    }

    // Fallback bullet if none.
    if bullets.isEmpty {
        bullets = ["- 🧾（模型未輸出要點）"]
    }

    // Ensure bullets are "- <emoji> ..." and not empty.
    let emojiRegex = try? NSRegularExpression(pattern: #"^\s*-\s*\p{Extended_Pictographic}"#)
    let normalizedBullets: [String] = bullets.prefix(8).map { bullet in
        var b = bullet
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "•", with: "-")

        if !b.hasPrefix("-") {
            b = "- " + b
        }
        if b == "-" || b == "- " {
            return "- 🧾（空白要點）"
        }

        if let emojiRegex {
            let range = NSRange(b.startIndex..<b.endIndex, in: b)
            let hasEmoji = emojiRegex.firstMatch(in: b, range: range) != nil
            if !hasEmoji {
                b = b.replacingOccurrences(of: #"^\s*-\s*"#, with: "- 🧾 ", options: .regularExpression)
            } else {
                b = b.replacingOccurrences(of: #"^\s*-\s*"#, with: "- ", options: .regularExpression)
            }
        }

        // Prevent model leaking tags.
        b = b.replacingOccurrences(of: "<", with: "＜").replacingOccurrences(of: ">", with: "＞")
        return b
    }

    let safeSummary = summaryLine
        .replacingOccurrences(of: "<", with: "＜")
        .replacingOccurrences(of: ">", with: "＞")

    return (["總結：\(safeSummary)", "要點："] + normalizedBullets).joined(separator: "\n")
}

private func modelStatusPayload() -> [String: Any] {
    let repoId = "XDGCC/coreml-Qwen3-0.6B"
    let revision = "fc6bdeb0b02573744ee2cba7e3f408f2851adf57"

    if let persisted = loadPersistedModelStatus(appGroupID: "group.com.qoli.eisonAI"),
       persisted.repoId == repoId,
       persisted.revision == revision {
        if persisted.state == "ready", isModelReady(appGroupID: "group.com.qoli.eisonAI", repoId: repoId, revision: revision) {
            return pruneNilValues([
                "state": "ready",
                "progress": 1.0,
                "error": nil,
                "repoId": repoId,
                "revision": revision,
            ])
        }

        if persisted.state == "downloading" || persisted.state == "verifying" || persisted.state == "failed" {
            return pruneNilValues([
                "state": persisted.state,
                "progress": persisted.progress,
                "error": persisted.error,
                "repoId": repoId,
                "revision": revision,
            ])
        }
    }

    if isModelReady(appGroupID: "group.com.qoli.eisonAI", repoId: repoId, revision: revision) {
        return pruneNilValues([
            "state": "ready",
            "progress": 1.0,
            "error": nil,
            "repoId": repoId,
            "revision": revision,
        ])
    }

    return pruneNilValues([
        "state": "notInstalled",
        "progress": 0.0,
        "error": nil,
        "repoId": repoId,
        "revision": revision,
    ])
}

private func pruneNilValues(_ dict: [String: Any?]) -> [String: Any] {
    var pruned: [String: Any] = [:]
    for (key, value) in dict {
        guard let value else { continue }
        pruned[key] = value
    }
    return pruned
}

private struct PersistedModelStatus: Decodable {
    let state: String
    let progress: Double
    let error: String?
    let repoId: String
    let revision: String
}

private func loadPersistedModelStatus(appGroupID: String) -> PersistedModelStatus? {
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
        return nil
    }
    let url = container.appendingPathComponent("Config/modelStatus.json")
    guard let data = try? Data(contentsOf: url) else {
        return nil
    }
    return try? JSONDecoder().decode(PersistedModelStatus.self, from: data)
}

private func isModelReady(appGroupID: String, repoId: String, revision: String) -> Bool {
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
        return false
    }

    let modelDir = container
        .appendingPathComponent("Models", isDirectory: true)
        .appendingPathComponent(repoId, isDirectory: true)
        .appendingPathComponent(revision, isDirectory: true)

    let requiredFiles: [String] = [
        "tokenizer.json",
        "tokenizer_config.json",
        "config.json",
        "Qwen3-0.6B.mlmodelc/metadata.json",
        "Qwen3-0.6B.mlmodelc/model.mil",
        "Qwen3-0.6B.mlmodelc/coremldata.bin",
        "Qwen3-0.6B.mlmodelc/analytics/coremldata.bin",
        "Qwen3-0.6B.mlmodelc/weights/weight.bin",
    ]

    for file in requiredFiles {
        let url = modelDir.appendingPathComponent(file)
        if !FileManager.default.fileExists(atPath: url.path) {
            return false
        }
    }

    return true
}

private func makeError(requestId: String?, code: String, message: String) -> [String: Any] {
    return [
        "v": 1,
        "id": requestId ?? "",
        "type": "event",
        "name": "error",
        "payload": [
            "requestId": requestId ?? "",
            "code": code,
            "message": message,
        ],
    ]
}
