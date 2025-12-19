import SwiftUI

struct LibraryItemDetailView: View {
    var item: MockupLibraryItem
    var filename: String
    var isFavorite: Bool

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
                prompts
                outputs
            }
            .padding(16)
        }
        .navigationTitle("Material")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.displayTitle)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)

                if isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Favorite")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if let created = item.createdAtDate {
                    Text(Self.dateFormatter.string(from: created))
                } else {
                    Text(item.createdAt)
                }
                Text(item.modelId)
                Text(filename)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let url = URL(string: item.url), !item.url.isEmpty {
                Link(destination: url) {
                    Label(item.url, systemImage: "link")
                        .font(.caption)
                        .lineLimit(2)
                }
            }
        }
    }

    private var prompts: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let systemPrompt = item.systemPrompt, !systemPrompt.isEmpty {
                TextSection(title: "System Prompt", text: systemPrompt)
            }
            if !item.userPrompt.isEmpty {
                TextSection(title: "User Prompt", text: item.userPrompt)
            }
        }
    }

    private var outputs: some View {
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

#Preview {
    NavigationStack {
        LibraryItemDetailView(
            item: MockupLibraryItem(
                id: "preview",
                createdAt: "2025-12-18T07:26:49Z",
                modelId: "Qwen3-0.6B-q4f16_1-MLC",
                title: "",
                url: "",
                userPrompt: "(no title)\n\n【正文】\n…",
                systemPrompt: "將內容整理為簡短簡報，包含重點摘要。",
                summaryText: "…",
                articleText: "…",
                v: 1
            ),
            filename: "clipboard__20251218T072649706Z.json",
            isFavorite: true
        )
    }
}

