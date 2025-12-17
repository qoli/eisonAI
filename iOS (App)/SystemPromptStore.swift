//
//  SystemPromptStore.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import Foundation

struct SystemPromptStore {
    private var defaults: UserDefaults? { UserDefaults(suiteName: AppConfig.appGroupIdentifier) }

    func load() -> String {
        guard let stored = defaults?.string(forKey: AppConfig.systemPromptKey) else {
            return AppConfig.defaultSystemPrompt
        }
        if stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppConfig.defaultSystemPrompt
        }
        return stored
    }

    func save(_ value: String?) {
        guard let defaults else { return }
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: AppConfig.systemPromptKey)
        } else {
            defaults.set(trimmed, forKey: AppConfig.systemPromptKey)
        }
    }
}
