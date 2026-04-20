import Foundation

struct MLXCuratedModelCatalog: Codable {
    let version: Int
    let groups: [MLXCuratedModelGroup]
}

struct MLXCuratedModelGroup: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let models: [MLXCuratedModel]
}

struct MLXCuratedModel: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let repoID: String
    let summary: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case repoID = "repo_id"
        case summary
    }
}

enum MLXCuratedModelGroupsLoader {
    static func load() -> [MLXCuratedModelGroup] {
        let decoder = JSONDecoder()

        for url in candidateURLs() {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let catalog = try? decoder.decode(MLXCuratedModelCatalog.self, from: data) else { continue }
            return catalog.groups
        }

        return []
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []

        if let bundled = Bundle.main.url(forResource: "mlx-model-groups", withExtension: "json") {
            urls.append(bundled)
        }

        if let bundledResources = Bundle.main.url(
            forResource: "mlx-model-groups",
            withExtension: "json",
            subdirectory: "Resources"
        ) {
            urls.append(bundledResources)
        }

        #if DEBUG
            if let development = developmentResourceURL() {
                urls.append(development)
            }
        #endif

        return urls
    }

    #if DEBUG
        private static func developmentResourceURL() -> URL? {
            let projectRootURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()

            let resourceURL = projectRootURL
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("mlx-model-groups.json", isDirectory: false)

            return FileManager.default.fileExists(atPath: resourceURL.path) ? resourceURL : nil
        }
    #endif
}
