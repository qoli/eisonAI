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

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let appGroupIdentifier = "group.com.qoli.eisonAI"
    private let systemPromptKey = "eison.systemPrompt"
    private let rawLibraryMaxItems = 200
    private let defaultSystemPrompt = """
你是一個資料整理員。

Summarize this post in 5-6 sentences.
Emphasize the key insights and main takeaways.

以繁體中文輸出。
"""

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
            throw NSError(
                domain: "EisonAI.RawLibrary",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "App Group container is unavailable."]
            )
        }

        return containerURL
            .appendingPathComponent("RawLibrary", isDirectory: true)
            .appendingPathComponent("Items", isDirectory: true)
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

    private func enforceRawLibraryLimit(in directoryURL: URL) throws {
        let items = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let jsonFiles = items
            .filter { $0.pathExtension.lowercased() == "json" }
        guard jsonFiles.count > rawLibraryMaxItems else { return }

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
        for fileURL in existing where fileURL.pathExtension.lowercased() == "json" {
            if fileURL.lastPathComponent.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: fileURL)
            }
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

        try enforceRawLibraryLimit(in: directoryURL)
        return (id, filename)
    }

    private func loadSystemPrompt() -> String {
        guard let stored = sharedDefaults()?.string(forKey: systemPromptKey) else {
            return defaultSystemPrompt
        }
        if stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return defaultSystemPrompt
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

        os_log(.default, "[Eison-Native] Received native message: %@ (profile: %@)", String(describing: message), profile?.uuidString ?? "none")

        let responseMessage: [String: Any]
        if let dict = message as? [String: Any] {
            let command = (dict["command"] as? String) ?? (dict["name"] as? String) ?? ""
            switch command {
            case "getSystemPrompt":
                responseMessage = [
                    "v": 1,
                    "type": "response",
                    "name": "systemPrompt",
                    "payload": [
                        "prompt": loadSystemPrompt(),
                    ],
                ]
            case "setSystemPrompt":
                let prompt = dict["prompt"] as? String
                saveSystemPrompt(prompt)
                responseMessage = [
                    "v": 1,
                    "type": "response",
                    "name": "systemPrompt",
                    "payload": [
                        "prompt": loadSystemPrompt(),
                    ],
                ]
            case "resetSystemPrompt":
                saveSystemPrompt(nil)
                responseMessage = [
                    "v": 1,
                    "type": "response",
                    "name": "systemPrompt",
                    "payload": [
                        "prompt": loadSystemPrompt(),
                    ],
                ]
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

                    if summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        throw NSError(
                            domain: "EisonAI.RawLibrary",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "summaryText is required."]
                        )
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

                    responseMessage = [
                        "v": 1,
                        "type": "response",
                        "name": "saveRawItem",
                        "payload": [
                            "ok": true,
                            "id": result.id,
                            "filename": result.filename,
                        ],
                    ]
                } catch {
                    responseMessage = [
                        "v": 1,
                        "type": "error",
                        "name": "saveRawItem",
                        "payload": [
                            "code": "SAVE_FAILED",
                            "message": error.localizedDescription,
                        ],
                    ]
                }
            default:
                responseMessage = [
                    "v": 1,
                    "type": "error",
                    "name": "error",
                    "payload": [
                        "code": "UNKNOWN_COMMAND",
                        "message": "Unsupported native command: \(command)",
                    ],
                ]
            }
        } else {
            responseMessage = [
                "v": 1,
                "type": "error",
                "name": "error",
                "payload": [
                    "code": "INVALID_MESSAGE",
                    "message": "Expected an object message payload.",
                ],
            ]
        }

        let response = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            response.userInfo = [SFExtensionMessageKey: responseMessage]
        } else {
            response.userInfo = ["message": responseMessage]
        }

        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
