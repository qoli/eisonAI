//
//  FavoritesViewModel.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import Combine
import Foundation

@MainActor
final class FavoritesViewModel: ObservableObject {
    @Published var entries: [RawHistoryEntry] = []
    @Published var errorMessage: String?

    private let store = RawLibraryStore()

    func reload() {
        do {
            errorMessage = nil
            entries = try store.listFavoriteEntries()
        } catch {
            errorMessage = error.localizedDescription
            entries = []
        }
    }

    func delete(at offsets: IndexSet) {
        let targets = offsets.map { entries[$0] }
        for entry in targets {
            do {
                try store.setFavorite(
                    filename: entry.fileURL.lastPathComponent,
                    sourceFileURL: entry.fileURL,
                    isFavorite: false
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        reload()
    }

    func unfavorite(_ entry: RawHistoryEntry) {
        do {
            try store.setFavorite(
                filename: entry.fileURL.lastPathComponent,
                sourceFileURL: entry.fileURL,
                isFavorite: false
            )
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearAll() {
        do {
            try store.clearAllFavorites()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
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
