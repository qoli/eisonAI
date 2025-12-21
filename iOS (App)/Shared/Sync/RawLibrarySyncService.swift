import Foundation

actor RawLibrarySyncService {
    static let shared = RawLibrarySyncService()

    private let cloud = RawLibraryCloudDatabase.shared
    private let fileManager = FileManager.default

    private let itemsPrefix = "Items/"
    private let favoriteItemsPrefix = "FavoriteItems/"
    private let favoriteIndexPath = AppConfig.rawLibraryFavoriteIndexFilename
    private let manifestFilename = AppConfig.rawLibrarySyncManifestFilename

    func syncNow(progress: RawLibrarySyncProgressHandler? = nil) async throws {
        let syncDate = Date()
        var manifest = try loadManifest()

        let localFiles = try listLocalFiles()
        let remoteFiles = try await fetchRemoteFiles()

        var localByPath = Dictionary(uniqueKeysWithValues: localFiles.map { ($0.path, $0) })
        var remoteByPath = Dictionary(uniqueKeysWithValues: remoteFiles.map { ($0.path, $0) })

        for (path, entry) in manifest.files {
            if localByPath[path] == nil {
                if entry.lastDeletedAt == nil {
                    manifest.files[path]?.lastDeletedAt = syncDate
                }
            } else {
                manifest.files[path]?.lastDeletedAt = nil
            }
        }

        var allPaths = Set(localByPath.keys)
        allPaths.formUnion(remoteByPath.keys)
        allPaths.formUnion(manifest.files.keys)

        let sortedPaths = allPaths.sorted()
        let totalCount = sortedPaths.count
        progress?(RawLibrarySyncProgress(completed: 0, total: totalCount))

        var completedCount = 0
        for path in sortedPaths {
            let local = localByPath[path]
            let remote = remoteByPath[path]
            var entry = manifest.files[path] ?? ManifestEntry(path: path, recordName: RawLibraryCloudDatabase.recordName(for: path))

            if let local {
                entry.lastLocalModifiedAt = local.modificationDate
                entry.lastDeletedAt = nil
            }

            if let remote {
                entry.lastKnownServerModifiedAt = remote.modificationDate
            }

            if let remoteDeletedAt = remote?.deletedAt {
                if let local {
                    let localTime = local.modificationDate ?? .distantPast
                    if localTime > remoteDeletedAt {
                        let saved = try await uploadLocal(local)
                        entry.lastKnownServerModifiedAt = saved.modificationDate
                        entry.lastDeletedAt = nil
                    } else {
                        try deleteLocalFile(path: path)
                        entry.lastLocalModifiedAt = remoteDeletedAt
                        entry.lastDeletedAt = remoteDeletedAt
                    }
                } else {
                    entry.lastDeletedAt = remoteDeletedAt
                }

                manifest.files[path] = entry
                completedCount += 1
                progress?(RawLibrarySyncProgress(completed: completedCount, total: totalCount))
                continue
            }

            switch (local, remote) {
            case let (local?, remote?):
                let localTime = local.modificationDate ?? .distantPast
                let remoteTime = remote.modificationDate ?? .distantPast
                if localTime > remoteTime {
                    let saved = try await uploadLocal(local)
                    entry.lastKnownServerModifiedAt = saved.modificationDate
                } else if remoteTime > localTime {
                    try writeLocalFile(path: remote.path, data: remote.data, modifiedAt: remote.modificationDate)
                    entry.lastLocalModifiedAt = remote.modificationDate
                }

            case let (local?, nil):
                let saved = try await uploadLocal(local)
                entry.lastKnownServerModifiedAt = saved.modificationDate

            case let (nil, remote?):
                if let deletedAt = entry.lastDeletedAt {
                    let remoteTime = remote.modificationDate ?? .distantPast
                    if deletedAt > remoteTime {
                        let tombstone = try await cloud.saveTombstone(path: path, deletedAt: deletedAt)
                        entry.lastKnownServerModifiedAt = tombstone.modificationDate
                        entry.lastDeletedAt = deletedAt
                        manifest.files[path] = entry
                        completedCount += 1
                        progress?(RawLibrarySyncProgress(completed: completedCount, total: totalCount))
                        continue
                    }
                }

                try writeLocalFile(path: remote.path, data: remote.data, modifiedAt: remote.modificationDate)
                entry.lastLocalModifiedAt = remote.modificationDate
                entry.lastDeletedAt = nil

            case (nil, nil):
                if let deletedAt = entry.lastDeletedAt {
                    let tombstone = try await cloud.saveTombstone(path: path, deletedAt: deletedAt)
                    entry.lastKnownServerModifiedAt = tombstone.modificationDate
                    manifest.files[path] = entry
                    completedCount += 1
                    progress?(RawLibrarySyncProgress(completed: completedCount, total: totalCount))
                    continue
                } else {
                    manifest.files.removeValue(forKey: path)
                    completedCount += 1
                    progress?(RawLibrarySyncProgress(completed: completedCount, total: totalCount))
                    continue
                }
            }

            manifest.files[path] = entry
            completedCount += 1
            progress?(RawLibrarySyncProgress(completed: completedCount, total: totalCount))
        }

        manifest.updatedAt = syncDate
        try saveManifest(manifest)
    }

    func overwriteRemoteWithLocal() async throws {
        let syncDate = Date()
        var manifest = try loadManifest()
        let localFiles = try listLocalFiles()

        _ = try await cloud.deleteAll(prefix: itemsPrefix)
        _ = try await cloud.deleteAll(prefix: favoriteItemsPrefix)
        try? await cloud.deleteFile(path: favoriteIndexPath)

        manifest.files.removeAll()

        for local in localFiles {
            let saved = try await uploadLocal(local)
            var entry = ManifestEntry(path: local.path, recordName: RawLibraryCloudDatabase.recordName(for: local.path))
            entry.lastLocalModifiedAt = local.modificationDate
            entry.lastKnownServerModifiedAt = saved.modificationDate
            entry.lastDeletedAt = nil
            manifest.files[local.path] = entry
        }

        manifest.updatedAt = syncDate
        try saveManifest(manifest)
    }

    func recordLocalDeletions(paths: [String], deletedAt: Date = Date()) throws {
        guard !paths.isEmpty else { return }
        var manifest = try loadManifest()
        for path in paths {
            var entry = manifest.files[path] ?? ManifestEntry(
                path: path,
                recordName: RawLibraryCloudDatabase.recordName(for: path)
            )
            entry.lastDeletedAt = deletedAt
            entry.lastLocalModifiedAt = nil
            manifest.files[path] = entry
        }
        manifest.updatedAt = deletedAt
        try saveManifest(manifest)
    }

    // MARK: - Local Files

    private struct LocalFile {
        let path: String
        let filename: String
        let url: URL
        let modificationDate: Date?
    }

    private func listLocalFiles() throws -> [LocalFile] {
        let itemsDir = try directoryURL(pathComponents: AppConfig.rawLibraryItemsPathComponents)
        let favoriteItemsDir = try directoryURL(pathComponents: AppConfig.rawLibraryFavoriteItemsPathComponents)
        let rootDir = try rawLibraryRootURL()

        var files: [LocalFile] = []

        files.append(contentsOf: try listJSONFiles(in: itemsDir, prefix: itemsPrefix))
        files.append(contentsOf: try listJSONFiles(in: favoriteItemsDir, prefix: favoriteItemsPrefix))

        let favoriteIndexURL = rootDir.appendingPathComponent(favoriteIndexPath)
        if fileManager.fileExists(atPath: favoriteIndexURL.path) {
            files.append(try buildLocalFile(url: favoriteIndexURL, path: favoriteIndexPath))
        }

        return files
    }

    private func listJSONFiles(in directoryURL: URL, prefix: String) throws -> [LocalFile] {
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        var result: [LocalFile] = []
        result.reserveCapacity(fileURLs.count)

        for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "json" {
            let path = "\(prefix)\(fileURL.lastPathComponent)"
            result.append(try buildLocalFile(url: fileURL, path: path))
        }

        return result
    }

    private func buildLocalFile(url: URL, path: String) throws -> LocalFile {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let filename = url.lastPathComponent
        return LocalFile(path: path, filename: filename, url: url, modificationDate: values?.contentModificationDate)
    }

    private func uploadLocal(_ local: LocalFile) async throws -> RawLibraryFile {
        let data = try Data(contentsOf: local.url, options: [.mappedIfSafe])
        return try await cloud.saveFile(path: local.path, filename: local.filename, data: data)
    }

    private func writeLocalFile(path: String, data: Data, modifiedAt: Date?) throws {
        let root = try rawLibraryRootURL()
        let fileURL = root.appendingPathComponent(path)
        let parent = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)
        try data.write(to: fileURL, options: [.atomic])

        if let modifiedAt {
            try? fileManager.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: fileURL.path)
        }
    }

    private func deleteLocalFile(path: String) throws {
        let root = try rawLibraryRootURL()
        let fileURL = root.appendingPathComponent(path)
        try? fileManager.removeItem(at: fileURL)
    }

    // MARK: - Remote Files

    private func fetchRemoteFiles() async throws -> [RawLibraryFile] {
        var records = try await cloud.fetchAllRecords(prefix: itemsPrefix)
        records.append(contentsOf: try await cloud.fetchAllRecords(prefix: favoriteItemsPrefix))
        if let favorite = try await cloud.fetchFile(path: favoriteIndexPath) {
            records.append(favorite)
        }
        return records
    }

    // MARK: - Manifest

    private struct SyncManifest: Codable {
        var v: Int
        var updatedAt: Date
        var files: [String: ManifestEntry]
    }

    private struct ManifestEntry: Codable {
        var path: String
        var recordName: String
        var lastLocalModifiedAt: Date?
        var lastKnownServerModifiedAt: Date?
        var lastDeletedAt: Date?
    }

    private func loadManifest() throws -> SyncManifest {
        let url = try manifestURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return SyncManifest(v: 1, updatedAt: Date(), files: [:])
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SyncManifest.self, from: data)
    }

    private func saveManifest(_ manifest: SyncManifest) throws {
        let url = try manifestURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: [.atomic])
    }

    private func manifestURL() throws -> URL {
        let root = try rawLibraryRootURL()
        return root.appendingPathComponent(manifestFilename)
    }

    // MARK: - Paths

    private func appGroupContainerURL() throws -> URL {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: AppConfig.appGroupIdentifier
        ) else {
            throw NSError(
                domain: "EisonAI.RawLibrary.Sync",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "App Group container is unavailable."]
            )
        }
        return containerURL
    }

    private func rawLibraryRootURL() throws -> URL {
        var url = try appGroupContainerURL()
        for component in AppConfig.rawLibraryRootPathComponents {
            url.appendPathComponent(component, isDirectory: true)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }

    private func directoryURL(pathComponents: [String]) throws -> URL {
        var url = try appGroupContainerURL()
        for component in pathComponents {
            url.appendPathComponent(component, isDirectory: true)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }
}

struct RawLibrarySyncProgress: Sendable {
    let completed: Int
    let total: Int
}

typealias RawLibrarySyncProgressHandler = @Sendable (RawLibrarySyncProgress) -> Void
