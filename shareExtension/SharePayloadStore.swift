import Foundation

struct SharePayloadStore {
    private let fileManager = FileManager.default
    private let appGroupIdentifier = "group.com.qoli.eisonAI"
    private let payloadsPathComponents = ["SharePayloads"]

    enum SaveOutcome {
        case saved(URL)
        case duplicate
    }

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

    private func containsURL(_ url: String) throws -> Bool {
        let dirURL = try payloadsDirectoryURL()
        let files = try fileManager.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for file in files where file.pathExtension == "json" {
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
