import Foundation

enum BundledTextResource {
    static func loadUTF8(
        name: String,
        ext: String,
        embeddedExtensionBundleID: String = "com.qoli.eisonAI.Extension"
    ) -> String? {
        if let text = loadTrimmedUTF8(from: Bundle.main.url(forResource: name, withExtension: ext)) {
            return text
        }

        if let text = loadTrimmedUTF8(
            from: Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources")
        ) {
            return text
        }

        if let extensionBundleURL = resolveEmbeddedExtensionBundleURL(bundleID: embeddedExtensionBundleID),
           let extensionBundle = Bundle(url: extensionBundleURL) {
            if let text = loadTrimmedUTF8(
                from: extensionBundle.url(forResource: name, withExtension: ext)
            ) {
                return text
            }

            if let text = loadTrimmedUTF8(
                from: extensionBundle.url(forResource: name, withExtension: ext, subdirectory: "Resources")
            ) {
                return text
            }
        }

        #if DEBUG
            // The simulator-only app target does not embed the Safari extension bundle,
            // so fall back to the checked-out source asset during development.
            if let text = loadTrimmedUTF8(from: developmentResourceURL(name: name, ext: ext)) {
                return text
            }
        #endif

        return nil
    }

    private static func loadTrimmedUTF8(from url: URL?) -> String? {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
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

    #if DEBUG
        private static func developmentResourceURL(name: String, ext: String) -> URL? {
            let projectRootURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()

            let resourceURL = projectRootURL
                .appendingPathComponent("Shared (Extension)", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("\(name).\(ext)", isDirectory: false)

            return FileManager.default.fileExists(atPath: resourceURL.path) ? resourceURL : nil
        }
    #endif
}
