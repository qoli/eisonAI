//
//  HistoryDetailView.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import SwiftUI

struct RawItemDetailView: View {
    var entry: RawHistoryEntry
    var loadDetail: (RawHistoryEntry) -> RawHistoryItem?

    @State private var item: RawHistoryItem?
    @State private var isTagEditorPresented = false

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

                            Button("Edit Tags") {
                                isTagEditorPresented = true
                            }
                            .font(.footnote)
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
        .sheet(isPresented: $isTagEditorPresented, onDismiss: {
            item = loadDetail(entry)
        }) {
            TagEditorView(fileURL: entry.fileURL, title: "Tags")
        }
        .task {
            item = loadDetail(entry)
        }
    }
}
