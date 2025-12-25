//
//  TagEditorViewModel.swift
//  iOS (App)
//
//  Created by Codex on 2025/12/25.
//

import Foundation

@MainActor
final class TagEditorViewModel: ObservableObject {
    @Published var tags: [String] = []
    @Published var cachedTags: [RawLibraryTagCacheEntry] = []
    @Published var newTag: String = ""
    @Published var errorMessage: String?

    private let store = RawLibraryStore()
    private var fileURL: URL?

    func load(fileURL: URL) {
        self.fileURL = fileURL
        do {
            errorMessage = nil
            let item = try store.loadItem(fileURL: fileURL)
            tags = normalizeTags(item.tags)
            cachedTags = try store.loadTagCache()
        } catch {
            errorMessage = error.localizedDescription
            tags = []
            cachedTags = []
        }
    }

    func addTagFromInput() {
        addTag(newTag)
    }

    func addTag(_ tag: String) {
        let normalized = normalizeTag(tag)
        guard !normalized.isEmpty else {
            newTag = ""
            return
        }
        guard !tags.contains(normalized) else {
            newTag = ""
            return
        }

        tags.append(normalized)
        newTag = ""
        persist()
    }

    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
        persist()
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            errorMessage = nil
            let result = try store.updateTags(fileURL: fileURL, tags: tags)
            tags = result.item.tags
            cachedTags = result.cache
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizeTag(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizeTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let normalized = normalizeTag(tag)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }
        return result
    }
}
