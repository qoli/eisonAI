import MarkdownUI
import SwiftUI

struct LibraryItemDetailView: View {
    @ObservedObject var viewModel: LibraryViewModel
    var entry: RawHistoryEntry

    @State private var item: RawHistoryItem?
    @State private var isArticleExpanded: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .medium
        return f
    }()

    private var isFavorite: Bool {
        viewModel.isFavorited(entry)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let item {
                    Divider().opacity(0.3)
                    row()
                    Divider().opacity(0.3)
                    outputs(item: item)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(entry.metadata.title.isEmpty ? "(no title)" : entry.metadata.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.toggleFavorite(entry)
                } label: {
                    Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.fill" : "star")
                }
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let url = URL(string: entry.metadata.url), !entry.metadata.url.isEmpty {
                    Link(destination: url) {
                        Label("Open Link", systemImage: "link")
                    }
                    .accessibilityLabel("Open Page URL")
                }
            }
        }
        .task {
            isArticleExpanded = false
            item = viewModel.loadDetail(for: entry)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.dateFormatter.string(from: entry.metadata.createdAt))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func row() -> some View {
        HStack {
            Text("Date")
                .font(.caption)
                .fontWeight(.bold)

            Spacer()

            Text(Self.dateFormatter.string(from: entry.metadata.createdAt))
                .font(.caption)
                .foregroundColor(.secondary)
        }

        HStack {
            Text("Model")
                .font(.caption)
                .fontWeight(.bold)

            Spacer()

            Text(entry.metadata.modelId)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func prompts(item: RawHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !item.systemPrompt.isEmpty {
                TextSection(title: "System Prompt", text: item.systemPrompt, descirptionText: "")
            }
            if !item.userPrompt.isEmpty {
                TextSection(title: "User Prompt", text: item.userPrompt, descirptionText: "")
            }
        }
    }

    @ViewBuilder
    private func outputs(item: RawHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !item.summaryText.isEmpty {
                TextSection(title: "", text: item.summaryText, descirptionText: "", isMarkdown: true)
            }
            if !item.articleText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    TextSection(
                        title: "Article",
                        text: item.articleText,
                        descirptionText: "",
                        lineLimit: isArticleExpanded ? nil : 5
                    )
                    .overlay {
                        if !isArticleExpanded {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()

                                    Button {
                                        withAnimation(.easeInOut) {
                                            isArticleExpanded.toggle()
                                        }
                                    } label: {
                                        Label(
                                            isArticleExpanded ? "Collapse" : "Expand",
                                            systemImage: isArticleExpanded
                                                ? "chevron.up"
                                                : "chevron.down"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(isArticleExpanded ? "Collapse Article" : "Expand Article")
                                    .padding(.horizontal)
                                    .padding(.vertical)
                                    .glassedEffect(in: RoundedRectangle(cornerRadius: 12 + 6, style: .continuous), interactive: true)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TextSection: View {
    var title: String
    var text: String
    var descirptionText: String
    var isMarkdown: Bool = false
    var lineLimit: Int? = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if title != "" {
                Text(title)
                    .font(.headline)
            }

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
                    .lineLimit(lineLimit)
            }
        }
        .padding(.horizontal, isMarkdown ? 0 : 12)
        .padding(.vertical, isMarkdown ? 0 : 12)
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
