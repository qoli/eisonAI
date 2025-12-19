import SwiftUI

struct LibraryItemDetailView: View {
    var entry: RawHistoryEntry
    var isFavorite: Bool
    var loadDetail: (RawHistoryEntry) -> RawHistoryItem?

    @State private var item: RawHistoryItem?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let item {
                    prompts(item: item)
                    outputs(item: item)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(16)
        }
        .navigationTitle("Material")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            item = loadDetail(entry)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry.metadata.title.isEmpty ? "(no title)" : entry.metadata.title)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)

                if isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Favorite")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.dateFormatter.string(from: entry.metadata.createdAt))
                Text(entry.metadata.modelId)
                Text(entry.fileURL.lastPathComponent)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let url = URL(string: entry.metadata.url), !entry.metadata.url.isEmpty {
                Link(destination: url) {
                    Label(entry.metadata.url, systemImage: "link")
                        .font(.caption)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private func prompts(item: RawHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !item.systemPrompt.isEmpty {
                TextSection(title: "System Prompt", text: item.systemPrompt)
            }
            if !item.userPrompt.isEmpty {
                TextSection(title: "User Prompt", text: item.userPrompt)
            }
        }
    }

    @ViewBuilder
    private func outputs(item: RawHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !item.summaryText.isEmpty {
                TextSection(title: "Summary", text: item.summaryText)
            }
            if !item.articleText.isEmpty {
                TextSection(title: "Article", text: item.articleText)
            }
        }
    }
}

private struct TextSection: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

