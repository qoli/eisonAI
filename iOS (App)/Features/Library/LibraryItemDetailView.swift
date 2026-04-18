import Drops
import Foundation
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
    @State private var isPreparingPDFExport: Bool = false
    @State private var isTagEditorPresented: Bool = false
    @State private var recentTagEntries: [RawLibraryTagCacheEntry] = []
    @State private var regenerateRequest: RegenerateRequest?
    @State private var exportedPDFURL: URL?
    @State private var pdfExportTask: Task<Void, Never>?

    private let rawLibraryStore = RawLibraryStore()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .medium
        return f
    }()

    private var isFavorite: Bool {
        viewModel.isFavorited(entry)
    }

    private var canRegenerateSummary: Bool {
        canRegenerateWithURL || canRegenerateWithArticle
    }

    private var canRegenerateWithURL: Bool {
        let urlString = entry.metadata.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return false }
        let scheme = url.scheme?.lowercased() ?? ""
        return scheme == "http" || scheme == "https"
    }

    private var canRegenerateWithArticle: Bool {
        let articleText = item?.articleText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !articleText.isEmpty
    }

    private var displayTitle: String {
        let itemTitle = item?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !itemTitle.isEmpty {
            return itemTitle
        }
        return entry.metadata.title.isEmpty ? "(no title)" : entry.metadata.title
    }

    private var fullTextToCopy: String {
        let articleText = item?.articleText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !articleText.isEmpty {
            return articleText
        }
        let summaryText = (item?.summaryText ?? entry.metadata.summaryText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return summaryText
    }

    private var pdfExportFileName: String {
        let trimmedTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = trimmedTitle.isEmpty ? "eisonai-note" : trimmedTitle
        return "\(safeTitle)-\(entry.metadata.id.prefix(8))"
    }

    private var pdfExportContent: LibraryItemPDFExportContent {
        let sourceURLText = entry.metadata.url.trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(
            title: displayTitle,
            createdAtText: Self.dateFormatter.string(from: entry.metadata.createdAt),
            sourceURLText: sourceURLText.isEmpty ? nil : sourceURLText,
            tags: item?.tags ?? entry.metadata.tags,
            summaryText: (item?.summaryText ?? entry.metadata.summaryText)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            articleText: item?.articleText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
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
                Button {
                    viewModel.toggleFavorite(entry)
                } label: {
                    Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.fill" : "star")
                }
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }

            // Detail-Menu
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        copyNoteLink()
                    } label: {
                        Label("Copy Note Link", systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button {
                        requestGenerateTitle(force: true)
                    } label: {
                        Label("Regenerate Title", systemImage: "arrow.clockwise")
                    }

                    Divider()

                    Button {
                        guard let request = makeRegenerateRequest() else { return }
                        regenerateRequest = request
                    } label: {
                        Label("Regenerate Summary", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!canRegenerateSummary)

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

            // bottomBar

            ToolbarItem(placement: .bottomBar) {
                Spacer()
            }

            ToolbarItem(placement: .bottomBar) {
                Menu {
                    if let url = URL(string: entry.metadata.url), !entry.metadata.url.isEmpty {
                        Link(destination: url) {
                            Label("Open Link", systemImage: "link")
                        }
                        .accessibilityLabel("Open Page URL")

                        Divider()
                    }

                    if let exportedPDFURL {
                        ShareLink(
                            item: exportedPDFURL,
                            preview: SharePreview(pdfExportFileName)
                        ) {
                            Label("Export PDF", systemImage: "doc.richtext")
                        }
                    } else {
                        Button {
                            preparePDFExport()
                        } label: {
                            Label(
                                isPreparingPDFExport ? "Preparing PDF…" : "Export PDF",
                                systemImage: "doc.richtext"
                            )
                        }
                        .disabled(isPreparingPDFExport)
                    }

                    if let url = URL(string: entry.metadata.url), !entry.metadata.url.isEmpty {
                        Divider()

                        ShareLink(
                            item: url,
                            subject: Text(displayTitle)
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Label("Actions", systemImage: "square.and.arrow.up")
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Content Actions")
            }
        }
        .sheet(isPresented: $isTagEditorPresented, onDismiss: {
            log("tag editor dismissed; reloading detail")
            item = viewModel.loadDetail(for: entry)
            log("tag editor reload done item=\(item != nil ? "ok" : "nil")")
            loadRecentTags()
            preparePDFExport()
        }) {
            TagEditorView(fileURL: entry.fileURL, title: "Tags")
        }
        .sheet(item: $regenerateRequest, onDismiss: {
            log("regenerate summary dismissed; reloading detail")
            item = viewModel.loadDetail(for: entry)
            log("regenerate summary reload done item=\(item != nil ? "ok" : "nil")")
            viewModel.reload()
            preparePDFExport()
        }) { request in
            ClipboardKeyPointSheet(
                input: request.input,
                saveMode: request.saveMode,
                showsErrorAlert: true
            )
        }
        .task {
            print(entry)
            log("detail task start path=\(entry.fileURL.lastPathComponent)")
            item = viewModel.loadDetail(for: entry)
            log("detail load result item=\(item != nil ? "ok" : "nil")")
            loadRecentTags()
            requestGenerateTitle(force: false)
            preparePDFExport()
        }
        .onDisappear {
            pdfExportTask?.cancel()
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
            preparePDFExport()
        } catch {
            log("apply recent tag failed: \(error.localizedDescription)")
        }
    }

    private func noteURLString() -> String {
        "eisonai://note?id=\(entry.metadata.id)"
    }

    private func copyNoteLink() {
        let value = noteURLString()
        copyToPasteboard(value)
    }

    private func copyFullText() {
        guard !fullTextToCopy.isEmpty else { return }
        copyToPasteboard(fullTextToCopy)
    }

    private func makeRegenerateRequest() -> RegenerateRequest? {
        let urlString = entry.metadata.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.isEmpty,
           let url = URL(string: urlString),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            let payload = SharePayload(
                id: UUID().uuidString,
                createdAt: Date(),
                url: urlString,
                text: nil,
                title: entry.metadata.title
            )
            return RegenerateRequest(
                input: .share(payload),
                saveMode: .updateExisting(
                    fileURL: entry.fileURL,
                    updateArticle: true,
                    updateTitle: true
                )
            )
        }

        let articleText = item?.articleText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !articleText.isEmpty else { return nil }
        let payload = SharePayload(
            id: UUID().uuidString,
            createdAt: Date(),
            url: nil,
            text: articleText,
            title: item?.title ?? entry.metadata.title
        )
        return RegenerateRequest(
            input: .share(payload),
            saveMode: .updateExisting(
                fileURL: entry.fileURL,
                updateArticle: false,
                updateTitle: false
            )
        )
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
                        LibraryTextDetailView(title: title, text: anchor.text.thinkTagstoMarkdonw())
                    } label: {
                        PlainTextSection(
                            title: title,
                            text: anchor.text.removingThinkTags()
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

    private func requestGenerateTitle(force: Bool) {
        guard !isGeneratingTitle else { return }

        isGeneratingTitle = true
        Task {
            defer {
                Task { @MainActor in
                    isGeneratingTitle = false
                }
            }

            let updated = await GenerationService.shared.generateTitleIfNeeded(force: force, fileURL: entry.fileURL)
            guard let updated else { return }
            await MainActor.run {
                self.item = updated
                viewModel.reload()
                preparePDFExport()
            }
        }
    }

    private func preparePDFExport() {
        let content = pdfExportContent
        guard !content.summaryText.isEmpty || !content.articleText.isEmpty else {
            log("pdf export skipped empty-content")
            exportedPDFURL = nil
            isPreparingPDFExport = false
            return
        }

        pdfExportTask?.cancel()
        isPreparingPDFExport = true

        let fileName = pdfExportFileName
        log(
            """
            pdf export prepare file=\(fileName).pdf \
            titleCount=\(content.title.count) \
            summaryCount=\(content.summaryText.count) \
            articleCount=\(content.articleText.count)
            """
        )
        pdfExportTask = Task {
            do {
                let url = try await LibraryItemPDFExporter.export(
                    content: content,
                    preferredFileName: fileName
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    exportedPDFURL = url
                    isPreparingPDFExport = false
                    log("pdf export ready path=\(url.path)")
                }
            } catch is CancellationError {
                await MainActor.run {
                    isPreparingPDFExport = false
                    log("pdf export canceled")
                }
            } catch {
                await MainActor.run {
                    exportedPDFURL = nil
                    isPreparingPDFExport = false
                    log("pdf export failed error=\(error.localizedDescription)")
                    showDrop(
                        title: "PDF Export Failed",
                        subtitle: error.localizedDescription
                    )
                }
            }
        }
    }

    private func log(_ message: String) {
        print("[SummaryRegen] \(message)")
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
            AppStructuredMarkdownView(
                markdown: noThinkText,
                allowsSelection: true
            )
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ifMacCatalyst { view in
                    view.padding(.horizontal)
                }
        }
    }
}

private struct LibraryTextDetailView: View {
    let title: String
    let text: String
    private let markdownLengthThreshold = 6000
    private var copyableText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if text.count > markdownLengthThreshold {
                    Text(text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    AppStructuredMarkdownView(
                        markdown: text,
                        allowsSelection: true
                    )
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Spacer()
            }

            ToolbarItem(placement: .bottomBar) {
                Button {
                    guard !copyableText.isEmpty else { return }
                    copyToPasteboard(copyableText)
                } label: {
                    Label("Copy Full Text", systemImage: "document.on.document")
                }
                .accessibilityLabel("Copy Full Text")
                .disabled(copyableText.isEmpty)
            }
        }
    }
}

private func copyToPasteboard(_ value: String) {
    #if canImport(UIKit)
        UIPasteboard.general.string = value
    #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    #endif

    let oneLine = value
        .components(separatedBy: .newlines)
        .joined()

    showDrop(
        title: "Copy To Pasteboard",
        subtitle: "\(String(oneLine.prefix(18)))..."
    )
}

private func showDrop(title: String, subtitle: String? = nil) {
    let drop = Drop(
        title: title,
        subtitle: subtitle ?? ""
    )
    Drops.show(drop)
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

private struct RegenerateRequest: Identifiable {
    let id = UUID().uuidString
    let input: KeyPointInput
    let saveMode: ClipboardKeyPointViewModel.SaveMode
}
