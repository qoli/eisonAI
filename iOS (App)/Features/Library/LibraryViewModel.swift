import Combine
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var entries: [RawHistoryEntry] = []
    @Published var errorMessage: String?
    @Published private(set) var favoriteFilenames: Set<String> = []

    private let store = RawLibraryStore()

    func reload() {
        do {
            errorMessage = nil
            entries = try store.listEntries()
            favoriteFilenames = try store.favoriteFilenameSet()
        } catch {
            errorMessage = error.localizedDescription
            entries = []
            favoriteFilenames = []
        }
    }

    func isFavorited(_ entry: RawHistoryEntry) -> Bool {
        favoriteFilenames.contains(entry.fileURL.lastPathComponent)
    }

    func toggleFavorite(_ entry: RawHistoryEntry) {
        let filename = entry.fileURL.lastPathComponent
        let makeFavorite = !favoriteFilenames.contains(filename)

        do {
            try store.setFavorite(filename: filename, sourceFileURL: entry.fileURL, isFavorite: makeFavorite)
            favoriteFilenames = try store.favoriteFilenameSet()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ entry: RawHistoryEntry) {
        do {
            try store.setFavorite(filename: entry.fileURL.lastPathComponent, sourceFileURL: entry.fileURL, isFavorite: false)
            try store.deleteItem(fileURL: entry.fileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
        reload()
    }

    func loadDetail(for entry: RawHistoryEntry) -> RawHistoryItem? {
        do {
            return try store.loadItem(fileURL: entry.fileURL)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

