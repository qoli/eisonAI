import Foundation

extension String {
    func removingBlankLines() -> String {
        let lines = components(separatedBy: .newlines)
        let nonBlankLines = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return nonBlankLines.joined(separator: "\n")
    }

    func removingThinkTags() -> String {
        let pattern = "(?is)<think>.*?</think>"
        var cleaned = replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "<think>", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive)
        return cleaned
    }
}
