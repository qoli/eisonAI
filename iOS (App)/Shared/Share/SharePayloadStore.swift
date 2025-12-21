import Foundation

struct SharePayloadStore {
    private let fileManager = FileManager.default

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
}
