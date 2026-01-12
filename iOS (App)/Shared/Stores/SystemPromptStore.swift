//
//  SystemPromptStore.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import Foundation

struct SystemPromptStore {
    private var defaults: UserDefaults? { UserDefaults(suiteName: AppConfig.appGroupIdentifier) }
    private let modelLanguageStore = ModelLanguageStore()

    func load() -> String {
        let base = loadBase()
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

    func loadBase() -> String {
        guard let stored = defaults?.string(forKey: AppConfig.systemPromptKey) else {
            return normalizeBase(AppConfig.defaultSystemPrompt)
        }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return normalizeBase(AppConfig.defaultSystemPrompt)
        }
        return normalizeBase(trimmed)
    }

    func saveBase(_ value: String?) {
        guard let defaults else { return }
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: AppConfig.systemPromptKey)
        } else {
            defaults.set(normalizeBase(trimmed), forKey: AppConfig.systemPromptKey)
        }
    }

    private func compose(base: String, languageLine: String) -> String {
        let normalizedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLanguageLine = languageLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedLanguageLine.isEmpty { return normalizedBase }
        if normalizedBase.contains(normalizedLanguageLine) { return normalizedBase }
        return "\(normalizedBase)\n\n\(normalizedLanguageLine)"
    }

    private func normalizeBase(_ base: String) -> String {
        let lines = base
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }

        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return true }
            if trimmed == "- 使用繁體中文。" { return false }
            if trimmed == "- 使用繁體中文" { return false }
            return true
        }

        return filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
