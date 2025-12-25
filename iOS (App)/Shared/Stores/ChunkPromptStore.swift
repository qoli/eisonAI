//
//  ChunkPromptStore.swift
//  iOS (App)
//
//  Created by Codex on 2025/12/25.
//

import Foundation

struct ChunkPromptStore {
    private var defaults: UserDefaults? { UserDefaults(suiteName: AppConfig.appGroupIdentifier) }

    func load() -> String {
        guard let stored = defaults?.string(forKey: AppConfig.chunkPromptKey) else {
            return AppConfig.defaultChunkPrompt
        }
        if stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppConfig.defaultChunkPrompt
        }
        return stored
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
}
