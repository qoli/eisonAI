import Foundation

enum PromptTemplates {
    private static var cache: [String: String] = [:]

    static func load(name: String, fallback: String) -> String {
        if let cached = cache[name] { return cached }
        let loaded = BundledTextResource.loadUTF8(name: name, ext: "txt") ?? fallback
        let trimmed = loaded.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? fallback : trimmed
        cache[name] = resolved
        return resolved
    }

    static func render(template: String, values: [String: String]) -> String {
        var output = template
        for (key, value) in values {
            let escapedKey = NSRegularExpression.escapedPattern(for: key)
            let pattern = "\\{\\{\\s*\(escapedKey)\\s*\\}\\}"
            output = output.replacingOccurrences(
                of: pattern,
                with: value,
                options: .regularExpression
            )
        }
        return output
    }
}
