import Foundation

enum NumericFidelityValidator {
    struct UnsupportedNumbersError: LocalizedError, Equatable {
        let values: [String]

        var errorDescription: String? {
            "Generated content introduced numeric facts not found in the source: \(values.joined(separator: ", ")). Regenerate the result."
        }
    }

    static func validate(summary: String, source: String) throws {
        let sourceValues = Set(significantNumbers(in: source))
        let unsupported = Array(Set(significantNumbers(in: summary)).subtracting(sourceValues)).sorted()
        guard unsupported.isEmpty else {
            throw UnsupportedNumbersError(values: unsupported)
        }
    }

    static func significantNumbers(in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}])[$€£¥]?[-+]?\d[\d,]*(?:\.\d+)?(?:%|‰|[kKmMbB])?(?![\p{L}\p{N}])"#
        ) else { return [] }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            let raw = String(text[swiftRange])
            let digits = raw.filter(\.isNumber)
            let hasQualifier = raw.contains(where: { "$€£¥%‰kKmMbB".contains($0) }) || raw.contains(".")
            guard digits.count >= 2 || hasQualifier else { return nil }
            return raw
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "$€£¥"))
                .lowercased()
        }
    }
}
