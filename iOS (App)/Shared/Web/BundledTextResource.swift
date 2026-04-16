import Foundation

enum BundledTextResource {
    static func loadUTF8(
        name: String,
        ext: String,
        embeddedExtensionBundleID: String = "com.qoli.eisonAI.Extension"
    ) -> String? {
        if let text = loadUTF8(from: Bundle.main, name: name, ext: ext) {
            return text
        }

        if let extensionBundleURL = resolveEmbeddedExtensionBundleURL(bundleID: embeddedExtensionBundleID),
           let extensionBundle = Bundle(url: extensionBundleURL) {
            if let text = loadUTF8(from: extensionBundle, name: name, ext: ext) {
                return text
            }
        }

        return nil
    }

    private static func loadUTF8(from bundle: Bundle, name: String, ext: String) -> String? {
        let candidateSubdirectories = [nil, "Resources", "BrowserRuntime"]
        for subdirectory in candidateSubdirectories {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory),
               let text = loadNonEmptyUTF8(from: url) {
                return text
            }
        }

        guard let resourcesURL = bundle.resourceURL else { return nil }
        guard
            let enumerator = FileManager.default.enumerator(
                at: resourcesURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        else {
            return nil
        }

        let expectedFilename = "\(name).\(ext)"
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == expectedFilename else { continue }
            if let text = loadNonEmptyUTF8(from: fileURL) {
                return text
            }
        }

        return nil
    }

    private static func loadNonEmptyUTF8(from url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func resolveEmbeddedExtensionBundleURL(bundleID: String) -> URL? {
        guard let pluginsURL = Bundle.main.builtInPlugInsURL else { return nil }
        guard
            let pluginURLs = try? FileManager.default.contentsOfDirectory(
                at: pluginsURL,
                includingPropertiesForKeys: nil
            )
        else { return nil }

        let extensionBundle = pluginURLs
            .filter { $0.pathExtension == "appex" }
            .compactMap(Bundle.init(url:))
            .first(where: { $0.bundleIdentifier == bundleID })

        return extensionBundle?.bundleURL
    }
}
