//
//  ModelLanguageStore.swift
//  iOS (App)
//
//  Created by Codex on 2026/1/2.
//

import Foundation

struct ModelLanguage: Identifiable, Hashable {
    let tag: String
    let displayName: String

    var id: String { tag }

    static let supported: [ModelLanguage] = [
        ModelLanguage(tag: "en-US", displayName: "English (US)"),
        ModelLanguage(tag: "en-GB", displayName: "English (UK)"),
        ModelLanguage(tag: "fr-FR", displayName: "French (France)"),
        ModelLanguage(tag: "de", displayName: "German"),
        ModelLanguage(tag: "it", displayName: "Italian"),
        ModelLanguage(tag: "pt-BR", displayName: "Portuguese (Brazil)"),
        ModelLanguage(tag: "pt-PT", displayName: "Portuguese (Portugal)"),
        ModelLanguage(tag: "es-ES", displayName: "Spanish (Spain)"),
        ModelLanguage(tag: "zh-Hans", displayName: "Chinese (Simplified)"),
        ModelLanguage(tag: "zh-Hant", displayName: "Chinese (Traditional)"),
        ModelLanguage(tag: "ja", displayName: "Japanese"),
        ModelLanguage(tag: "ko", displayName: "Korean"),
        ModelLanguage(tag: "da", displayName: "Danish"),
        ModelLanguage(tag: "nl", displayName: "Dutch"),
        ModelLanguage(tag: "no", displayName: "Norwegian"),
        ModelLanguage(tag: "sv", displayName: "Swedish"),
        ModelLanguage(tag: "tr", displayName: "Turkish"),
        ModelLanguage(tag: "vi", displayName: "Vietnamese"),
    ]

    static func isSupportedTag(_ tag: String) -> Bool {
        let normalized = normalizeTag(tag)
        return supported.contains(where: { $0.tag.caseInsensitiveCompare(normalized) == .orderedSame })
    }

    static func displayName(forTag tag: String) -> String {
        let normalized = normalizeTag(tag)
        return supported.first(where: { $0.tag.caseInsensitiveCompare(normalized) == .orderedSame })?.displayName ?? normalized
    }

    static func normalizeTag(_ tag: String) -> String {
        tag.replacingOccurrences(of: "_", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func recommendedTag(for locale: Locale) -> String {
        let identifier = normalizeTag(locale.identifier)
        if isSupportedTag(identifier) {
            return canonicalTag(for: identifier)
        }

        let components = Locale.components(fromIdentifier: locale.identifier)
        let language = components[NSLocale.Key.languageCode.rawValue] ?? ""
        let script = components[NSLocale.Key.scriptCode.rawValue]
        let region = components[NSLocale.Key.countryCode.rawValue]

        if !language.isEmpty {
            if language == "zh" {
                if let script, isSupportedTag("zh-\(script)") {
                    return canonicalTag(for: "zh-\(script)")
                }
                if let region {
                    let upper = region.uppercased()
                    if ["TW", "HK", "MO"].contains(upper) { return "zh-Hant" }
                    if ["CN", "SG"].contains(upper) { return "zh-Hans" }
                }
                return "zh-Hans"
            }

            if language == "en" {
                if let region, region.uppercased() == "GB" { return "en-GB" }
                return "en-US"
            }

            if language == "pt" {
                if let region, region.uppercased() == "PT" { return "pt-PT" }
                if let region, region.uppercased() == "BR" { return "pt-BR" }
                return "pt-BR"
            }

            if let region, isSupportedTag("\(language)-\(region)") {
                return canonicalTag(for: "\(language)-\(region)")
            }

            if let script, isSupportedTag("\(language)-\(script)") {
                return canonicalTag(for: "\(language)-\(script)")
            }

            if isSupportedTag(language) {
                return canonicalTag(for: language)
            }
        }

        return "en-US"
    }

    private static func canonicalTag(for tag: String) -> String {
        let normalized = normalizeTag(tag)
        return supported.first(where: { $0.tag.caseInsensitiveCompare(normalized) == .orderedSame })?.tag ?? normalized
    }
}

struct ModelLanguageStore {
    private var defaults: UserDefaults? { UserDefaults(suiteName: AppConfig.appGroupIdentifier) }

    func loadOrRecommended(locale: Locale = .current) -> String {
        guard let defaults else {
            return ModelLanguage.recommendedTag(for: locale)
        }

        guard let stored = defaults.string(forKey: AppConfig.modelLanguageKey) else {
            let recommended = ModelLanguage.recommendedTag(for: locale)
            saveInternal(recommended, triggerTranslator: false)
            return recommended
        }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || !ModelLanguage.isSupportedTag(trimmed) {
            let recommended = ModelLanguage.recommendedTag(for: locale)
            saveInternal(recommended, triggerTranslator: false)
            return recommended
        }
        return ModelLanguage.normalizeTag(trimmed)
    }

    func save(_ tag: String) {
        saveInternal(tag, triggerTranslator: true)
    }

    func callTranslator() {
        #if !APP_EXTENSION
            Task { @MainActor in
                print("[ModelLanguageStore] callTranslator started")
                await translatePrompts()
                print("[ModelLanguageStore] callTranslator finished")
            }
        #endif
    }

    func ensureTranslatedPromptsOnLaunch() {
        guard let defaults else { return }
        let summary = defaults.string(forKey: AppConfig.translatedSummaryPromptKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chunk = defaults.string(forKey: AppConfig.translatedChunkPromptKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if summary.isEmpty || chunk.isEmpty {
            callTranslator()
        }
    }

    private func saveInternal(_ tag: String, triggerTranslator: Bool) {
        guard let defaults else { return }
        let normalized = ModelLanguage.normalizeTag(tag)
        if normalized.isEmpty || !ModelLanguage.isSupportedTag(normalized) { return }
        defaults.set(
            ModelLanguage.supported.first(where: { $0.tag.caseInsensitiveCompare(normalized) == .orderedSame })?.tag ?? normalized,
            forKey: AppConfig.modelLanguageKey
        )
        if triggerTranslator {
            callTranslator()
        }
    }

    @MainActor
    private func translatePrompts() async {
        #if !APP_EXTENSION
            guard let defaults else { return }
            let summarySource = SystemPromptStore().load(translated: false)
            let chunkSource = ChunkPromptStore().loadWithLanguage(translated: false)
            let targetTag = loadOrRecommended()
            print("[ModelLanguageStore] translatePrompts target=\(targetTag) summaryCount=\(summarySource.count) chunkCount=\(chunkSource.count)")
            guard let result = await PromptTranslationCoordinator.shared.requestTranslation(
                summary: summarySource,
                chunk: chunkSource,
                targetLanguageTag: targetTag
            ) else {
                print("[ModelLanguageStore] translatePrompts failed")
                return
            }
            defaults.set(result.summary, forKey: AppConfig.translatedSummaryPromptKey)
            defaults.set(result.chunk, forKey: AppConfig.translatedChunkPromptKey)
            print("[ModelLanguageStore] translatePrompts saved summaryCount=\(result.summary.count) chunkCount=\(result.chunk.count)")
        #endif
    }
}
