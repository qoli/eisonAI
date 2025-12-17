//
//  AppConfig.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import Foundation

enum AppConfig {
    static let appGroupIdentifier = "group.com.qoli.eisonAI"
    static let systemPromptKey = "eison.systemPrompt"
    static let rawLibraryItemsPathComponents = ["RawLibrary", "Items"]

    static let defaultSystemPrompt: String = {
        if
            let url = Bundle.main.url(forResource: "default_system_prompt", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        return "你是一個資料整理員。\n\n以繁體中文輸出。"
    }()
}
