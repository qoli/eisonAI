import Foundation
import NaturalLanguage

enum ContentLanguageResolver {
    static func dominantLanguageTag(for text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(20_000)))
        guard let language = recognizer.dominantLanguage else { return nil }
        return language.rawValue.replacingOccurrences(of: "_", with: "-")
    }

    static func representsSameLanguage(_ lhs: String?, _ rhs: String) -> Bool {
        guard let lhs else { return false }
        return baseLanguage(lhs) == baseLanguage(rhs)
    }

    private static func baseLanguage(_ tag: String) -> String {
        tag.replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", maxSplits: 1)
            .first?
            .lowercased() ?? ""
    }
}
