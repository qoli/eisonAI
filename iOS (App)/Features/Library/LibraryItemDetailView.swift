import Foundation
import MarkdownUI
import SwiftUI
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct LibraryItemDetailView: View {
    @ObservedObject var viewModel: LibraryViewModel
    var entry: RawHistoryEntry

    @Environment(\.dismiss) private var dismiss

    @State private var item: RawHistoryItem?
    @State private var isGeneratingTitle: Bool = false
    @State private var isTagEditorPresented: Bool = false
    @State private var recentTagEntries: [RawLibraryTagCacheEntry] = []

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
                    outputs(item: item)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(displayTitle)
        .navigationSubtitleCompat(Self.dateFormatter.string(from: entry.metadata.createdAt))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isGeneratingTitle {
                    ProgressView()
                }
            }

            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.toggleFavorite(entry)
                } label: {
                    Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.fill" : "star")
                }
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }

            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }

            // Detail-Menu
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let url = URL(string: entry.metadata.url), !entry.metadata.url.isEmpty {
                        Link(destination: url) {
                            Label("Open Link", systemImage: "link")
                        }
                        .accessibilityLabel("Open Page URL")

                        Divider()
                    }

                    Button {
                        copyNoteLink()
                    } label: {
                        Label("Copy Note Link", systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button {
                        generateTitleIfNeeded(force: true)
                    } label: {
                        Label("Regenerate Title", systemImage: "arrow.clockwise")
                    }

                    Divider()

                    Menu {
                        let recentTags = Array(recentTagEntries.prefix(5))
                        let currentTags = Set(item?.tags ?? [])
                        if recentTags.isEmpty {
                            Button("No Recent Tags") {}
                                .disabled(true)
                        } else {
                            ForEach(recentTags, id: \.tag) { entry in
                                if currentTags.contains(entry.tag) {
                                    Button {
                                        applyRecentTag(entry.tag)
                                    } label: {
                                        Label(entry.tag, systemImage: "tag.circle")
                                    }
                                } else {
                                    Button {
                                        applyRecentTag(entry.tag)
                                    } label: {
                                        Label(entry.tag, systemImage: "circle")
                                    }
                                }
                            }
                        }

                        Divider()

                        Button {
                            isTagEditorPresented = true
                        } label: {
                            Label("Edit Tags", systemImage: "tag.fill")
                        }
                    } label: {
                        Label("Tags", systemImage: "tag")
                        TagsText(tags: item?.tags ?? [])
                    }

                    Divider()

                    Menu {
                        Button(role: .destructive) {
                            viewModel.delete(entry)
                            dismiss()
                        } label: {
                            Label("Confirm Delete", systemImage: "trash")
                        }

                        Button(role: .cancel) {} label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                    } label: {
                        Label("Delete Record", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $isTagEditorPresented, onDismiss: {
            log("tag editor dismissed; reloading detail")
            item = viewModel.loadDetail(for: entry)
            log("tag editor reload done item=\(item != nil ? "ok" : "nil")")
            loadRecentTags()
        }) {
            TagEditorView(fileURL: entry.fileURL, title: "Tags")
        }
        .task {
            print(entry)
            log("detail task start path=\(entry.fileURL.lastPathComponent)")
            item = viewModel.loadDetail(for: entry)
            log("detail load result item=\(item != nil ? "ok" : "nil")")
            loadRecentTags()
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
    private func tagsSection(item: RawHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tags")
                    .font(.caption)
                    .fontWeight(.bold)

                Spacer()
            }

            if item.tags.isEmpty {
                Text("No tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TagChipsView(tags: item.tags)
            }
        }
    }

    private func loadRecentTags() {
        do {
            recentTagEntries = try rawLibraryStore.loadTagCache()
        } catch {
            log("load recent tags failed: \(error.localizedDescription)")
        }
    }

    private func applyRecentTag(_ tag: String) {
        guard let currentItem = item else { return }
        let updatedTags: [String]
        if currentItem.tags.contains(tag) {
            updatedTags = currentItem.tags.filter { $0 != tag }
        } else {
            updatedTags = currentItem.tags + [tag]
        }
        do {
            let result = try rawLibraryStore.updateTags(fileURL: entry.fileURL, tags: updatedTags)
            item = result.item
            recentTagEntries = result.cache
        } catch {
            log("apply recent tag failed: \(error.localizedDescription)")
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

    @ViewBuilder
    private func prompts(item: RawHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !item.systemPrompt.isEmpty {
                PlainTextSection(title: "System Prompt", text: item.systemPrompt)
            }
            if !item.userPrompt.isEmpty {
                PlainTextSection(title: "User Prompt", text: item.userPrompt)
            }
        }
    }

    @ViewBuilder
    private func outputs(item: RawHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            summarySection(item.summaryText)
            readingAnchorsSection(item.readingAnchors)
            articleSection(item.articleText)
        }
    }

    @ViewBuilder
    private func readingAnchorsSection(_ anchors: [ReadingAnchorChunk]?) -> some View {
        if let anchors, !anchors.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Reading Anchors")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                ForEach(anchors) { anchor in
                    let title = "Chunk \(anchor.index + 1) (\(anchor.tokenCount) tokens)"
                    NavigationLink {
                        LibraryTextDetailView(title: title, text: anchor.text)
                    } label: {
                        PlainTextSection(
                            title: title,
                            text: anchor.text
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func summarySection(_ text: String) -> some View {
        if !text.isEmpty {
            MarkdownSection(text: text)
        }
    }

    @ViewBuilder
    private func articleSection(_ text: String) -> some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Full Article")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                NavigationLink {
                    LibraryTextDetailView(title: "Article", text: text)
                } label: {
                    PlainTextSection(
                        title: "Article",
                        text: text
                    )
                }
                .buttonStyle(.plain)
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

private struct PlainTextSection: View {
    var title: String
    var text: String
    var lineLimit: Int? = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Text(text.removingBlankLines())
                .padding()
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(lineLimit)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MarkdownSection: View {
    var text: String

    var noThinkText: String {
        text.removingThinkTags()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Markdown(noThinkText)
                .markdownTheme(.librarySummary)
                .padding(.vertical, 12)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LibraryTextDetailView: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Markdown(text)
                    .markdownTheme(.librarySummary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
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

extension View {
    @ViewBuilder
    fileprivate func ifAvailableiOS26<Content: View>(_ transform: (Self) -> Content) -> some View {
        if #available(iOS 26.0, *) {
            transform(self)
        } else {
            self
        }
    }
}

extension View {
    @ViewBuilder
    func navigationSubtitleCompat(_ text: String) -> some View {
        if #available(iOS 26.0, *) {
            self.navigationSubtitle(text)
        } else {
            self
        }
    }
}

struct TagsText: View {
    var tags: [String]

    var tagsText: String {
        tags.map { "#\($0)" }.joined(separator: ", ")
    }

    var body: some View {
        Text(tagsText)
    }
}
