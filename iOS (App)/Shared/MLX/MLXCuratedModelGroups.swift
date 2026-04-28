import Foundation
import OSLog

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
    private static let logger = Logger(subsystem: "com.qoli.eisonAI", category: "MLXCuratedModelGroupsLoader")

    static func load() -> [MLXCuratedModelGroup] {
        let decoder = JSONDecoder()
        let urls = candidateURLs()

        for url in urls {
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                logger.warning("Unable to read curated model index at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }

            do {
                let catalog = try decoder.decode(MLXCuratedModelCatalog.self, from: data)
                logger.notice("Loaded curated model index from \(url.path, privacy: .public) groups=\(catalog.groups.count)")
                return catalog.groups
            } catch {
                logger.error("Unable to decode curated model index at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }
        }

        if urls.isEmpty {
            logger.error("Curated model index not found in app bundle.")
        } else {
            logger.error("Curated model index candidates existed but none could be loaded.")
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
