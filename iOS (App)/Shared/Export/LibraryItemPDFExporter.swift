import Foundation
import OSLog
import WebKit

struct LibraryItemPDFExportContent: Sendable {
    let title: String
    let createdAtText: String
    let sourceURLText: String?
    let tags: [String]
    let summaryText: String
    let articleText: String
}

enum LibraryItemPDFExporter {
    enum ExportError: LocalizedError {
        case failedToMeasureContent

        var errorDescription: String? {
            switch self {
            case .failedToMeasureContent:
                return "Unable to measure the PDF content."
            }
        }
    }

    private static let logger = Logger(subsystem: "com.qoli.eisonAI", category: "PDFExport")

    static func export(
        content: LibraryItemPDFExportContent,
        preferredFileName: String
    ) async throws -> URL {
        let artifact = try await Task.detached(priority: .utility) {
            try Task.checkCancellation()

            let safeName = sanitizedFileName(preferredFileName)
            let pdfURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(safeName)
                .appendingPathExtension("pdf")
            let htmlURL = pdfURL.deletingPathExtension().appendingPathExtension("html")
            let textURL = pdfURL.deletingPathExtension().appendingPathExtension("txt")

            log(
                """
                export start file=\(pdfURL.lastPathComponent) \
                titleCount=\(content.title.count) \
                summaryCount=\(content.summaryText.count) \
                articleCount=\(content.articleText.count) \
                tags=\(content.tags.count) \
                sourceURL=\(content.sourceURLText?.isEmpty == false ? "yes" : "no")
                """
            )
            log("summary preview: \(preview(content.summaryText.removingThinkTags()))")
            if !content.articleText.isEmpty {
                log("article preview: \(preview(content.articleText))")
            }

            try removeIfExists(at: pdfURL)
            try removeIfExists(at: htmlURL)
            try removeIfExists(at: textURL)

            let plainText = makeDebugText(content: content)
            let html = makeHTMLDocument(content: content)
            try plainText.write(to: textURL, atomically: true, encoding: .utf8)
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)

            log("sidecar text path=\(textURL.path) count=\(plainText.count)")
            log("sidecar html path=\(htmlURL.path) count=\(html.count)")

            return ExportArtifact(
                pdfURL: pdfURL,
                htmlURL: htmlURL,
                textURL: textURL
            )
        }.value

        try await renderPDF(from: artifact)
        log("export success path=\(artifact.pdfURL.path)")
        return artifact.pdfURL
    }

    static func sanitizedFileName(_ fileName: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "eisonai-export" : trimmed
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = fallback
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return cleaned.isEmpty ? "eisonai-export" : cleaned
    }

    private static func removeIfExists(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    @MainActor
    private static func renderPDF(from artifact: ExportArtifact) async throws {
        try Task.checkCancellation()
        let renderer = LibraryItemPDFWebRenderer()
        try await renderer.render(htmlURL: artifact.htmlURL, to: artifact.pdfURL)
    }

    private static func makeHTMLDocument(content: LibraryItemPDFExportContent) -> String {
        let trimmedTitle = content.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let pageTitle = trimmedTitle.isEmpty ? "eisonAI Export" : trimmedTitle
        let sourceURLText = content.sourceURLText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryHTML = MarkdownHTMLRenderer.render(
            markdown: content.summaryText.removingThinkTags().trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let articleHTML = MarkdownHTMLRenderer.render(
            markdown: content.articleText.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(pageTitle.htmlEscaped())</title>
          <style>
            :root {
              color-scheme: light;
              --text: #171717;
              --muted: #5f5f5f;
              --line: #dddddd;
              --soft: #f5f5f5;
              --code: #f3f4f6;
              --quote: #e5e7eb;
              --tag-bg: #f1f5f9;
              --tag-text: #334155;
              --link: #1d4ed8;
            }

            @page {
              size: A4;
              margin: 16mm 14mm 18mm;
            }

            html {
              -webkit-text-size-adjust: 100%;
              background: #fafafa;
            }

            body {
              margin: 0;
              padding: 28px 34px 40px;
              color: var(--text);
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
              font-size: 13px;
              line-height: 1.6;
              background: white;
            }

            article {
              width: min(100%, 720px);
              margin: 0 auto;
            }

            header {
              margin-bottom: 28px;
            }

            h1.document-title {
              margin: 0 0 10px;
              font-size: 28px;
              line-height: 1.22;
              font-weight: 760;
              letter-spacing: -0.02em;
            }

            .metadata {
              color: var(--muted);
              font-size: 11px;
            }

            .metadata-row + .metadata-row {
              margin-top: 4px;
            }

            .tags {
              margin-top: 12px;
              display: flex;
              flex-wrap: wrap;
              gap: 6px;
            }

            .tag {
              display: inline-block;
              padding: 3px 8px;
              border-radius: 999px;
              background: var(--tag-bg);
              color: var(--tag-text);
              font-size: 10px;
              font-weight: 600;
              letter-spacing: 0.01em;
            }

            section + section {
              margin-top: 34px;
            }

            h2.section-title {
              margin: 0 0 14px;
              font-size: 15px;
              line-height: 1.3;
              font-weight: 700;
              color: #2d2d2d;
              text-transform: uppercase;
              letter-spacing: 0.04em;
            }

            .markdown > :first-child {
              margin-top: 0;
            }

            .markdown > :last-child {
              margin-bottom: 0;
            }

            .markdown h1,
            .markdown h2,
            .markdown h3,
            .markdown h4,
            .markdown h5,
            .markdown h6 {
              margin: 1.25em 0 0.5em;
              color: #111111;
              line-height: 1.28;
            }

            .markdown h1 { font-size: 24px; }
            .markdown h2 { font-size: 20px; }
            .markdown h3 { font-size: 17px; }
            .markdown h4,
            .markdown h5,
            .markdown h6 { font-size: 14px; }

            .markdown p,
            .markdown ul,
            .markdown ol,
            .markdown blockquote,
            .markdown pre,
            .markdown table {
              margin: 0 0 1em;
            }

            .markdown ul,
            .markdown ol {
              padding-left: 1.4em;
            }

            .markdown li + li {
              margin-top: 0.18em;
            }

            .markdown code {
              font-family: "SF Mono", "Menlo", "Consolas", monospace;
              font-size: 0.92em;
              padding: 0.12em 0.32em;
              border-radius: 4px;
              background: var(--code);
            }

            .markdown pre {
              padding: 12px 14px;
              border-radius: 10px;
              background: var(--code);
              overflow-wrap: anywhere;
              white-space: pre-wrap;
            }

            .markdown pre code {
              padding: 0;
              border-radius: 0;
              background: transparent;
            }

            .markdown blockquote {
              padding: 0.2em 0 0.2em 1em;
              color: #4b5563;
              border-left: 3px solid var(--quote);
            }

            .markdown hr {
              border: 0;
              border-top: 1px solid var(--line);
              margin: 1.4em 0;
            }

            .markdown a {
              color: var(--link);
              text-decoration: none;
            }

            .markdown table {
              width: 100%;
              border-collapse: collapse;
              font-size: 12px;
            }

            .markdown th,
            .markdown td {
              padding: 8px 10px;
              border: 1px solid var(--line);
              vertical-align: top;
            }

            .markdown th {
              background: var(--soft);
              text-align: left;
            }

            .markdown img {
              max-width: 100%;
              height: auto;
            }
          </style>
        </head>
        <body>
          <article>
            <header>
              <h1 class="document-title">\(pageTitle.htmlEscaped())</h1>
              <div class="metadata">
                <div class="metadata-row">\(content.createdAtText.htmlEscaped())</div>
                \(metadataSourceRow(sourceURLText))
              </div>
              \(tagsHTML(content.tags))
            </header>
            \(sectionHTML(title: "Summary", bodyHTML: summaryHTML))
            \(sectionHTML(title: "Full Article", bodyHTML: articleHTML))
          </article>
        </body>
        </html>
        """
    }

    private static func metadataSourceRow(_ sourceURLText: String?) -> String {
        guard let sourceURLText, !sourceURLText.isEmpty else { return "" }
        let escaped = sourceURLText.htmlAttributeEscaped()
        let text = sourceURLText.htmlEscaped()
        return #"<div class="metadata-row"><a href="\#(escaped)">\#(text)</a></div>"#
    }

    private static func tagsHTML(_ tags: [String]) -> String {
        guard !tags.isEmpty else { return "" }
        let tagHTML = tags.map { #"<span class="tag">#\#($0.htmlEscaped())</span>"# }.joined()
        return #"<div class="tags">\#(tagHTML)</div>"#
    }

    private static func sectionHTML(title: String, bodyHTML: String) -> String {
        guard !bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return """
        <section>
          <h2 class="section-title">\(title.htmlEscaped())</h2>
          <div class="markdown">
            \(bodyHTML)
          </div>
        </section>
        """
    }

    private static func makeDebugText(content: LibraryItemPDFExportContent) -> String {
        var lines: [String] = []
        lines.append(content.title)
        lines.append(content.createdAtText)

        if let sourceURLText = content.sourceURLText, !sourceURLText.isEmpty {
            lines.append(sourceURLText)
        }

        if !content.tags.isEmpty {
            lines.append(content.tags.map { "#\($0)" }.joined(separator: " "))
        }

        let summary = content.summaryText.removingThinkTags().trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            lines.append("")
            lines.append("Summary")
            lines.append(summary)
        }

        let article = content.articleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !article.isEmpty {
            lines.append("")
            lines.append("Full Article")
            lines.append(article)
        }

        return lines.joined(separator: "\n")
    }

    private static func preview(_ text: String, limit: Int = 280) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        if normalized.count <= limit {
            return normalized
        }
        return String(normalized.prefix(limit)) + "..."
    }

    private static func log(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        print("[PDFExport] \(message)")
    }
}

private extension LibraryItemPDFExporter {
    struct ExportArtifact: Sendable {
        let pdfURL: URL
        let htmlURL: URL
        let textURL: URL
    }
}

@MainActor
private final class LibraryItemPDFWebRenderer: NSObject, WKNavigationDelegate {
    private static let pageWidth: CGFloat = 794
    private static let pageHeight: CGFloat = 1123

    private let webView: WKWebView
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.suppressesIncrementalRendering = false

        self.webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: Self.pageWidth, height: Self.pageHeight),
            configuration: configuration
        )
        self.webView.isOpaque = false
        self.webView.backgroundColor = .clear
        super.init()
        webView.navigationDelegate = self
    }

    func render(htmlURL: URL, to pdfURL: URL) async throws {
        try Task.checkCancellation()
        try await load(htmlURL: htmlURL)
        try await webView.waitForDocumentReady()
        try Task.checkCancellation()

        let contentRect = try await measuredContentRect()
        let configuration = WKPDFConfiguration()
        configuration.rect = contentRect
        let pdfData = try await webView.createPDFAsync(configuration: configuration)
        try Task.checkCancellation()
        try pdfData.write(to: pdfURL, options: .atomic)
    }

    private func load(htmlURL: URL) async throws {
        if navigationContinuation != nil {
            throw CocoaError(.coderInvalidValue)
        }

        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation
            webView.loadFileURL(
                htmlURL,
                allowingReadAccessTo: htmlURL.deletingLastPathComponent()
            )
        }
    }

    private func measuredContentRect() async throws -> CGRect {
        let script = """
        (() => {
          const root = document.documentElement;
          const body = document.body;
          const widths = [
            root ? root.scrollWidth : 0,
            root ? root.offsetWidth : 0,
            root ? root.clientWidth : 0,
            body ? body.scrollWidth : 0,
            body ? body.offsetWidth : 0,
            body ? body.clientWidth : 0
          ];
          const heights = [
            root ? root.scrollHeight : 0,
            root ? root.offsetHeight : 0,
            root ? root.clientHeight : 0,
            body ? body.scrollHeight : 0,
            body ? body.offsetHeight : 0,
            body ? body.clientHeight : 0
          ];
          return {
            width: Math.ceil(Math.max(...widths)),
            height: Math.ceil(Math.max(...heights))
          };
        })()
        """

        let result = try await webView.evaluateJavaScriptAsync(script)
        guard let dictionary = result as? [String: Any] else {
            throw LibraryItemPDFExporter.ExportError.failedToMeasureContent
        }

        let width = max(1, CGFloat(dictionary["width"] as? Double ?? Double(Self.pageWidth)))
        let height = max(1, CGFloat(dictionary["height"] as? Double ?? Double(Self.pageHeight)))
        return CGRect(x: 0, y: 0, width: width, height: height)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }
}

private enum MarkdownHTMLRenderer {
    static func render(markdown: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let attributedString = try? AttributedString(markdown: trimmed) {
            return HTMLFormatter(attributedString).html()
        }

        return fallbackHTML(for: trimmed)
    }

    private static func fallbackHTML(for text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let separated = normalized.replacingOccurrences(
            of: #"\n[ \t]*\n+"#,
            with: "\u{2029}",
            options: .regularExpression
        )
        let paragraphs = separated
            .components(separatedBy: "\u{2029}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if paragraphs.isEmpty {
            return "<p>\(text.htmlEscaped())</p>"
        }

        return paragraphs.map { paragraph in
            let body = paragraph
                .htmlEscaped()
                .replacingOccurrences(of: "\n", with: "<br />\n")
            return "<p>\(body)</p>"
        }.joined(separator: "\n")
    }
}

private final class HTMLFormatter {
    private let attributedString: AttributedString

    init(_ attributedString: AttributedString) {
        self.attributedString = attributedString
    }

    func html() -> String {
        attributedString.blockNodes.renderHTML()
    }
}

private struct PDFHTMLSegment {
    let components: ArraySlice<PresentationIntent.IntentType>
    let intent: PresentationIntent
    var range: Range<AttributedString.Index>

    init(intent: PresentationIntent, range: Range<AttributedString.Index>) {
        self.init(
            components: intent.components[intent.components.startIndex..<intent.components.endIndex],
            intent: intent,
            range: range
        )
    }

    private init(
        components: ArraySlice<PresentationIntent.IntentType>,
        intent: PresentationIntent,
        range: Range<AttributedString.Index>
    ) {
        self.components = components
        self.intent = intent
        self.range = range
    }

    func dropLastComponent() -> Self {
        .init(components: components.dropLast(), intent: intent, range: range)
    }
}

private struct PDFHTMLSegmentGrouping {
    let component: PresentationIntent.IntentType
    var segments: [PDFHTMLSegment]
}

private struct PDFHTMLListItem {
    let ordinal: Int
    let blocks: [PDFHTMLBlockNode]
}

private struct PDFHTMLTableRow {
    let cells: [[PDFHTMLInlineNode]]
}

private final class PDFHTMLInlineNode {
    enum Kind {
        case text(String)
        case code(String)
        case strong(children: [PDFHTMLInlineNode])
        case emphasized(children: [PDFHTMLInlineNode])
        case strikethrough(children: [PDFHTMLInlineNode])
        case link(url: URL, children: [PDFHTMLInlineNode])
        case lineBreak
    }

    let kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }
}

private final class PDFHTMLBlockNode {
    enum Kind {
        case paragraph(children: [PDFHTMLInlineNode])
        case header(level: Int, children: [PDFHTMLInlineNode])
        case orderedList(children: [PDFHTMLListItem])
        case unorderedList(children: [PDFHTMLListItem])
        case codeBlock(languageHint: String?, code: String)
        case blockQuote(children: [PDFHTMLBlockNode])
        case table(columns: [PresentationIntent.TableColumn], children: [PDFHTMLTableRow])
        case thematicBreak
    }

    let kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }
}

private struct PDFHTMLBlock: Equatable {
    struct Container: Equatable {
        let children: [PDFHTMLBlock]
    }

    struct Leaf: Equatable {
        let attributedString: AttributedSubstring
    }

    enum Kind: Equatable {
        case container(Container)
        case leaf(Leaf)
    }

    let intentType: PresentationIntent.IntentType
    let kind: Kind

    var container: Container? {
        guard case .container(let container) = kind else { return nil }
        return container
    }

    var leaf: Leaf? {
        guard case .leaf(let leaf) = kind else { return nil }
        return leaf
    }
}

private extension AttributedString {
    var blockNodes: [PDFHTMLBlockNode] {
        blocks.compactMap(\.blockNode)
    }

    private var blocks: [PDFHTMLBlock] {
        segments()
            .groupedByLastComponent()
            .map { .init(segmentGrouping: $0, attributedString: self) }
    }

    private func segments() -> [PDFHTMLSegment] {
        var segments: [PDFHTMLSegment] = []

        for run in runs {
            guard let presentationIntent = run.presentationIntent else {
                continue
            }

            if segments.isEmpty || segments.last?.intent != presentationIntent {
                segments.append(.init(intent: presentationIntent, range: run.range))
            } else if let lastIndex = segments.indices.last {
                let currentRange = segments[lastIndex].range
                segments[lastIndex].range = currentRange.lowerBound..<run.range.upperBound
            }
        }

        if segments.isEmpty {
            segments.append(
                .init(
                    intent: .init(.paragraph, identity: 1),
                    range: startIndex..<endIndex
                )
            )
        }

        return segments
    }
}

private extension Sequence where Element == PDFHTMLSegment {
    func groupedByLastComponent() -> [PDFHTMLSegmentGrouping] {
        var groups: [PDFHTMLSegmentGrouping] = []

        for segment in self {
            guard let component = segment.components.last else { continue }

            if groups.isEmpty || groups.last?.component != component {
                groups.append(.init(component: component, segments: [segment.dropLastComponent()]))
            } else if let lastIndex = groups.indices.last {
                groups[lastIndex].segments.append(segment.dropLastComponent())
            }
        }

        return groups
    }
}

private extension PDFHTMLBlock {
    init(segmentGrouping: PDFHTMLSegmentGrouping, attributedString: AttributedString) {
        if let segment = segmentGrouping.segments.first, segment.components.isEmpty {
            self.init(
                intentType: segmentGrouping.component,
                kind: .leaf(.init(attributedString: attributedString[segment.range]))
            )
        } else {
            self.init(
                intentType: segmentGrouping.component,
                kind: .container(
                    .init(
                        children: segmentGrouping.segments.groupedByLastComponent().map {
                            .init(segmentGrouping: $0, attributedString: attributedString)
                        }
                    )
                )
            )
        }
    }

    var blockNode: PDFHTMLBlockNode? {
        switch intentType.kind {
        case .paragraph:
            guard let leaf else { return nil }
            return .init(.paragraph(children: leaf.inlineNodes))
        case .header(let level):
            guard let leaf else { return nil }
            return .init(.header(level: level, children: leaf.inlineNodes))
        case .orderedList:
            guard let container else { return nil }
            return .init(.orderedList(children: container.listItems))
        case .unorderedList:
            guard let container else { return nil }
            return .init(.unorderedList(children: container.listItems))
        case .codeBlock(let languageHint):
            guard let leaf else { return nil }
            return .init(
                .codeBlock(
                    languageHint: languageHint,
                    code: String(leaf.attributedString.characters[...])
                )
            )
        case .blockQuote:
            guard let container else { return nil }
            return .init(.blockQuote(children: container.children.compactMap(\.blockNode)))
        case .table(let columns):
            guard let container else { return nil }
            return .init(.table(columns: columns, children: container.tableRows))
        case .thematicBreak:
            return .init(.thematicBreak)
        default:
            return nil
        }
    }
}

private extension PDFHTMLBlock.Container {
    var listItems: [PDFHTMLListItem] {
        children.compactMap { block in
            guard
                case .listItem(let ordinal) = block.intentType.kind,
                let container = block.container
            else {
                return nil
            }

            return .init(
                ordinal: ordinal,
                blocks: container.children.compactMap(\.blockNode)
            )
        }
    }

    var tableRows: [PDFHTMLTableRow] {
        children.compactMap { block in
            guard block.intentType.kind.isTableRow, let container = block.container else {
                return nil
            }

            return .init(
                cells: container.children.compactMap(\.leaf?.inlineNodes)
            )
        }
    }
}

private extension PDFHTMLBlock.Leaf {
    var inlineNodes: [PDFHTMLInlineNode] {
        attributedString.runs
            .map { attributedString[$0.range] }
            .map(PDFHTMLInlineNode.init)
    }
}

private extension PDFHTMLInlineNode {
    convenience init(_ attributedString: AttributedSubstring) {
        let intent = attributedString.inlinePresentationIntent ?? []
        let node: PDFHTMLInlineNode

        if intent.contains(.lineBreak) {
            node = PDFHTMLInlineNode(.lineBreak)
        } else if intent.contains(.softBreak) {
            node = PDFHTMLInlineNode(.text(" "))
        } else if intent.contains(.code) {
            node = PDFHTMLInlineNode(.code(String(attributedString.characters[...])))
        } else {
            node = PDFHTMLInlineNode(.text(String(attributedString.characters[...])))
        }

        var wrappedNode = node
        if intent.contains(.stronglyEmphasized) {
            wrappedNode = PDFHTMLInlineNode(.strong(children: [wrappedNode]))
        }

        if intent.contains(.emphasized) {
            wrappedNode = PDFHTMLInlineNode(.emphasized(children: [wrappedNode]))
        }

        if intent.contains(.strikethrough) {
            wrappedNode = PDFHTMLInlineNode(.strikethrough(children: [wrappedNode]))
        }

        if let url = attributedString.link {
            wrappedNode = PDFHTMLInlineNode(.link(url: url, children: [wrappedNode]))
        }

        self.init(wrappedNode.kind)
    }

    func renderHTML() -> String {
        switch kind {
        case .text(let text):
            return text.htmlEscaped()
        case .code(let code):
            return "<code>\(code.htmlEscaped())</code>"
        case .strong(let children):
            return "<strong>\(children.renderHTML())</strong>"
        case .emphasized(let children):
            return "<em>\(children.renderHTML())</em>"
        case .strikethrough(let children):
            return "<del>\(children.renderHTML())</del>"
        case .link(let url, let children):
            return #"<a href="\#(url.absoluteString.htmlAttributeEscaped())">\#(children.renderHTML())</a>"#
        case .lineBreak:
            return "<br />"
        }
    }
}

private extension Array where Element == PDFHTMLInlineNode {
    func renderHTML() -> String {
        map { $0.renderHTML() }.joined()
    }
}

private extension PDFHTMLBlockNode {
    func renderHTML() -> String {
        switch kind {
        case .paragraph(let children):
            return "<p>\(children.renderHTML())</p>"
        case .header(let level, let children):
            let clampedLevel = max(1, min(6, level))
            return "<h\(clampedLevel)>\(children.renderHTML())</h\(clampedLevel)>"
        case .orderedList(let children):
            let start = children.map(\.ordinal).min() ?? 1
            let startAttribute = start > 1 ? #" start="\#(start)""# : ""
            return "<ol\(startAttribute)>\n\(children.renderHTML())\n</ol>"
        case .unorderedList(let children):
            return "<ul>\n\(children.renderHTML())\n</ul>"
        case .codeBlock(let languageHint, let code):
            let classAttribute = languageHint
                .flatMap { $0.isEmpty ? nil : $0 }
                .map { #" class="language-\#($0.htmlAttributeEscaped())""# } ?? ""
            return "<pre><code\(classAttribute)>\(code.htmlCodeEscaped())</code></pre>"
        case .blockQuote(let children):
            return "<blockquote>\n\(children.renderHTML())\n</blockquote>"
        case .table(let columns, let children):
            guard let headerHTML = children.first?.renderHeaderHTML(columns: columns) else {
                return "<table></table>"
            }

            let bodyHTML = Array(children.dropFirst()).renderHTML(columns: columns)
            if bodyHTML.isEmpty {
                return "<table>\n<thead>\n\(headerHTML)\n</thead>\n</table>"
            }
            return "<table>\n<thead>\n\(headerHTML)\n</thead>\n<tbody>\n\(bodyHTML)\n</tbody>\n</table>"
        case .thematicBreak:
            return "<hr />"
        }
    }
}

private extension Array where Element == PDFHTMLBlockNode {
    func renderHTML() -> String {
        map { $0.renderHTML() }.joined(separator: "\n")
    }
}

private extension PDFHTMLListItem {
    func renderHTML() -> String {
        let paragraphCount = blocks.filter {
            if case .paragraph = $0.kind { return true }
            return false
        }.count

        if paragraphCount == 1,
           blocks.count == 1,
           case .paragraph(let children) = blocks[0].kind {
            return "<li>\(children.renderHTML())</li>"
        }

        if paragraphCount == 1,
           let firstParagraphIndex = blocks.firstIndex(where: {
               if case .paragraph = $0.kind { return true }
               return false
           }),
           case .paragraph(let children) = blocks[firstParagraphIndex].kind {
            let otherBlocks = blocks.enumerated()
                .filter { $0.offset != firstParagraphIndex }
                .map(\.element)
            return "<li>\(children.renderHTML())\(otherBlocks.renderHTML())</li>"
        }

        return "<li>\(blocks.renderHTML())</li>"
    }
}

private extension Array where Element == PDFHTMLListItem {
    func renderHTML() -> String {
        map { $0.renderHTML() }.joined(separator: "\n")
    }
}

private extension PDFHTMLTableRow {
    func renderHeaderHTML(columns: [PresentationIntent.TableColumn]) -> String {
        renderHTML("th", columns: columns)
    }

    func renderDataHTML(columns: [PresentationIntent.TableColumn]) -> String {
        renderHTML("td", columns: columns)
    }

    private func renderHTML(
        _ element: String,
        columns: [PresentationIntent.TableColumn]
    ) -> String {
        let cells = zip(columns.map(\.alignment), self.cells).map { alignment, inlines in
            #"<\#(element) align="\#(alignment)">\#(inlines.renderHTML())</\#(element)>"#
        }
        return "<tr>\n\(cells.joined(separator: "\n"))\n</tr>"
    }
}

private extension Array where Element == PDFHTMLTableRow {
    func renderHTML(columns: [PresentationIntent.TableColumn]) -> String {
        map { $0.renderDataHTML(columns: columns) }.joined(separator: "\n")
    }
}

private extension PresentationIntent.Kind {
    var isTableRow: Bool {
        switch self {
        case .tableHeaderRow, .tableRow:
            return true
        default:
            return false
        }
    }
}

private extension String {
    func htmlEscaped() -> String {
        var result = ""
        result.reserveCapacity(utf8.count)

        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x26:
                result.append("&amp;")
            case 0x3C:
                result.append("&lt;")
            case 0x3E:
                result.append("&gt;")
            case 0x20 ... 0x7E:
                result.append(Character(scalar))
            default:
                result.append("&#\(scalar.value);")
            }
        }

        return result
    }

    func htmlCodeEscaped() -> String {
        var result = ""
        result.reserveCapacity(utf8.count)

        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x26:
                result.append("&amp;")
            case 0x3C:
                result.append("&lt;")
            case 0x3E:
                result.append("&gt;")
            default:
                result.append(Character(scalar))
            }
        }

        return result
    }

    func htmlAttributeEscaped() -> String {
        var result = ""
        result.reserveCapacity(utf8.count)

        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x26:
                result.append("&amp;")
            case 0x3C:
                result.append("&lt;")
            case 0x3E:
                result.append("&gt;")
            case 0x22:
                result.append("&quot;")
            case 0x20 ... 0x7E:
                result.append(Character(scalar))
            default:
                result.append("&#\(scalar.value);")
            }
        }

        return result
    }
}
