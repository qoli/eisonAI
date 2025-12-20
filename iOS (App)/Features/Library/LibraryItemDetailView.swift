import MarkdownUI
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
                    .padding(12)
                    .glassedEffect(in: RoundedRectangle(cornerRadius: 12), interactive: false)

//                Divider().opacity(0.25)

                if let item {
                    outputs(item: item)
//                    prompts(item: item)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }
        .navigationTitle(entry.metadata.title.isEmpty ? "(no title)" : entry.metadata.title)
        .navigationBarTitleDisplayMode(.large)
        .task {
            item = loadDetail(entry)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
//            HStack(alignment: .firstTextBaseline, spacing: 10) {
//                Text(entry.metadata.title.isEmpty ? "(no title)" : entry.metadata.title)
//                    .font(.title3.weight(.semibold))
//                    .textSelection(.enabled)

//            }

            VStack(alignment: .leading, spacing: 4) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Favorite")
                }
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
                TextSection(title: "Summary", text: item.summaryText, isMarkdown: true)
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
    var isMarkdown: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if isMarkdown {
                Markdown(text)
                    .markdownTheme(.librarySummary)
                    .padding(.horizontal, isMarkdown ? 0 : 12)
                    .padding(.vertical, 12)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(text)
                    .padding()
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, isMarkdown ? 0 : 12)
        .padding(.vertical, 12)
        .background(
            Group {
                if isMarkdown {
                    Color.clear
                } else {
                    Color.clear
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        )
    }
}

import SwiftUI

extension View {
    @ViewBuilder
    func glassedEffect(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background {
                shape.glassed()
            }
        }
    }
}

extension Shape {
    func glassed() -> some View {
        fill(.ultraThinMaterial)
            .fill(
                .linearGradient(
                    colors: [
                        .primary.opacity(0.08),
                        .primary.opacity(0.05),
                        .primary.opacity(0.01),
                        .clear,
                        .clear,
                        .clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .stroke(.primary.opacity(0.2), lineWidth: 0.7)
    }
}
