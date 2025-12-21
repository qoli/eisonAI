import Foundation
import MarkdownUI
import SwiftUI

struct LibraryItemDetailView: View {
    @ObservedObject var viewModel: LibraryViewModel
    var entry: RawHistoryEntry

    @State private var item: RawHistoryItem?
    @State private var isArticleExpanded: Bool = false
    @State private var isGeneratingTitle: Bool = false

    private let mlc = MLCClient()
    private let foundationModels = FoundationModelsClient()
    private let foundationSettings = FoundationModelsSettingsStore()
    private let rawLibraryStore = RawLibraryStore()

    private let titlePromptStore = TitlePromptStore()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .medium
        return f
    }()

    private var isFavorite: Bool {
        viewModel.isFavorited(entry)
    }

    private var displayTitle: String {
        let itemTitle = item?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !itemTitle.isEmpty {
            return itemTitle
        }
        return entry.metadata.title.isEmpty ? "(no title)" : entry.metadata.title
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
        .navigationTitle(displayTitle)
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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("重建標題") {
                        generateTitleIfNeeded(force: true)
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .task {
            isArticleExpanded = false
            item = viewModel.loadDetail(for: entry)
            generateTitleIfNeeded(force: false)
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

    private func generateTitleIfNeeded(force: Bool) {
        guard !isGeneratingTitle else { return }
        guard let item else { return }
        let currentTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !force && !currentTitle.isEmpty { return }

        isGeneratingTitle = true
        log("title generation start force=\(force) path=\(entry.fileURL.lastPathComponent)")
        Task {
            defer {
                Task { @MainActor in
                    isGeneratingTitle = false
                }
            }

            do {
                let systemPrompt = titlePromptStore.load()
                let userPrompt = buildTitleUserPrompt(for: item)
                let useFoundationModels = foundationSettings.isAppEnabled()
                    && FoundationModelsAvailability.currentStatus() == .available
                let stream: AsyncThrowingStream<String, Error>
                if useFoundationModels {
                    log("title generation using FoundationModels")
                    let prefix = clampText(userPrompt, maxChars: 800)
                    foundationModels.prewarm(systemPrompt: systemPrompt, promptPrefix: prefix)
                    stream = try await foundationModels.streamChat(
                        systemPrompt: systemPrompt,
                        userPrompt: userPrompt,
                        temperature: 0.4,
                        maximumResponseTokens: 128
                    )
                } else {
                    log("title generation using MLC")
                    try await mlc.loadIfNeeded()
                    stream = try await mlc.streamChat(systemPrompt: systemPrompt, userPrompt: userPrompt)
                }
                var output = ""
                for try await chunk in stream {
                    output += chunk
                }

                if !useFoundationModels, isQwen3Model(mlc.loadedModelID) {
                    log("title generation stripping <think> tags for qwen3")
                    output = stripThinkTags(output)
                }

                let title = sanitizeTitle(output)
                guard !title.isEmpty else { return }
                log("title generation result=\"\(title)\"")
                let updated = try rawLibraryStore.updateTitle(fileURL: entry.fileURL, title: title)
                await MainActor.run {
                    self.item = updated
                    viewModel.reload()
                }
            } catch {
                log("title generation error \(error.localizedDescription)")
                // No-op: failure strategy is silent.
            }
        }
    }

    private func buildTitleUserPrompt(for item: RawHistoryItem) -> String {
        let pieces = [
            item.summaryText,
            item.articleText,
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")

        let content = pieces.isEmpty ? item.url : pieces
        return clampText(content, maxChars: 4000)
    }

    private func sanitizeTitle(_ text: String) -> String {
        let strippedMarkdown = stripMarkdown(text)
        let trimmed = strippedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let stripped = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.trimmingCharacters(in: CharacterSet(charactersIn: "\"「」"))
    }

    private func clampText(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        let idx = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[..<idx])
    }

    private func isQwen3Model(_ modelID: String?) -> Bool {
        guard let modelID else { return false }
        return modelID.lowercased().contains("qwen3-0.6b")
    }

    private func stripThinkTags(_ text: String) -> String {
        let pattern = "(?is)<think>.*?</think>"
        var cleaned = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "<think>", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive)
        return cleaned
    }

    private func stripMarkdown(_ text: String) -> String {
        var output = text
        // Remove fenced code blocks
        output = output.replacingOccurrences(of: "(?s)```.*?```", with: "", options: .regularExpression)
        // Remove inline code
        output = output.replacingOccurrences(of: "`([^`]*)`", with: "$1", options: .regularExpression)
        // Images: ![alt](url) -> alt
        output = output.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\([^\\)]*\\)", with: "$1", options: .regularExpression)
        // Links: [text](url) -> text
        output = output.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]*\\)", with: "$1", options: .regularExpression)
        // Headings and blockquotes
        output = output.replacingOccurrences(of: "(?m)^(\\s{0,3}#{1,6}\\s+)", with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: "(?m)^(\\s*>\\s?)", with: "", options: .regularExpression)
        // Bold/italic markers
        output = output.replacingOccurrences(of: "(\\*\\*|__)", with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: "(\\*|_)", with: "", options: .regularExpression)
        // List markers
        output = output.replacingOccurrences(of: "(?m)^(\\s*[-+*]\\s+)", with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: "(?m)^(\\s*\\d+\\.\\s+)", with: "", options: .regularExpression)
        return output
    }

    private func log(_ message: String) {
        print("[TitleRebuild] \(message)")
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
