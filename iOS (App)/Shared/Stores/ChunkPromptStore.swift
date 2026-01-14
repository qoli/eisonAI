//
//  ChunkPromptStore.swift
//  iOS (App)
//
//  Created by Codex on 2025/12/25.
//

import Foundation

struct ChunkPromptStore {
    private var defaults: UserDefaults? { UserDefaults(suiteName: AppConfig.appGroupIdentifier) }
    private let modelLanguageStore = ModelLanguageStore()

    func load() -> String {
        guard let stored = defaults?.string(forKey: AppConfig.chunkPromptKey) else {
            return AppConfig.defaultChunkPrompt
        }
        if stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppConfig.defaultChunkPrompt
        }
        return stored
    }

    func loadWithLanguage() -> String {
        let base = load()
        let languageTag = modelLanguageStore.loadOrRecommended()
        let languageName = ModelLanguage.displayName(forTag: languageTag)
        let languageLineTemplate = PromptTemplates.load(
            name: "summary_language_line",
            fallback: "- Please respond in {{language}}."
        )
        let languageLine = PromptTemplates.render(
            template: languageLineTemplate,
            values: ["language": languageName]
        )
        return compose(base: base, languageLine: languageLine)
    }

    func save(_ value: String?) {
        guard let defaults else { return }
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: AppConfig.chunkPromptKey)
        } else {
            defaults.set(trimmed, forKey: AppConfig.chunkPromptKey)
        }
    }

    private func compose(base: String, languageLine: String) -> String {
        let normalizedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLanguageLine = languageLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedLanguageLine.isEmpty { return normalizedBase }
        if normalizedBase.contains(normalizedLanguageLine) { return normalizedBase }
        return "\(normalizedBase)\n\n\(normalizedLanguageLine)"
    }
}
