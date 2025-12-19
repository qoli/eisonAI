import Foundation

struct MockupLibraryItem: Identifiable, Codable, Hashable {
    var id: String
    var createdAt: String
    var modelId: String
    var title: String
    var url: String
    var userPrompt: String
    var systemPrompt: String?
    var summaryText: String
    var articleText: String
    var v: Int

    var createdAtDate: Date? {
        Self.parseISO8601(createdAt)
    }

    var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let candidate = firstMeaningfulLine(in: userPrompt)
            ?? firstMeaningfulLine(in: summaryText)
            ?? firstMeaningfulLine(in: articleText)

        return candidate?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80).description ?? "Untitled"
    }

    var subtitle: String {
        let preview = firstMeaningfulLine(in: summaryText) ?? firstMeaningfulLine(in: articleText) ?? ""
        return preview.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstMeaningfulLine(in text: String) -> String? {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        for line in lines {
            if line.isEmpty { continue }
            if line == "(no title)" { continue }
            if line == "【正文】" { continue }
            if line == "<think>" { continue }
            return line
        }
        return nil
    }

    private static func parseISO8601(_ s: String) -> Date? {
        let formatterWithFractional: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()

        let formatter: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()

        return formatterWithFractional.date(from: s) ?? formatter.date(from: s)
    }
}

struct MockupFavoriteIndex: Codable, Hashable {
    var filenames: [String]
    var updatedAt: String
    var v: Int
}

struct LoadedMockupLibraryItem: Identifiable, Hashable {
    var item: MockupLibraryItem
    var filename: String
    var isFavorite: Bool

    var id: String { item.id }
}

