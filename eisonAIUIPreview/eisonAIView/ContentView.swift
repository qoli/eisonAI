//
//  ContentView.swift
//  eisonAIView
//
//  Created by 黃佁媛 on 12/19/25.
//

import SwiftUI

#Preview {
    NavigationStackView()
}

private enum LibraryMode: Int {
    case all = 0
    case favorites = 1
    case recent = 2
}

struct NavigationStackView: View {
    @State var searchText: String = ""
    @State private var selection: Int = 0
    @FocusState private var isSearchFocused: Bool
    @StateObject private var store = MockupLibraryStore()
    @State private var segmentedTransitionEdge: Edge = .trailing
    @State private var lastSelection: Int = 0

    private var mode: LibraryMode {
        LibraryMode(rawValue: selection) ?? .all
    }

    private var visibleItems: [LoadedMockupLibraryItem] {
        var base: [LoadedMockupLibraryItem]
        switch mode {
        case .all, .recent:
            base = store.items
        case .favorites:
            base = store.items.filter(\.isFavorite)
        }

        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return base }

        return base.filter { entry in
            let blob = [
                entry.item.title,
                entry.item.userPrompt,
                entry.item.systemPrompt ?? "",
                entry.item.summaryText,
                entry.item.articleText,
                entry.item.modelId,
            ]
            .joined(separator: "\n")
            .localizedLowercase

            return blob.contains(trimmedQuery.localizedLowercase)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                mainContent
                    .id(mode)
                    .navigationTitle("\(mode)".capitalized)
            }
            .animation(.easeInOut(duration: 0.25), value: selection)
            .onChange(of: selection) { newValue in
                segmentedTransitionEdge = newValue >= lastSelection ? .trailing : .leading
                lastSelection = newValue
            }
            .safeAreaInset(edge: .bottom) {
                searchBar
                    .padding(.bottom, isSearchFocused ? 12 : 0) // keyboard open: 12, closed: 0
            }
            .toolbar {
                ToolbarItem(placement: .title) {
                    Picker("", selection: $selection) {
                        Image(systemName: "magnifyingglass").tag(0)
                        Image(systemName: "star").tag(1)
                        Image(systemName: "clock").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let loadError = store.loadError {
            ContentUnavailableView {
                Label("MockupData Load Failed", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(loadError)
            } actions: {
                Button("Reload") { store.reload() }
            }
        } else if visibleItems.isEmpty {
            ContentUnavailableView {
                Label("No Material", systemImage: "tray.fill")
            } description: {
                Text("New Materials you receive will appear here.")
            } actions: {
                Button("Reload") { store.reload() }
            }
        } else {
            List(visibleItems) { entry in
                NavigationLink {
                    LibraryItemDetailView(item: entry.item, filename: entry.filename, isFavorite: entry.isFavorite)
                } label: {
                    LibraryItemRow(entry: entry)
                }
            }
            .listStyle(.plain)
            .animation(.easeInOut(duration: 0.15), value: visibleItems)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search your library ...", text: $searchText)
                .focused($isSearchFocused)
                .submitLabel(.done)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .glassEffect()
        .padding(.horizontal, isSearchFocused ? 16 : 60) // keyboard open: 16, closed: 60
        .animation(.easeInOut(duration: 0.25), value: isSearchFocused)
    }
}

private struct LibraryItemRow: View {
    var entry: LoadedMockupLibraryItem

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.item.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                if entry.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                        .accessibilityLabel("Favorite")
                }

                Spacer(minLength: 0)
            }

            Text(entry.item.subtitle)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let date = entry.item.createdAtDate {
                    Text(Self.dateFormatter.string(from: date))
                } else {
                    Text(entry.item.createdAt)
                }
                Text("·")
                Text(entry.item.modelId)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 6)
    }
}
