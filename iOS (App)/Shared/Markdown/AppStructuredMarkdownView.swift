import SwiftUI
import Textual

struct AppStructuredMarkdownView: View {
    let markdown: String
    var allowsSelection: Bool = false

    @ViewBuilder
    var body: some View {
        let content = StructuredText(markdown: markdown)
            .textual.structuredTextStyle(.default)
            .textual.inlineStyle(.librarySummary)
            .textual.headingStyle(AppMarkdownHeadingStyle())
            .textual.paragraphStyle(AppMarkdownParagraphStyle())
            .textual.blockQuoteStyle(AppMarkdownBlockQuoteStyle())
            .textual.codeBlockStyle(AppMarkdownCodeBlockStyle())
            .textual.listItemStyle(.default(markerSpacing: .fontScaled(0.45)))
            .textual.listItemSpacing(.fontScaled(top: 0.2))
            .textual.orderedListMarker(.decimal)
            .textual.thematicBreakStyle(AppMarkdownThematicBreakStyle())
            .textual.unorderedListMarker(.hierarchical(.disc, .circle, .square))
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

private struct AppMarkdownHeadingStyle: StructuredText.HeadingStyle {
    private static let topSpacing: [CGFloat] = [0.9, 0.8, 0.7, 0.7, 0.7, 0.7]
    private static let bottomSpacing: [CGFloat] = [0.45, 0.35, 0.3, 0.3, 0.3, 0.3]
    private static let fontWeights: [Font.Weight] = [.black, .black, .black, .semibold, .semibold, .semibold]
    private static let fontSizes: [CGFloat] = [22.95, 20.4, 17.85, 17, 14.11, 11.39]

    func makeBody(configuration: Configuration) -> some View {
        let headingLevel = min(configuration.headingLevel, 6)
        let index = headingLevel - 1

        return configuration.label
            .font(.system(size: Self.fontSizes[index], weight: Self.fontWeights[index]))
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
