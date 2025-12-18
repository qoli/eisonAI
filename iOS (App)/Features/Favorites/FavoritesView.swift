//
//  FavoritesView.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import SwiftUI

struct FavoritesView: View {
    @StateObject private var viewModel = FavoritesViewModel()
    @State private var showClearConfirmation = false

    var body: some View {
        List {
            if let error = viewModel.errorMessage, !error.isEmpty {
                Section {
                    Text(error)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(viewModel.entries) { entry in
                    NavigationLink {
                        RawItemDetailView(entry: entry, loadDetail: viewModel.loadDetail)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.metadata.title.isEmpty ? "(no title)" : entry.metadata.title)
                                .font(.headline)
                                .lineLimit(2)

                            if !entry.metadata.url.isEmpty {
                                Text(entry.metadata.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Text(entry.metadata.summaryText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)

                            Text(entry.metadata.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.unfavorite(entry)
                        } label: {
                            Text("Unfavorite")
                        }
                    }
                }
            } header: {
                Text("Favorites (\(viewModel.entries.count))")
            }
        }
        .navigationTitle("Favorites")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear All", role: .destructive) {
                    showClearConfirmation = true
                }
                .disabled(viewModel.entries.isEmpty)
            }
        }
        .confirmationDialog(
            "Clear all favorites?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                viewModel.clearAll()
            }
        }
        .refreshable {
            viewModel.reload()
        }
        .task {
            viewModel.reload()
        }
        .onAppear {
            viewModel.reload()
        }
    }
}
