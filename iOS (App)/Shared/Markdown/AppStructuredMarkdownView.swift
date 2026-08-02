import SwiftUI
import Textual

struct AppStructuredMarkdownView: View {
    let markdown: String
    var allowsSelection: Bool = false
    @AppStorage(
        AppConfig.macReadingTextScaleKey,
        store: UserDefaults(suiteName: AppConfig.appGroupIdentifier)
    ) private var storedReadingScale = ReadingTextSizeOption.standard.rawValue

    private var readingScale: CGFloat {
        platform == .macCatalyst ? CGFloat(ReadingTextSizeStore.normalizedScale(storedReadingScale)) : 1
    }

    @ViewBuilder
    var body: some View {
        if allowsSelection {
            SystemSelectableMarkdownView(
                markdown: markdown,
                readingScale: readingScale
            )
        } else {
            StructuredText(markdown: markdown)
                .font(.system(size: AppMarkdownMetrics.rootFontSize * readingScale))
                .textual.structuredTextStyle(AppMarkdownStyle(scale: readingScale))
                .textual.listItemSpacing(.fontScaled(top: AppMarkdownMetrics.listItemTopSpacingEm))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Uses the platform text-selection responder so standard edit-menu actions such as
/// Translate and Look Up remain available. Textual's selection overlay intentionally
/// limits its responder actions to Copy and Share.
private struct SystemSelectableMarkdownView: View {
    let readingScale: CGFloat
    private let content: Result<AttributedString, Error>

    init(markdown: String, readingScale: CGFloat) {
        self.readingScale = readingScale
        content = Result {
            try AttributedString(
                markdown: markdown,
                options: .init(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        }
    }

    @ViewBuilder
    var body: some View {
        switch content {
        case let .success(attributedText):
            Text(attributedText)
                .font(.system(size: AppMarkdownMetrics.rootFontSize * readingScale))
                .lineSpacing(AppMarkdownMetrics.paragraphLineSpacing)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .failure(error):
            ContentUnavailableView(
                "Unable to Display Content",
                systemImage: "doc.text.magnifyingglass",
                description: Text(error.localizedDescription)
            )
        }
    }
}

private enum AppMarkdownMetrics {
    // Raw point values resolved from the legacy MarkdownUI theme on iOS (17pt root font).
    static let rootFontSize: CGFloat = 17

    static let headingSizes: [CGFloat] = [23, 20, 18, 17, 14, 11]
    static let headingTopSpacing: [CGFloat] = [21, 16, 13, 26, 26, 26]
    static let headingBottomSpacing: [CGFloat] = [10, 7, 5, 17, 17, 17]
    static let headingLineSpacing: [CGFloat?] = [3, 3, 3, nil, nil, nil]
    static let headingWeights: [Font.Weight] = [.black, .black, .black, .semibold, .semibold, .semibold]

    static let paragraphLineSpacing: CGFloat = 3
    static let paragraphBottomSpacing: CGFloat = 12

    static let blockQuoteLeadingPadding: CGFloat = 14
    static let blockQuoteTrailingPadding: CGFloat = 5
    static let blockQuoteVerticalPadding: CGFloat = 3
    static let blockQuoteRuleWidth: CGFloat = 3
    static let blockQuoteTopSpacing: CGFloat = 3
    static let blockQuoteBottomSpacing: CGFloat = 10

    static let codeFontSize: CGFloat = 15
    static let codeBlockLineSpacing: CGFloat = 3
    static let codeBlockBottomSpacing: CGFloat = 12

    static let listItemTopSpacingEm: CGFloat = 0.2
    static let listMarkerMinWidthEm: CGFloat = 1.5
    static let listMarkerSpacingEm: CGFloat = 0.235
}

private extension InlineStyle {
    static let librarySummary = InlineStyle()
        .code(
            .monospaced,
            .fontScale(0.9),
            .backgroundColor(Color.secondary.opacity(0.15))
        )
        .link(.foregroundColor(.accentColor))
        .strong(
            .fontWeight(.bold),
            .foregroundColor(.primary)
        )
}

private struct AppMarkdownStyle: StructuredText.Style {
    typealias HeadingStyle = AppMarkdownHeadingStyle
    typealias ParagraphStyle = AppMarkdownParagraphStyle
    typealias BlockQuoteStyle = AppMarkdownBlockQuoteStyle
    typealias CodeBlockStyle = AppMarkdownCodeBlockStyle
    typealias ListItemStyle = StructuredText.DefaultListItemStyle
    typealias UnorderedListMarker = StructuredText.HierarchicalSymbolListMarker
    typealias OrderedListMarker = StructuredText.DecimalListMarker
    typealias TableStyle = StructuredText.DefaultTableStyle
    typealias TableCellStyle = StructuredText.DefaultTableCellStyle
    typealias ThematicBreakStyle = AppMarkdownThematicBreakStyle

    let scale: CGFloat

    var inlineStyle: InlineStyle { .librarySummary }
    var headingStyle: AppMarkdownHeadingStyle { .init(scale: scale) }
    var paragraphStyle: AppMarkdownParagraphStyle { .init() }
    var blockQuoteStyle: AppMarkdownBlockQuoteStyle { .init() }
    var codeBlockStyle: AppMarkdownCodeBlockStyle { .init(scale: scale) }
    var listItemStyle: StructuredText.DefaultListItemStyle {
        .default(markerSpacing: .fontScaled(AppMarkdownMetrics.listMarkerSpacingEm))
    }
    var unorderedListMarker: StructuredText.HierarchicalSymbolListMarker {
        .hierarchical(
            .init(
                symbolName: "circle.fill",
                scale: 0.33,
                minWidth: .fontScaled(AppMarkdownMetrics.listMarkerMinWidthEm)
            ),
            .init(
                symbolName: "circle",
                scale: 0.33,
                minWidth: .fontScaled(AppMarkdownMetrics.listMarkerMinWidthEm)
            ),
            .init(
                symbolName: "square.fill",
                scale: 0.33,
                minWidth: .fontScaled(AppMarkdownMetrics.listMarkerMinWidthEm)
            )
        )
    }
    var orderedListMarker: StructuredText.DecimalListMarker {
        .init(minWidth: .fontScaled(AppMarkdownMetrics.listMarkerMinWidthEm))
    }
    var tableStyle: StructuredText.DefaultTableStyle { .default }
    var tableCellStyle: StructuredText.DefaultTableCellStyle { .default }
    var thematicBreakStyle: AppMarkdownThematicBreakStyle { .init() }
}

private struct AppMarkdownHeadingStyle: StructuredText.HeadingStyle {
    let scale: CGFloat

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let headingLevel = min(configuration.headingLevel, 6)
        let index = headingLevel - 1

        switch headingLevel {
        case 1...3:
            configuration.label
                .font(.system(size: AppMarkdownMetrics.headingSizes[index] * scale))
                .fontWeight(AppMarkdownMetrics.headingWeights[index])
                .lineSpacing(AppMarkdownMetrics.headingLineSpacing[index] ?? 0)
                .textual.blockSpacing(
                    .init(
                        top: AppMarkdownMetrics.headingTopSpacing[index],
                        bottom: AppMarkdownMetrics.headingBottomSpacing[index]
                    )
                )
                .foregroundStyle(.primary)
        default:
            configuration.label
                .font(.system(size: AppMarkdownMetrics.headingSizes[index] * scale))
                .fontWeight(AppMarkdownMetrics.headingWeights[index])
                .textual.blockSpacing(
                    .init(
                        top: AppMarkdownMetrics.headingTopSpacing[index],
                        bottom: AppMarkdownMetrics.headingBottomSpacing[index]
                    )
                )
                .foregroundStyle(.primary)
        }
    }
}

private struct AppMarkdownParagraphStyle: StructuredText.ParagraphStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(AppMarkdownMetrics.paragraphLineSpacing)
            .textual.blockSpacing(.init(top: 0, bottom: AppMarkdownMetrics.paragraphBottomSpacing))
            .foregroundStyle(.primary.opacity(0.75))
    }
}

private struct AppMarkdownBlockQuoteStyle: StructuredText.BlockQuoteStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, AppMarkdownMetrics.blockQuoteLeadingPadding)
            .padding(.trailing, AppMarkdownMetrics.blockQuoteTrailingPadding)
            .padding(.vertical, AppMarkdownMetrics.blockQuoteVerticalPadding)
            .textual.blockSpacing(
                .init(
                    top: AppMarkdownMetrics.blockQuoteTopSpacing,
                    bottom: AppMarkdownMetrics.blockQuoteBottomSpacing
                )
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: AppMarkdownMetrics.blockQuoteRuleWidth)
            }
    }
}

private struct AppMarkdownCodeBlockStyle: StructuredText.CodeBlockStyle {
    let scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        Overflow {
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .font(.system(size: AppMarkdownMetrics.codeFontSize * scale))
                .lineSpacing(AppMarkdownMetrics.codeBlockLineSpacing)
                .monospaced()
                .padding(10)
        }
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .textual.blockSpacing(.init(top: 0, bottom: AppMarkdownMetrics.codeBlockBottomSpacing))
    }
}

private struct AppMarkdownThematicBreakStyle: StructuredText.ThematicBreakStyle {
    func makeBody(configuration: Configuration) -> some View {
        Divider()
            .textual.blockSpacing(.fontScaled(top: 0.9, bottom: 0.9))
    }
}
