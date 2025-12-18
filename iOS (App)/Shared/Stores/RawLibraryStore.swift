//
//  RawLibraryStore.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import Foundation

struct RawLibraryStore {
    private let fileManager = FileManager.default

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
}
