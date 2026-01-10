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
    static let modelLanguageKey = "eison.modelLanguage"
    static let chunkPromptKey = "eison.chunkPrompt"
    static let titlePromptKey = "eison.titlePrompt"
    static let generationBackendKey = "eison.generation.backend"
    static let foundationModelsAppEnabledKey = "eison.foundationModels.app.enabled"
    static let foundationModelsExtensionEnabledKey = "eison.foundationModels.extension.enabled"
    static let byokProviderKey = "eison.byok.provider"
    static let byokApiURLKey = "eison.byok.apiUrl"
    static let byokApiKeyKey = "eison.byok.apiKey"
    static let byokModelKey = "eison.byok.model"
    static let byokLongDocumentChunkTokenSizeKey = "eison.byok.longDocument.chunkTokenSize"
    static let byokLongDocumentRoutingThresholdKey = "eison.byok.longDocument.routingThreshold"
    static let sharePollingEnabledKey = "eison.share.polling.enabled"
    static let tokenEstimatorEncodingKey = "eison.tokenEstimator.encoding"
    static let longDocumentChunkTokenSizeKey = "eison.longDocument.chunkTokenSize"
    static let longDocumentMaxChunkCountKey = "eison.longDocument.maxChunkCount"
    static let onboardingCompletedKey = "eison.onboarding.completed"
    static let rawLibraryMaxItems = 5000
    static let rawLibraryRootPathComponents = ["RawLibrary"]
    static let rawLibraryItemsPathComponents = ["RawLibrary", "Items"]
    static let rawLibraryFavoriteItemsPathComponents = ["RawLibrary", "FavoriteItems"]
    static let rawLibraryFavoriteIndexFilename = "Favorite.json"
    static let rawLibraryTagsCacheFilename = "cacheTags.json"
    static let rawLibrarySyncManifestFilename = "sync_manifest.json"
    static let sharePayloadsPathComponents = ["SharePayloads"]
    static let lifetimeAccessProductId = "eisonai.unlock"

    static let defaultSystemPrompt: String = {
        if let text = BundledTextResource.loadUTF8(name: "default_system_prompt", ext: "txt") {
            return text
        }

        return """
        將內容整理為簡短簡報，包含重點摘要。

        輸出要求：
        - 合適的格式結構
        """
    }()

    static let defaultChunkPrompt = """
    你是一個文字整理員。

    你目前的任務是，正在協助用戶完整閱讀超長內容。

    - 擷取此文章的關鍵點
    """

    static let defaultTitlePrompt = """
    為內容建立一個簡短的標題；
    與輸入語言保持一致，純文本輸出。
    """
}
