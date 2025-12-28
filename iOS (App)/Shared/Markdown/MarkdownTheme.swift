import MarkdownUI
import SwiftUI

extension Theme {
    static let librarySummary = Theme.basic
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.9))
            BackgroundColor(Color.secondary.opacity(0.15))
        }
        .link {
            ForegroundColor(.accentColor)
        }
        .strong {
            FontWeight(.bold)
            ForegroundColor(.primary)
        }
        .heading1 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: .em(0.9), bottom: .em(0.45))
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.35))
                    ForegroundColor(.primary)
                }
        }
        .heading2 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: .em(0.8), bottom: .em(0.35))
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.2))
                    ForegroundColor(.primary)
                }
        }
        .heading3 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: .em(0.7), bottom: .em(0.3))
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.05))
                    ForegroundColor(.primary)
                }
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.18))
                .markdownMargin(top: .zero, bottom: .em(0.7))
                .markdownTextStyle {
                    ForegroundColor(.primary.opacity(0.75))
                }
        }
        .blockquote { configuration in
            configuration.label
                .markdownTextStyle {
                    ForegroundColor(.secondary)
                }
                .relativePadding(.leading, length: .em(0.8))
                .relativePadding(.trailing, length: .em(0.3))
                .relativePadding(.vertical, length: .em(0.2))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .relativeFrame(width: .em(0.2))
                }
                .markdownMargin(top: .em(0.2), bottom: .em(0.6))
        }
        .codeBlock { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.18))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.9))
                    }
                    .padding(10)
            }
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .markdownMargin(top: .zero, bottom: .em(0.7))
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.2))
        }
        .thematicBreak {
            Divider().markdownMargin(top: .em(0.9), bottom: .em(0.9))
        }
}
