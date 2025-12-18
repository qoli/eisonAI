//
//  RawLibraryStore.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import CryptoKit
import Foundation

struct RawLibraryStore {
    private let fileManager = FileManager.default
    private let rawLibraryMaxItems = 200

    private func itemsDirectoryURL() throws -> URL {
        guard
            let containerURL = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: AppConfig.appGroupIdentifier
            )
        else {
            throw NSError(
                domain: "EisonAI.RawLibrary",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "App Group container is unavailable."]
            )
        }

        var url = containerURL
        for component in AppConfig.rawLibraryItemsPathComponents {
            url.appendPathComponent(component, isDirectory: true)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }

    private static let filenameTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
        return formatter
    }()

    private func parseTimestampFromRawLibraryFilename(_ filename: String) -> Date? {
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        guard let range = base.range(of: "__") else { return nil }
        let timestamp = String(base[range.upperBound...])
        return Self.filenameTimestampFormatter.date(from: timestamp)
    }

    @discardableResult
    private func enforceRawLibraryLimit(in directoryURL: URL) throws -> Int {
        let items = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let jsonFiles = items.filter { $0.pathExtension.lowercased() == "json" }
        guard jsonFiles.count > rawLibraryMaxItems else { return 0 }

        let sorted = jsonFiles.sorted { lhs, rhs in
            let leftDate = parseTimestampFromRawLibraryFilename(lhs.lastPathComponent) ?? .distantPast
            let rightDate = parseTimestampFromRawLibraryFilename(rhs.lastPathComponent) ?? .distantPast
            if leftDate != rightDate { return leftDate < rightDate }
            return lhs.lastPathComponent < rhs.lastPathComponent
        }

        let deleteCount = sorted.count - rawLibraryMaxItems
        for fileURL in sorted.prefix(deleteCount) {
            try? fileManager.removeItem(at: fileURL)
        }
        return deleteCount
    }

    func listEntries() throws -> [RawHistoryEntry] {
        let directoryURL = try itemsDirectoryURL()
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let jsonFiles = fileURLs
            .filter { $0.pathExtension.lowercased() == "json" }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var entries: [RawHistoryEntry] = []
        entries.reserveCapacity(jsonFiles.count)

        for fileURL in jsonFiles {
            do {
                let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                let metadata = try decoder.decode(RawHistoryItemMetadata.self, from: data)
                entries.append(RawHistoryEntry(fileURL: fileURL, metadata: metadata))
            } catch {
                // Ignore malformed entries; they can be deleted from the filesystem if needed.
            }
        }

        return entries.sorted { lhs, rhs in
            if lhs.metadata.createdAt != rhs.metadata.createdAt {
                return lhs.metadata.createdAt > rhs.metadata.createdAt
            }
            return lhs.fileURL.lastPathComponent > rhs.fileURL.lastPathComponent
        }
    }

    func loadItem(fileURL: URL) throws -> RawHistoryItem {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        return try decoder.decode(RawHistoryItem.self, from: data)
    }

    func deleteItem(fileURL: URL) throws {
        try fileManager.removeItem(at: fileURL)
    }

    @discardableResult
    func saveRawItem(
        url: String,
        title: String,
        articleText: String,
        summaryText: String,
        systemPrompt: String,
        userPrompt: String,
        modelId: String
    ) throws -> (id: String, filename: String) {
        let directoryURL = try itemsDirectoryURL()

        let createdAt = Date()
        let id = UUID().uuidString
        let timestamp = Self.filenameTimestampFormatter.string(from: createdAt)

        let normalizedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArticle = articleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSummary = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)

        let filename: String
        let shouldReplaceExistingForURL = normalizedURL.lowercased().hasPrefix("http://") || normalizedURL.lowercased().hasPrefix("https://")
        if shouldReplaceExistingForURL {
            let urlHash = sha256Hex(normalizedURL)
            filename = "\(urlHash)__\(timestamp).json"

            let existing = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            let prefix = "\(urlHash)__"
            for fileURL in existing where fileURL.pathExtension.lowercased() == "json" {
                if fileURL.lastPathComponent.hasPrefix(prefix) {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        } else {
            filename = "clipboard__\(timestamp).json"
        }

        let item = RawHistoryItem(
            v: 1,
            id: id,
            createdAt: createdAt,
            url: normalizedURL,
            title: normalizedTitle,
            articleText: normalizedArticle,
            summaryText: normalizedSummary,
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

        _ = try enforceRawLibraryLimit(in: directoryURL)
        return (id, filename)
    }

    func clearAll() throws {
        let directoryURL = try itemsDirectoryURL()
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "json" {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func sha256Hex(_ value: String) -> String {
        let data = Data(value.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
