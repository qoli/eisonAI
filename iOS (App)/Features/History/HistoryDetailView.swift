//
//  HistoryDetailView.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct RawItemDetailView: View {
    var entry: RawHistoryEntry
    var loadDetail: (RawHistoryEntry) -> RawHistoryItem?

    @State private var item: RawHistoryItem?
    @State private var isTagEditorPresented = false
    @State private var recentTagEntries: [RawLibraryTagCacheEntry] = []

    private let rawLibraryStore = RawLibraryStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(entry.metadata.title.isEmpty ? "(no title)" : entry.metadata.title)
                    .font(.title3)
                    .bold()

                VStack(alignment: .leading, spacing: 6) {
                    if !entry.metadata.url.isEmpty {
                        Text(entry.metadata.url)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.metadata.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Model: \(entry.metadata.modelId)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let item {
                    GroupBox("Tags") {
                        VStack(alignment: .leading, spacing: 8) {
                            if item.tags.isEmpty {
                                Text("No tags")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                TagChipsView(tags: item.tags)
                            }

                            Menu {
                                let recentTags = Array(recentTagEntries.prefix(5))
                                if recentTags.isEmpty {
                                    Button("No recent tags") {}
                                        .disabled(true)
                                } else {
                                    ForEach(recentTags, id: \.tag) { entry in
                                        Button(entry.tag) {
                                            applyRecentTag(entry.tag)
                                        }
                                    }
                                }

                                Divider()

                                Button("Edit Tags") {
                                    isTagEditorPresented = true
                                }
                            } label: {
                                Label("Tag Menu", systemImage: "ellipsis.circle")
                                    .labelStyle(.iconOnly)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Summary") {
                        Text(item.summaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Article") {
                        Text(item.articleText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding()
        }
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Copy Note Link") {
                        copyNoteLink()
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isTagEditorPresented, onDismiss: {
            item = loadDetail(entry)
            loadRecentTags()
        }) {
            TagEditorView(fileURL: entry.fileURL, title: "Tags")
        }
        .task {
            item = loadDetail(entry)
            loadRecentTags()
        }
    }

    private func loadRecentTags() {
        do {
            recentTagEntries = try rawLibraryStore.loadTagCache()
        } catch {
            // Silent fail in UI
        }
    }

    private func applyRecentTag(_ tag: String) {
        guard let currentItem = item else { return }
        if currentItem.tags.contains(tag) { return }
        do {
            let result = try rawLibraryStore.updateTags(fileURL: entry.fileURL, tags: currentItem.tags + [tag])
            item = result.item
            recentTagEntries = result.cache
        } catch {
            // Silent fail in UI
        }
    }

    private func noteURLString() -> String {
        "eisonai://note?id=\(entry.metadata.id)"
    }

    private func copyNoteLink() {
        let value = noteURLString()
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}
