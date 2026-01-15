import CloudKit
import CryptoKit
import Foundation

struct RawLibraryFile {
    let path: String
    let filename: String
    let data: Data
    let modificationDate: Date?
    let deletedAt: Date?

    init(path: String, filename: String, data: Data, modificationDate: Date? = nil, deletedAt: Date? = nil) {
        self.path = path
        self.filename = filename
        self.data = data
        self.modificationDate = modificationDate
        self.deletedAt = deletedAt
    }
}

enum RawLibraryCloudDatabaseError: Error {
    case missingField(String)
    case missingAsset(recordID: CKRecord.ID)
    case missingAssetFileURL(recordID: CKRecord.ID)
    case saveCompletedWithoutRecord
}

final class RawLibraryCloudDatabase {
    static let shared = RawLibraryCloudDatabase()
    static var isLoggingEnabled = true

    private let recordType = "RawLibraryFile"
    private let database: CKDatabase

    init(containerID: String = "iCloud.com.qoli.eisonAI") {
        database = CKContainer(identifier: containerID).privateCloudDatabase
        log("init container=\(containerID) database=private")
    }

    enum Field: String {
        case filename
        case path
        case filedata
        case deletedAt
    }

    func saveFile(_ file: RawLibraryFile) async throws -> RawLibraryFile {
        let recordID = CKRecord.ID(recordName: Self.recordName(for: file.path))
        log("saveFile start path=\(file.path) recordID=\(recordID.recordName)")
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record[Field.filename.rawValue] = file.filename as NSString
        record[Field.path.rawValue] = file.path as NSString
        record[Field.deletedAt.rawValue] = nil

        let (asset, tempURL) = try makeAsset(from: file.data)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        record[Field.filedata.rawValue] = asset

        let savedRecord = try await saveRecord(record)
        log("saveFile success path=\(file.path) recordID=\(recordID.recordName)")
        return RawLibraryFile(
            path: file.path,
            filename: file.filename,
            data: file.data,
            modificationDate: savedRecord.modificationDate,
            deletedAt: nil
        )
    }

    func saveFile(path: String, filename: String, data: Data) async throws -> RawLibraryFile {
        let file = RawLibraryFile(path: path, filename: filename, data: data)
        return try await saveFile(file)
    }

    func saveTombstone(path: String, deletedAt: Date = Date()) async throws -> RawLibraryFile {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        let recordID = CKRecord.ID(recordName: Self.recordName(for: path))
        log("saveTombstone start path=\(path) recordID=\(recordID.recordName)")
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record[Field.filename.rawValue] = filename as NSString
        record[Field.path.rawValue] = path as NSString
        record[Field.deletedAt.rawValue] = deletedAt as NSDate

        let (asset, tempURL) = try makeAsset(from: Data())
        defer { try? FileManager.default.removeItem(at: tempURL) }
        record[Field.filedata.rawValue] = asset

        let savedRecord = try await saveRecord(record)
        log("saveTombstone success path=\(path) recordID=\(recordID.recordName)")
        return RawLibraryFile(
            path: path,
            filename: filename,
            data: Data(),
            modificationDate: savedRecord.modificationDate,
            deletedAt: deletedAt
        )
    }

    func fetchFile(path: String) async throws -> RawLibraryFile? {
        let recordID = CKRecord.ID(recordName: Self.recordName(for: path))
        log("fetchFile start path=\(path) recordID=\(recordID.recordName)")
        guard let record = try await fetchRecord(recordID: recordID) else { return nil }
        log("fetchFile found path=\(path) recordID=\(recordID.recordName)")
        return try mapRecord(record)
    }

    func fetchFileData(path: String) async throws -> Data? {
        guard let file = try await fetchFile(path: path) else { return nil }
        return file.data
    }

    func fetchAllPaths(prefix: String?) async throws -> [String] {
        log("fetchAllPaths start prefix=\(prefix ?? "nil")")
        let records = try await fetchRecords(predicate: predicateForPrefix(prefix))
        log("fetchAllPaths success count=\(records.count) prefix=\(prefix ?? "nil")")
        return records.compactMap { $0[Field.path.rawValue] as? String }
    }

    func fetchAllRecords(prefix: String?) async throws -> [RawLibraryFile] {
        log("fetchAllRecords start prefix=\(prefix ?? "nil")")
        let records = try await fetchRecords(predicate: predicateForPrefix(prefix))
        log("fetchAllRecords success count=\(records.count) prefix=\(prefix ?? "nil")")
        return try records.map { try mapRecord($0) }
    }

    func deleteFile(path: String) async throws {
        let recordID = CKRecord.ID(recordName: Self.recordName(for: path))
        log("deleteFile start path=\(path) recordID=\(recordID.recordName)")
        _ = try await deleteRecord(recordID: recordID)
        log("deleteFile success path=\(path) recordID=\(recordID.recordName)")
    }

    func deleteAll(prefix: String?) async throws -> Int {
        log("deleteAll start prefix=\(prefix ?? "nil")")
        let records = try await fetchRecords(predicate: predicateForPrefix(prefix))
        let recordIDs = records.map { $0.recordID }
        let deleted = try await deleteRecords(recordIDs: recordIDs)
        log("deleteAll success deleted=\(deleted) prefix=\(prefix ?? "nil")")
        return deleted
    }

    // MARK: - Helpers

    static func recordName(for path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func mapRecord(_ record: CKRecord) throws -> RawLibraryFile {
        guard let filename = record[Field.filename.rawValue] as? String else {
            throw RawLibraryCloudDatabaseError.missingField(Field.filename.rawValue)
        }
        guard let path = record[Field.path.rawValue] as? String else {
            throw RawLibraryCloudDatabaseError.missingField(Field.path.rawValue)
        }
        let data = try extractData(from: record)
        let deletedAt = record[Field.deletedAt.rawValue] as? Date
        return RawLibraryFile(
            path: path,
            filename: filename,
            data: data,
            modificationDate: record.modificationDate,
            deletedAt: deletedAt
        )
    }

    private func extractData(from record: CKRecord) throws -> Data {
        guard let asset = record[Field.filedata.rawValue] as? CKAsset else {
            throw RawLibraryCloudDatabaseError.missingAsset(recordID: record.recordID)
        }
        guard let url = asset.fileURL else {
            throw RawLibraryCloudDatabaseError.missingAssetFileURL(recordID: record.recordID)
        }
        return try Data(contentsOf: url)
    }

    private func makeAsset(from data: Data) throws -> (asset: CKAsset, url: URL) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: tempURL, options: [.atomic])
        return (CKAsset(fileURL: tempURL), tempURL)
    }

    private func fetchRecord(recordID: CKRecord.ID) async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withRecordID: recordID) { record, error in
                if let error = error as? CKError, error.code == .unknownItem {
                    self.log("fetchRecord missing recordID=\(recordID.recordName)")
                    continuation.resume(returning: nil)
                    return
                }
                if let error = error {
                    self.log("fetchRecord error recordID=\(recordID.recordName) error=\(error)")
                    continuation.resume(throwing: error)
                    return
                }
                self.log("fetchRecord success recordID=\(recordID.recordName)")
                continuation.resume(returning: record)
            }
        }
    }

    private func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .allKeys
            operation.isAtomic = true
            operation.database = database

            var savedRecord: CKRecord?
            var opError: Error?

            operation.perRecordCompletionBlock = { record, error in
                if let error = error {
                    self.log("saveRecord perRecord error recordID=\(record.recordID.recordName) error=\(error)")
                    opError = error
                    return
                }
                savedRecord = record
            }

            operation.modifyRecordsCompletionBlock = { _, _, error in
                if let error = opError ?? error {
                    self.log("saveRecord completion error error=\(error)")
                    continuation.resume(throwing: error)
                    return
                }
                if let savedRecord {
                    self.log("saveRecord completion success recordID=\(savedRecord.recordID.recordName)")
                    continuation.resume(returning: savedRecord)
                } else {
                    self.log("saveRecord completion error missing record")
                    continuation.resume(throwing: RawLibraryCloudDatabaseError.saveCompletedWithoutRecord)
                }
            }

            database.add(operation)
        }
    }

    private func predicateForPrefix(_ prefix: String?) -> NSPredicate {
        if let prefix, !prefix.isEmpty {
            return NSPredicate(format: "%K BEGINSWITH %@", Field.path.rawValue, prefix)
        }
        return NSPredicate(value: true)
    }

    private func fetchRecords(predicate: NSPredicate) async throws -> [CKRecord] {
        var allRecords: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        var page = 0

        repeat {
            let operation: CKQueryOperation
            if let cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else {
                let query = CKQuery(recordType: recordType, predicate: predicate)
                operation = CKQueryOperation(query: query)
            }

            operation.database = database

            var pageRecords: [CKRecord] = []
            operation.recordFetchedBlock = { record in
                pageRecords.append(record)
            }

            cursor = try await withCheckedThrowingContinuation { continuation in
                operation.queryCompletionBlock = { nextCursor, error in
                    if let error = error {
                        self.log("fetchRecords error page=\(page) error=\(error)")
                        continuation.resume(throwing: error)
                        return
                    }
                    self.log("fetchRecords page=\(page) count=\(pageRecords.count) hasMore=\(nextCursor != nil)")
                    continuation.resume(returning: nextCursor)
                }
                database.add(operation)
            }

            allRecords.append(contentsOf: pageRecords)
            page += 1
        } while cursor != nil

        return allRecords
    }

    private func deleteRecord(recordID: CKRecord.ID) async throws -> CKRecord.ID? {
        try await withCheckedThrowingContinuation { continuation in
            database.delete(withRecordID: recordID) { deletedID, error in
                if let error = error {
                    self.log("deleteRecord error recordID=\(recordID.recordName) error=\(error)")
                    continuation.resume(throwing: error)
                    return
                }
                self.log("deleteRecord success recordID=\(recordID.recordName)")
                continuation.resume(returning: deletedID)
            }
        }
    }

    private func deleteRecords(recordIDs: [CKRecord.ID]) async throws -> Int {
        guard !recordIDs.isEmpty else { return 0 }
        var deletedCount = 0

        let chunkSize = 200
        let chunks = stride(from: 0, to: recordIDs.count, by: chunkSize).map {
            Array(recordIDs[$0 ..< min($0 + chunkSize, recordIDs.count)])
        }

        for chunk in chunks {
            let count = try await deleteRecordChunk(recordIDs: chunk)
            deletedCount += count
        }

        return deletedCount
    }

    private func deleteRecordChunk(recordIDs: [CKRecord.ID]) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
            operation.isAtomic = false
            operation.database = database

            operation.modifyRecordsCompletionBlock = { _, deletedRecordIDs, error in
                if let error = error {
                    self.log("deleteRecordChunk error count=\(recordIDs.count) error=\(error)")
                    continuation.resume(throwing: error)
                    return
                }
                self.log("deleteRecordChunk success deleted=\(deletedRecordIDs?.count ?? 0)")
                continuation.resume(returning: deletedRecordIDs?.count ?? 0)
            }

            database.add(operation)
        }
    }

    private func log(_ message: String) {
        guard Self.isLoggingEnabled else { return }
//        print("RawLibraryCloudDatabase: \(message)")
    }
}
