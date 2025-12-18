import Foundation

enum BundledTextResource {
    static func loadUTF8(
        name: String,
        ext: String,
        embeddedExtensionBundleID: String = "com.qoli.eisonAI.Extension"
    ) -> String? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext),
           let text = try? String(contentsOf: url, encoding: .utf8)
        {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources"),
           let text = try? String(contentsOf: url, encoding: .utf8)
        {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        if let extensionBundleURL = resolveEmbeddedExtensionBundleURL(bundleID: embeddedExtensionBundleID),
           let extensionBundle = Bundle(url: extensionBundleURL)
        {
            if let url = extensionBundle.url(forResource: name, withExtension: ext),
               let text = try? String(contentsOf: url, encoding: .utf8)
            {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }

            if let url = extensionBundle.url(forResource: name, withExtension: ext, subdirectory: "Resources"),
               let text = try? String(contentsOf: url, encoding: .utf8)
            {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }

        return nil
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

