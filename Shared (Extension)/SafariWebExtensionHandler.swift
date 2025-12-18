//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Native messaging is used only for lightweight configuration (e.g. system prompt).
//  LLM inference runs in the extension popup via WebLLM (bundled assets).
//

import Foundation
import SafariServices
import CryptoKit
import os.log

#if canImport(FoundationModels)
import FoundationModels
#endif

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let logSubsystem = "com.qoli.eisonAI"
    private static let nativeLog = OSLog(subsystem: logSubsystem, category: "Native")
    private static let rawLibraryLog = OSLog(subsystem: logSubsystem, category: "RawLibrary")

    private let appGroupIdentifier = AppConfig.appGroupIdentifier
    private let systemPromptKey = AppConfig.systemPromptKey
    private let rawLibraryMaxItems = 200

    private struct RawHistoryItem: Codable {
        var v: Int = 1
        var id: String
        var createdAt: Date
        var url: String
        var title: String
        var articleText: String
        var summaryText: String
        var systemPrompt: String
        var userPrompt: String
        var modelId: String
    }

    private static let filenameTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
        return formatter
    }()

    private func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private func rawLibraryItemsDirectoryURL() throws -> URL {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            )
        else {
            os_log(
                "[Eison-Native] App Group container unavailable for id=%{public}@",
                log: Self.rawLibraryLog,
                type: .error,
                appGroupIdentifier
            )
            throw NSError(
                domain: "EisonAI.RawLibrary",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "App Group container is unavailable."]
            )
        }

        var directoryURL = containerURL
        for component in AppConfig.rawLibraryItemsPathComponents {
            directoryURL = directoryURL.appendingPathComponent(component, isDirectory: true)
        }
        return directoryURL
    }

    private func sha256Hex(_ value: String) -> String {
        let data = Data(value.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func parseTimestampFromRawLibraryFilename(_ filename: String) -> Date? {
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        guard let range = base.range(of: "__") else { return nil }
        let timestamp = String(base[range.upperBound...])
        return Self.filenameTimestampFormatter.date(from: timestamp)
    }

    @discardableResult
    private func enforceRawLibraryLimit(in directoryURL: URL) throws -> Int {
        let items = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let jsonFiles = items
            .filter { $0.pathExtension.lowercased() == "json" }
        guard jsonFiles.count > rawLibraryMaxItems else { return 0 }

        let sorted = jsonFiles.sorted { lhs, rhs in
            let leftDate = parseTimestampFromRawLibraryFilename(lhs.lastPathComponent) ?? .distantPast
            let rightDate = parseTimestampFromRawLibraryFilename(rhs.lastPathComponent) ?? .distantPast
            if leftDate != rightDate { return leftDate < rightDate }
            return lhs.lastPathComponent < rhs.lastPathComponent
        }

        let deleteCount = sorted.count - rawLibraryMaxItems
        for fileURL in sorted.prefix(deleteCount) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return deleteCount
    }

    private func saveRawHistoryItem(
        url: String,
        title: String,
        articleText: String,
        summaryText: String,
        systemPrompt: String,
        userPrompt: String,
        modelId: String
    ) throws -> (id: String, filename: String) {
        let directoryURL = try rawLibraryItemsDirectoryURL()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let createdAt = Date()
        let id = UUID().uuidString
        let urlHash = sha256Hex(url)
        let timestamp = Self.filenameTimestampFormatter.string(from: createdAt)
        let filename = "\(urlHash)__\(timestamp).json"

        // Keep only the latest record per URL by removing older files with the same hash prefix.
        let existing = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let prefix = "\(urlHash)__"
        var removedForURL = 0
        for fileURL in existing where fileURL.pathExtension.lowercased() == "json" {
            if fileURL.lastPathComponent.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: fileURL)
                removedForURL += 1
            }
        }
        if removedForURL > 0 {
            os_log(
                "[Eison-Native] RawLibrary removed %d old item(s) for urlHash=%{public}@",
                log: Self.rawLibraryLog,
                type: .info,
                removedForURL,
                urlHash
            )
        }

        let item = RawHistoryItem(
            id: id,
            createdAt: createdAt,
            url: url,
            title: title,
            articleText: articleText,
            summaryText: summaryText,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            modelId: modelId
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)

        let fileURL = directoryURL.appendingPathComponent(filename)
        try data.write(to: fileURL, options: [.atomic])

        let trimmed = try enforceRawLibraryLimit(in: directoryURL)
        if trimmed > 0 {
            os_log(
                "[Eison-Native] RawLibrary trimmed %d old item(s) to max=%d",
                log: Self.rawLibraryLog,
                type: .info,
                trimmed,
                rawLibraryMaxItems
            )
        }
        return (id, filename)
    }

    private func loadSystemPrompt() -> String {
        guard let stored = sharedDefaults()?.string(forKey: systemPromptKey) else {
            return AppConfig.defaultSystemPrompt
        }
        if stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppConfig.defaultSystemPrompt
        }
        return stored
    }

    private func saveSystemPrompt(_ value: String?) {
        guard let defaults = sharedDefaults() else { return }
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: systemPromptKey)
        } else {
            defaults.set(trimmed, forKey: systemPromptKey)
        }
    }

    private func isFoundationModelsExtensionEnabled() -> Bool {
        sharedDefaults()?.bool(forKey: AppConfig.foundationModelsExtensionEnabledKey) ?? false
    }

    private func complete(_ context: NSExtensionContext, responseMessage: [String: Any]) {
        let response = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            response.userInfo = [SFExtensionMessageKey: responseMessage]
        } else {
            response.userInfo = ["message": responseMessage]
        }
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let profile: UUID?
        if #available(iOS 17.0, macOS 14.0, *) {
            profile = request?.userInfo?[SFExtensionProfileKey] as? UUID
        } else {
            profile = request?.userInfo?["profile"] as? UUID
        }

        let message: Any?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        let profileString = profile?.uuidString ?? "none"
        if let dict = message as? [String: Any] {
            let command = (dict["command"] as? String) ?? (dict["name"] as? String) ?? ""
            os_log(
                "[Eison-Native] Received native message command=%{public}@ (profile: %{public}@)",
                log: Self.nativeLog,
                type: .info,
                command,
                profileString
            )
        } else {
            let messageType = message.map { String(describing: type(of: $0)) } ?? "nil"
            os_log(
                "[Eison-Native] Received native message (non-dict) (profile: %{public}@) type=%{public}@",
                log: Self.nativeLog,
                type: .error,
                profileString,
                messageType
            )
        }

        guard let dict = message as? [String: Any] else {
            complete(context, responseMessage: [
                "v": 1,
                "type": "error",
                "name": "error",
                "payload": [
                    "code": "INVALID_MESSAGE",
                    "message": "Expected an object message payload.",
                ],
            ])
            return
        }

        let command = (dict["command"] as? String) ?? (dict["name"] as? String) ?? ""
        switch command {
        case "getSystemPrompt":
            complete(context, responseMessage: [
                "v": 1,
                "type": "response",
                "name": "systemPrompt",
                "payload": [
                    "prompt": loadSystemPrompt(),
                ],
            ])
            return

        case "setSystemPrompt":
            let prompt = dict["prompt"] as? String
            saveSystemPrompt(prompt)
            complete(context, responseMessage: [
                "v": 1,
                "type": "response",
                "name": "systemPrompt",
                "payload": [
                    "prompt": loadSystemPrompt(),
                ],
            ])
            return

        case "resetSystemPrompt":
            saveSystemPrompt(nil)
            complete(context, responseMessage: [
                "v": 1,
                "type": "response",
                "name": "systemPrompt",
                "payload": [
                    "prompt": loadSystemPrompt(),
                ],
            ])
            return

        case "fm.checkAvailability":
            Task {
                let enabled = isFoundationModelsExtensionEnabled()
                let payload = await FoundationModelsStreamManager.shared.checkAvailabilityPayload(enabled: enabled)
                complete(context, responseMessage: [
                    "v": 1,
                    "type": "response",
                    "name": "fm.checkAvailability",
                    "payload": payload,
                ])
            }
            return

        case "fm.stream.start":
            Task {
                let enabled = isFoundationModelsExtensionEnabled()
                if !enabled {
                    complete(context, responseMessage: [
                        "v": 1,
                        "type": "error",
                        "name": "fm.stream.start",
                        "payload": [
                            "code": "DISABLED",
                            "message": "Foundation Models (Safari Extension) is disabled.",
                        ],
                    ])
                    return
                }

                let payload = dict["payload"] as? [String: Any]
                let systemPrompt = (payload?["systemPrompt"] as? String) ?? ""
                let userPrompt = (payload?["userPrompt"] as? String) ?? ""
                let optionsDict = payload?["options"] as? [String: Any]
                let temperature = optionsDict?["temperature"] as? Double
                let maximumResponseTokens = optionsDict?["maximumResponseTokens"] as? Int

                do {
                    let jobId = try await FoundationModelsStreamManager.shared.start(
                        systemPrompt: systemPrompt,
                        userPrompt: userPrompt,
                        temperature: temperature,
                        maximumResponseTokens: maximumResponseTokens
                    )
                    complete(context, responseMessage: [
                        "v": 1,
                        "type": "response",
                        "name": "fm.stream.start",
                        "payload": [
                            "jobId": jobId,
                            "cursor": 0,
                        ],
                    ])
                } catch {
                    complete(context, responseMessage: [
                        "v": 1,
                        "type": "error",
                        "name": "fm.stream.start",
                        "payload": [
                            "code": "START_FAILED",
                            "message": error.localizedDescription,
                        ],
                    ])
                }
            }
            return

        case "fm.stream.poll":
            Task {
                let payload = dict["payload"] as? [String: Any]
                let jobId = (payload?["jobId"] as? String) ?? ""
                let cursor = (payload?["cursor"] as? Int) ?? 0

                let result = await FoundationModelsStreamManager.shared.poll(jobId: jobId, cursor: cursor)
                switch result {
                case .success(let responsePayload):
                    complete(context, responseMessage: [
                        "v": 1,
                        "type": "response",
                        "name": "fm.stream.poll",
                        "payload": responsePayload,
                    ])
                case .failure(let error):
                    complete(context, responseMessage: [
                        "v": 1,
                        "type": "error",
                        "name": "fm.stream.poll",
                        "payload": [
                            "code": "POLL_FAILED",
                            "message": error.localizedDescription,
                        ],
                    ])
                }
            }
            return

        case "fm.stream.cancel":
            Task {
                let payload = dict["payload"] as? [String: Any]
                let jobId = (payload?["jobId"] as? String) ?? ""
                await FoundationModelsStreamManager.shared.cancel(jobId: jobId)
                complete(context, responseMessage: [
                    "v": 1,
                    "type": "response",
                    "name": "fm.stream.cancel",
                    "payload": [
                        "ok": true,
                    ],
                ])
            }
            return

        case "saveRawItem":
            do {
                let payload = dict["payload"] as? [String: Any]
                let url = (payload?["url"] as? String) ?? ""
                let title = (payload?["title"] as? String) ?? ""
                let articleText = (payload?["articleText"] as? String) ?? ""
                let summaryText = (payload?["summaryText"] as? String) ?? ""
                let systemPrompt = (payload?["systemPrompt"] as? String) ?? ""
                let userPrompt = (payload?["userPrompt"] as? String) ?? ""
                let modelId = (payload?["modelId"] as? String) ?? ""

                let urlHash = sha256Hex(url)
                os_log(
                    "[Eison-Native] saveRawItem requested (profile: %{public}@) urlHash=%{public}@ urlLen=%d titleLen=%d articleLen=%d summaryLen=%d model=%{public}@",
                    log: Self.rawLibraryLog,
                    type: .info,
                    profile?.uuidString ?? "none",
                    urlHash,
                    url.count,
                    title.count,
                    articleText.count,
                    summaryText.count,
                    modelId
                )

                if summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw NSError(
                        domain: "EisonAI.RawLibrary",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "summaryText is required."]
                    )
                }

                let directoryURL: URL
                do {
                    directoryURL = try rawLibraryItemsDirectoryURL()
                    os_log(
                        "[Eison-Native] RawLibrary directory: %{public}@",
                        log: Self.rawLibraryLog,
                        type: .info,
                        directoryURL.path
                    )
                } catch {
                    os_log(
                        "[Eison-Native] RawLibrary directory unavailable: %{public}@",
                        log: Self.rawLibraryLog,
                        type: .error,
                        error.localizedDescription
                    )
                    throw error
                }

                let result = try saveRawHistoryItem(
                    url: url,
                    title: title,
                    articleText: articleText,
                    summaryText: summaryText,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    modelId: modelId
                )

                do {
                    let savedURL = directoryURL.appendingPathComponent(result.filename)
                    let items = try FileManager.default.contentsOfDirectory(
                        at: directoryURL,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    )
                    let jsonCount = items.filter { $0.pathExtension.lowercased() == "json" }.count
                    os_log(
                        "[Eison-Native] saveRawItem saved id=%{public}@ file=%{public}@ path=%{public}@ totalJSON=%d",
                        log: Self.rawLibraryLog,
                        type: .info,
                        result.id,
                        result.filename,
                        savedURL.path,
                        jsonCount
                    )

                    complete(context, responseMessage: [
                        "v": 1,
                        "type": "response",
                        "name": "saveRawItem",
                        "payload": [
                            "ok": true,
                            "id": result.id,
                            "filename": result.filename,
                            "directoryPath": directoryURL.path,
                            "savedPath": savedURL.path,
                            "totalJSON": jsonCount,
                        ],
                    ])
                } catch {
                    os_log(
                        "[Eison-Native] saveRawItem post-save listing failed: %{public}@",
                        log: Self.rawLibraryLog,
                        type: .error,
                        error.localizedDescription
                    )

                    complete(context, responseMessage: [
                        "v": 1,
                        "type": "response",
                        "name": "saveRawItem",
                        "payload": [
                            "ok": true,
                            "id": result.id,
                            "filename": result.filename,
                            "directoryPath": directoryURL.path,
                        ],
                    ])
                }
            } catch {
                os_log(
                    "[Eison-Native] saveRawItem failed: %{public}@",
                    log: Self.rawLibraryLog,
                    type: .error,
                    error.localizedDescription
                )
                complete(context, responseMessage: [
                    "v": 1,
                    "type": "error",
                    "name": "saveRawItem",
                    "payload": [
                        "code": "SAVE_FAILED",
                        "message": error.localizedDescription,
                    ],
                ])
            }
            return

        default:
            complete(context, responseMessage: [
                "v": 1,
                "type": "error",
                "name": "error",
                "payload": [
                    "code": "UNKNOWN_COMMAND",
                    "message": "Unsupported native command: \(command)",
                ],
            ])
            return
        }
    }
}

actor FoundationModelsStreamManager {
    static let shared = FoundationModelsStreamManager()

    enum StreamError: LocalizedError {
        case notSupported
        case unavailable(String)
        case jobNotFound

        var errorDescription: String? {
            switch self {
            case .notSupported:
                return "Foundation Models requires iOS 26+ with Apple Intelligence."
            case .unavailable(let reason):
                return reason
            case .jobNotFound:
                return "Stream job not found."
            }
        }
    }

    private struct Job {
        var output: String = ""
        var done: Bool = false
        var error: String?
        var task: Task<Void, Never>?
    }

    private var jobs: [String: Job] = [:]

    func checkAvailabilityPayload(enabled: Bool) async -> [String: Any] {
        guard enabled else {
            return [
                "enabled": false,
                "available": false,
                "reason": "Disabled by user.",
            ]
        }

        guard #available(iOS 26.0, macOS 26.0, *) else {
            return [
                "enabled": true,
                "available": false,
                "reason": "Requires iOS 26+ with Apple Intelligence.",
            ]
        }

#if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return [
                "enabled": true,
                "available": true,
                "reason": "",
            ]
        case .unavailable(let reason):
            let message: String
            switch reason {
            case .deviceNotEligible:
                message = "Device not eligible for Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                message = "Apple Intelligence is not enabled."
            case .modelNotReady:
                message = "Apple Intelligence models are still downloading."
            @unknown default:
                message = "Apple Intelligence is unavailable."
            }
            return [
                "enabled": true,
                "available": false,
                "reason": message,
            ]
        }
#else
        return [
            "enabled": true,
            "available": false,
            "reason": "FoundationModels framework is unavailable.",
        ]
#endif
    }

    func start(
        systemPrompt: String,
        userPrompt: String,
        temperature: Double?,
        maximumResponseTokens: Int?
    ) async throws -> String {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw StreamError.notSupported }
#if canImport(FoundationModels)
        let availability = SystemLanguageModel.default.availability
        if case .unavailable(let reason) = availability {
            let message: String
            switch reason {
            case .deviceNotEligible:
                message = "Device not eligible for Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                message = "Apple Intelligence is not enabled."
            case .modelNotReady:
                message = "Apple Intelligence models are still downloading."
            @unknown default:
                message = "Apple Intelligence is unavailable."
            }
            throw StreamError.unavailable(message)
        }

        let jobId = UUID().uuidString
        var job = Job()

        let temp = temperature
        let maxTok = maximumResponseTokens

        job.task = Task {
            await self.runJob(
                jobId: jobId,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                temperature: temp,
                maximumResponseTokens: maxTok
            )
        }

        jobs[jobId] = job
        return jobId
#else
        throw StreamError.notSupported
#endif
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func runJob(
        jobId: String,
        systemPrompt: String,
        userPrompt: String,
        temperature: Double?,
        maximumResponseTokens: Int?
    ) async {
        let options = GenerationOptions(
            sampling: nil,
            temperature: temperature,
            maximumResponseTokens: maximumResponseTokens
        )

        do {
            let model = SystemLanguageModel(useCase: .general, guardrails: .default)
            let session = LanguageModelSession(model: model, instructions: Instructions(systemPrompt))
            let stream = session.streamResponse(to: Prompt(userPrompt), options: options)

            var previous = ""
            for try await partial in stream {
                if Task.isCancelled { break }
                let current = partial.content
                let delta: String
                if current.hasPrefix(previous) {
                    delta = String(current.dropFirst(previous.count))
                } else {
                    delta = current
                }
                previous = current
                if !delta.isEmpty {
                    appendDelta(jobId: jobId, delta: delta)
                }
            }

            markDone(jobId: jobId)
        } catch {
            markError(jobId: jobId, message: error.localizedDescription)
        }
    }
#endif

    private func appendDelta(jobId: String, delta: String) {
        guard var job = jobs[jobId] else { return }
        guard !job.done else { return }
        job.output.append(delta)
        jobs[jobId] = job
    }

    private func markDone(jobId: String) {
        guard var job = jobs[jobId] else { return }
        job.done = true
        job.task = nil
        jobs[jobId] = job
    }

    private func markError(jobId: String, message: String) {
        guard var job = jobs[jobId] else { return }
        job.done = true
        job.error = message
        job.task = nil
        jobs[jobId] = job
    }

    func poll(jobId: String, cursor: Int) async -> Result<[String: Any], Error> {
        guard let job = jobs[jobId] else { return .failure(StreamError.jobNotFound) }

        let safeCursor = max(0, min(cursor, job.output.utf16.count))
        let startIndex = String.Index(utf16Offset: safeCursor, in: job.output)
        let delta = String(job.output[startIndex...])

        return .success([
            "delta": delta,
            "cursor": job.output.utf16.count,
            "done": job.done,
            "error": job.error ?? "",
        ])
    }

    func cancel(jobId: String) async {
        guard var job = jobs[jobId] else { return }
        job.task?.cancel()
        job.done = true
        jobs[jobId] = job
    }
}
