import SwiftUI
import Textual

struct AppStructuredMarkdownView: View {
    let markdown: String
    var allowsSelection: Bool = false

    @ViewBuilder
    var body: some View {
        let content = StructuredText(markdown: markdown)
            .font(.system(size: 14))
            .textual.structuredTextStyle(AppMarkdownStyle())
            .frame(maxWidth: .infinity, alignment: .leading)

        if allowsSelection {
            content.textual.textSelection(.enabled)
        } else {
            content
        }
    }
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

    var inlineStyle: InlineStyle { .librarySummary }
    var headingStyle: AppMarkdownHeadingStyle { .init() }
    var paragraphStyle: AppMarkdownParagraphStyle { .init() }
    var blockQuoteStyle: AppMarkdownBlockQuoteStyle { .init() }
    var codeBlockStyle: AppMarkdownCodeBlockStyle { .init() }
    var listItemStyle: StructuredText.DefaultListItemStyle {
        .default(markerSpacing: .fontScaled(0.45))
    }
    var unorderedListMarker: StructuredText.HierarchicalSymbolListMarker {
        .hierarchical(.disc, .circle, .square)
    }
    var orderedListMarker: StructuredText.DecimalListMarker { .decimal }
    var tableStyle: StructuredText.DefaultTableStyle { .default }
    var tableCellStyle: StructuredText.DefaultTableCellStyle { .default }
    var thematicBreakStyle: AppMarkdownThematicBreakStyle { .init() }
}

private struct AppMarkdownHeadingStyle: StructuredText.HeadingStyle {
    private static let fontScales: [CGFloat] = [1.14, 0.93, 0.86, 0.86, 0.78, 0.67]
    private static let topSpacing: [CGFloat] = [0.9, 0.8, 0.7, 0.7, 0.7, 0.7]
    private static let bottomSpacing: [CGFloat] = [0.45, 0.35, 0.3, 0.3, 0.3, 0.3]
    private static let fontWeights: [Font.Weight] = [.black, .black, .black, .semibold, .semibold, .semibold]
    private static let baseFontSize: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        let headingLevel = min(configuration.headingLevel, 6)
        let index = headingLevel - 1

        return configuration.label
            .font(.system(size: Self.baseFontSize))
            .textual.fontScale(Self.fontScales[index])
            .fontWeight(Self.fontWeights[index])
            .textual.lineSpacing(.fontScaled(0.15))
            .textual.blockSpacing(
                .fontScaled(top: Self.topSpacing[index], bottom: Self.bottomSpacing[index])
            )
            .foregroundStyle(.primary)
    }
}

private struct AppMarkdownParagraphStyle: StructuredText.ParagraphStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .textual.lineSpacing(.fontScaled(0.2))
            .textual.blockSpacing(.fontScaled(top: 0, bottom: 0.7))
            .foregroundStyle(.primary.opacity(0.75))
    }
}

private struct AppMarkdownBlockQuoteStyle: StructuredText.BlockQuoteStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textual.padding(.leading, .fontScaled(0.8))
            .textual.padding(.trailing, .fontScaled(0.3))
            .textual.padding(.vertical, .fontScaled(0.2))
            .textual.blockSpacing(.fontScaled(top: 0.2, bottom: 0.6))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .textual.frame(width: .fontScaled(0.2))
            }
    }
}

private struct AppMarkdownCodeBlockStyle: StructuredText.CodeBlockStyle {
    func makeBody(configuration: Configuration) -> some View {
        Overflow {
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .textual.lineSpacing(.fontScaled(0.18))
                .textual.fontScale(0.9)
                .monospaced()
                .padding(10)
        }
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .textual.blockSpacing(.fontScaled(top: 0, bottom: 0.7))
    }
}

private struct AppMarkdownThematicBreakStyle: StructuredText.ThematicBreakStyle {
    func makeBody(configuration: Configuration) -> some View {
        Divider()
            .textual.blockSpacing(.fontScaled(top: 0.9, bottom: 0.9))
    }
}
