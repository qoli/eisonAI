//
//  TitlePromptStore.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2025/12/21.
//

import Foundation

struct TitlePromptStore {
    private var defaults: UserDefaults? { UserDefaults(suiteName: AppConfig.appGroupIdentifier) }

    func load() -> String {
        guard let stored = defaults?.string(forKey: AppConfig.titlePromptKey) else {
            return AppConfig.defaultTitlePrompt
        }
        if stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppConfig.defaultTitlePrompt
        }
        return stored
    }

    func save(_ value: String?) {
        guard let defaults else { return }
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: AppConfig.titlePromptKey)
        } else {
            defaults.set(trimmed, forKey: AppConfig.titlePromptKey)
        }
    }
}
