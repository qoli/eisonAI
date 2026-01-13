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
    static let autoStrategyThresholdKey = "eison.generation.auto.strategyThreshold"
    static let autoLocalModelPreferenceKey = "eison.generation.auto.localModelPreference"
    static let localQwenEnabledKey = "eison.labs.localQwen.enabled"
    static let sharePollingEnabledKey = "eison.share.polling.enabled.v2"
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
        let fallback = """
        Summarize the content as a short brief with key points.

        Output requirements:
        - Clear structured headings + bullet points
        - No tables (including Markdown tables)
        - Do not use the `|` character
        """
        return PromptTemplates.load(name: "default_system_prompt", fallback: fallback)
    }()

    static let defaultChunkPrompt: String = {
        let fallback = """
        You are a text organizer.

        Your task is to help the user fully read very long content.

        - Extract the key points from this article
        """
        return PromptTemplates.load(name: "default_chunk_prompt", fallback: fallback)
    }()

    static let defaultTitlePrompt: String = {
        let fallback = """
        Create a short title for the content;
        Match the input language, plain text output.
        """
        return PromptTemplates.load(name: "default_title_prompt", fallback: fallback)
    }()
}
