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

    static let defaultSystemPrompt = """
你是一個資料整理員。

Summarize this post in 5-6 sentences.
Emphasize the key insights and main takeaways.

以繁體中文輸出。
"""
}
