import Foundation

extension String {
    func removingBlankLines() -> String {
        let lines = components(separatedBy: .newlines)
        let nonBlankLines = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return nonBlankLines.joined(separator: "\n")
    }
}
