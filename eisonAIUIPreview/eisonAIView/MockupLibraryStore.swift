import Foundation
import Combine

@MainActor
final class MockupLibraryStore: ObservableObject {
    @Published private(set) var items: [LoadedMockupLibraryItem] = []
    @Published private(set) var loadError: String?

    init() {
        reload()
    }

    func reload() {
        do {
            let loaded = try Self.loadFromMockupData()
            items = loaded.sorted(by: Self.sortNewestFirst)
            loadError = nil
        } catch {
            items = []
            loadError = String(describing: error)
        }
    }

    private static func sortNewestFirst(_ a: LoadedMockupLibraryItem, _ b: LoadedMockupLibraryItem) -> Bool {
        switch (a.item.createdAtDate, b.item.createdAtDate) {
        case let (.some(da), .some(db)): return da > db
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return a.filename > b.filename
        }
    }

    private static func loadFromMockupData() throws -> [LoadedMockupLibraryItem] {
        guard let rawLibraryURL = MockupDataLocator.rawLibraryURL() else {
            throw MockupDataError.rawLibraryNotFound
        }

        let favoriteIndexURL = rawLibraryURL.appendingPathComponent("Favorite.json")
        let favoriteIndex: MockupFavoriteIndex? = try decodeIfExists(MockupFavoriteIndex.self, at: favoriteIndexURL)

        var favoriteFilenames = Set(favoriteIndex?.filenames ?? [])

        let itemsURL = rawLibraryURL.appendingPathComponent("Items", isDirectory: true)
        let favoriteItemsURL = rawLibraryURL.appendingPathComponent("FavoriteItems", isDirectory: true)

        var byId: [String: LoadedMockupLibraryItem] = [:]

        for entry in try loadItems(in: itemsURL, defaultFavorite: false) {
            byId[entry.id] = entry
        }

        for entry in try loadItems(in: favoriteItemsURL, defaultFavorite: true) {
            byId[entry.id] = entry
            favoriteFilenames.insert(entry.filename)
        }

        for (id, entry) in byId {
            byId[id] = LoadedMockupLibraryItem(
                item: entry.item,
                filename: entry.filename,
                isFavorite: entry.isFavorite || favoriteFilenames.contains(entry.filename)
            )
        }

        return Array(byId.values)
    }

    private static func loadItems(in directory: URL, defaultFavorite: Bool) throws -> [LoadedMockupLibraryItem] {
        var results: [LoadedMockupLibraryItem] = []
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "json" {
            let item = try decode(MockupLibraryItem.self, at: fileURL)
            results.append(
                LoadedMockupLibraryItem(
                    item: item,
                    filename: fileURL.lastPathComponent,
                    isFavorite: defaultFavorite
                )
            )
        }

        return results
    }

    private static func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }

    private static func decodeIfExists<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decode(type, at: url)
    }
}

enum MockupDataError: Error, LocalizedError {
    case rawLibraryNotFound

    var errorDescription: String? {
        switch self {
        case .rawLibraryNotFound:
            return "MockupData/RawLibrary not found in Bundle resources or workspace."
        }
    }
}

enum MockupDataLocator {
    static func rawLibraryURL() -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("MockupData/RawLibrary", isDirectory: true)
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }

        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let workspace = sourceDir.appendingPathComponent("MockupData/RawLibrary", isDirectory: true)
        if FileManager.default.fileExists(atPath: workspace.path) {
            return workspace
        }

        return nil
    }
}
