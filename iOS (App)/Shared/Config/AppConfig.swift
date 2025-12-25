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
    static let chunkPromptKey = "eison.chunkPrompt"
    static let titlePromptKey = "eison.titlePrompt"
    static let foundationModelsAppEnabledKey = "eison.foundationModels.app.enabled"
    static let foundationModelsExtensionEnabledKey = "eison.foundationModels.extension.enabled"
    static let sharePollingEnabledKey = "eison.share.polling.enabled"
    static let rawLibraryMaxItems = 5000
    static let rawLibraryRootPathComponents = ["RawLibrary"]
    static let rawLibraryItemsPathComponents = ["RawLibrary", "Items"]
    static let rawLibraryFavoriteItemsPathComponents = ["RawLibrary", "FavoriteItems"]
    static let rawLibraryFavoriteIndexFilename = "Favorite.json"
    static let rawLibraryTagsCacheFilename = "cacheTags.json"
    static let rawLibrarySyncManifestFilename = "sync_manifest.json"
    static let sharePayloadsPathComponents = ["SharePayloads"]

    static let defaultSystemPrompt: String = {
        if
            let url = Bundle.main.url(forResource: "default_system_prompt", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        return """
        將內容整理為簡短簡報，包含重點摘要。

        輸出要求：
        - 合適的格式結構
        - 使用繁體中文。
        """
    }()

    static let defaultChunkPrompt = """
    你是一個文字整理員。

    你目前的任務是，正在協助用戶完整閱讀超長內容。

    - 擷取此文章的關鍵點
    """

    static let defaultTitlePrompt = """
    請為內容構建一個合適的標題；
    使用繁體中文，保持純文本輸出。
    """
}
