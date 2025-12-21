import Foundation

struct SharePayloadStore {
    private let fileManager = FileManager.default
    private let appGroupIdentifier = "group.com.qoli.eisonAI"
    private let payloadsPathComponents = ["SharePayloads"]

    private func appGroupContainerURL() throws -> URL {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
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
        for component in payloadsPathComponents {
            url.appendPathComponent(component, isDirectory: true)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
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
}
