import Foundation

struct SharePayloadStore {
    private let fileManager = FileManager.default
    enum SaveOutcome {
        case saved(URL)
        case duplicate
    }

    private func appGroupContainerURL() throws -> URL {
        guard
            let containerURL = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: AppConfig.appGroupIdentifier
            )
        else {
            throw NSError(
                domain: "EisonAI.SharePayload",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "App Group container is unavailable."]
            )
        }

        return containerURL
    }

    private func payloadsDirectoryURL() throws -> URL {
        var url = try appGroupContainerURL()
        for component in AppConfig.sharePayloadsPathComponents {
            url.appendPathComponent(component, isDirectory: true)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }

    private func payloadFileURL(id: String) throws -> URL {
        try payloadsDirectoryURL().appendingPathComponent("\(id).json", isDirectory: false)
    }

    private func pendingPayloadFileURLs() throws -> [URL] {
        let directoryURL = try payloadsDirectoryURL()
        let items = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return items.filter { $0.pathExtension.lowercased() == "json" }
    }

    func saveIfNotDuplicate(_ payload: SharePayload) throws -> SaveOutcome {
        if let url = payload.url?.trimmingCharacters(in: .whitespacesAndNewlines),
           !url.isEmpty,
           try containsURL(url)
        {
            return .duplicate
        }
        return .saved(try save(payload))
    }

    func save(_ payload: SharePayload) throws -> URL {
        let dirURL = try payloadsDirectoryURL()
        let fileURL = dirURL.appendingPathComponent("\(payload.id).json", isDirectory: false)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    func loadNextPending() throws -> SharePayload? {
        let items = try pendingPayloadFileURLs()
        guard !items.isEmpty else { return nil }

        let sorted = items.sorted { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if leftDate != rightDate { return leftDate < rightDate }
            return lhs.lastPathComponent < rhs.lastPathComponent
        }

        let fileURL = sorted[0]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let payload = try decoder.decode(SharePayload.self, from: data)
        try? fileManager.removeItem(at: fileURL)
        return payload
    }

    @discardableResult
    func clearAllPending() throws -> Int {
        let items = try pendingPayloadFileURLs()
        for url in items {
            try? fileManager.removeItem(at: url)
        }
        return items.count
    }

    func loadAndDelete(id: String) throws -> SharePayload? {
        let fileURL = try payloadFileURL(id: id)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let payload = try decoder.decode(SharePayload.self, from: data)

        try? fileManager.removeItem(at: fileURL)
        return payload
    }

    private func containsURL(_ url: String) throws -> Bool {
        let dirURL = try payloadsDirectoryURL()
        let files = try fileManager.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for file in files where file.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: file),
                  let payload = try? decoder.decode(SharePayload.self, from: data)
            else {
                continue
            }
            if payload.url == url {
                return true
            }
        }

        return false
    }
}
