//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Native messaging is used only for lightweight configuration (e.g. system prompt).
//  LLM inference runs in the extension popup via WebLLM (bundled assets).
//

import CryptoKit
import Foundation
import os.log
import SafariServices

#if canImport(AnyLanguageModel)
    import AnyLanguageModel
#endif

enum GenerationBackendSelection: String {
    case auto
    case local
    case byok
}

enum ExecutionBackend: String {
    case mlc
    case appleIntelligence = "apple"
    case byok
}

struct BYOKSettingsPayload {
    let provider: String
    let apiURL: String
    let apiKey: String
    let model: String
}

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let logSubsystem = "com.qoli.eisonAI"
    private static let nativeLog = OSLog(subsystem: logSubsystem, category: "Native")
    private static let rawLibraryLog = OSLog(subsystem: logSubsystem, category: "RawLibrary")

    private let appGroupIdentifier = AppConfig.appGroupIdentifier
    private let systemPromptKey = AppConfig.systemPromptKey
    private let modelLanguageKey = AppConfig.modelLanguageKey
    private let chunkPromptKey = AppConfig.chunkPromptKey
    private let tokenEstimatorEncodingKey = AppConfig.tokenEstimatorEncodingKey
    private let longDocumentChunkTokenSizeKey = AppConfig.longDocumentChunkTokenSizeKey
    private let longDocumentMaxChunkCountKey = AppConfig.longDocumentMaxChunkCountKey
    private let rawLibraryMaxItems = AppConfig.rawLibraryMaxItems

    private static let supportedModelLanguages: [(tag: String, displayName: String)] = [
        (tag: "en-US", displayName: "English (US)"),
        (tag: "en-GB", displayName: "English (UK)"),
        (tag: "fr-FR", displayName: "French (France)"),
        (tag: "de", displayName: "German"),
        (tag: "it", displayName: "Italian"),
        (tag: "pt-BR", displayName: "Portuguese (Brazil)"),
        (tag: "pt-PT", displayName: "Portuguese (Portugal)"),
        (tag: "es-ES", displayName: "Spanish (Spain)"),
        (tag: "zh-Hans", displayName: "Chinese (Simplified)"),
        (tag: "zh-Hant", displayName: "Chinese (Traditional)"),
        (tag: "ja", displayName: "Japanese"),
        (tag: "ko", displayName: "Korean"),
        (tag: "da", displayName: "Danish"),
        (tag: "nl", displayName: "Dutch"),
        (tag: "no", displayName: "Norwegian"),
        (tag: "sv", displayName: "Swedish"),
        (tag: "tr", displayName: "Turkish"),
        (tag: "vi", displayName: "Vietnamese"),
    ]
    private struct RawHistoryItem: Codable {
        var v: Int = 1
        var id: String
        var createdAt: Date
        var url: String
        var title: String
        var articleText: String
        var summaryText: String
        var tags: [String] = []
        var systemPrompt: String
        var userPrompt: String
        var modelId: String
        var readingAnchors: [ReadingAnchorChunk]?
        var tokenEstimate: Int?
        var tokenEstimator: String?
        var chunkTokenSize: Int?
        var routingThreshold: Int?
        var isLongDocument: Bool?
    }

    private struct ReadingAnchorChunk: Codable {
        var index: Int
        var tokenCount: Int
        var text: String
        var startUTF16: Int?
        var endUTF16: Int?
    }

    private static let filenameTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
        return formatter
    }()

    private func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private func rawLibraryItemsDirectoryURL() throws -> URL {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            )
        else {
            os_log(
                "[Eison-Native] App Group container unavailable for id=%{public}@",
                log: Self.rawLibraryLog,
                type: .error,
                appGroupIdentifier
            )
            throw NSError(
                domain: "EisonAI.RawLibrary",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "App Group container is unavailable."]
            )
        }

        var directoryURL = containerURL
        for component in AppConfig.rawLibraryItemsPathComponents {
            directoryURL = directoryURL.appendingPathComponent(component, isDirectory: true)
        }
        return directoryURL
    }

    private func sha256Hex(_ value: String) -> String {
        let data = Data(value.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func parseTimestampFromRawLibraryFilename(_ filename: String) -> Date? {
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        guard let range = base.range(of: "__") else { return nil }
        let timestamp = String(base[range.upperBound...])
        return Self.filenameTimestampFormatter.date(from: timestamp)
    }

    @discardableResult
    private func enforceRawLibraryLimit(in directoryURL: URL) throws -> Int {
        let items = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let jsonFiles = items
            .filter { $0.pathExtension.lowercased() == "json" }
        guard jsonFiles.count > rawLibraryMaxItems else { return 0 }

        let sorted = jsonFiles.sorted { lhs, rhs in
            let leftDate = parseTimestampFromRawLibraryFilename(lhs.lastPathComponent) ?? .distantPast
            let rightDate = parseTimestampFromRawLibraryFilename(rhs.lastPathComponent) ?? .distantPast
            if leftDate != rightDate { return leftDate < rightDate }
            return lhs.lastPathComponent < rhs.lastPathComponent
        }

        let deleteCount = sorted.count - rawLibraryMaxItems
        for fileURL in sorted.prefix(deleteCount) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return deleteCount
    }

    private func saveRawHistoryItem(
        url: String,
        title: String,
        articleText: String,
        summaryText: String,
        systemPrompt: String,
        userPrompt: String,
        modelId: String,
        readingAnchors: [ReadingAnchorChunk]? = nil,
        tokenEstimate: Int? = nil,
        tokenEstimator: String? = nil,
        chunkTokenSize: Int? = nil,
        routingThreshold: Int? = nil,
        isLongDocument: Bool? = nil
    ) throws -> (id: String, filename: String) {
        let directoryURL = try rawLibraryItemsDirectoryURL()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let createdAt = Date()
        let id = UUID().uuidString
        let urlHash = sha256Hex(url)
        let timestamp = Self.filenameTimestampFormatter.string(from: createdAt)
        let filename = "\(urlHash)__\(timestamp).json"

        // Keep only the latest record per URL by removing older files with the same hash prefix.
        let existing = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let prefix = "\(urlHash)__"
        var removedForURL = 0
        for fileURL in existing where fileURL.pathExtension.lowercased() == "json" {
            if fileURL.lastPathComponent.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: fileURL)
                removedForURL += 1
            }
        }
        if removedForURL > 0 {
            os_log(
                "[Eison-Native] RawLibrary removed %d old item(s) for urlHash=%{public}@",
                log: Self.rawLibraryLog,
                type: .info,
                removedForURL,
                urlHash
            )
        }

        let item = RawHistoryItem(
            id: id,
            createdAt: createdAt,
            url: url,
            title: title,
            articleText: articleText,
            summaryText: summaryText,
            tags: [],
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            modelId: modelId,
            readingAnchors: readingAnchors,
            tokenEstimate: tokenEstimate,
            tokenEstimator: tokenEstimator,
            chunkTokenSize: chunkTokenSize,
            routingThreshold: routingThreshold,
            isLongDocument: isLongDocument
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)

        let fileURL = directoryURL.appendingPathComponent(filename)
        try data.write(to: fileURL, options: [.atomic])

        let trimmed = try enforceRawLibraryLimit(in: directoryURL)
        if trimmed > 0 {
            os_log(
                "[Eison-Native] RawLibrary trimmed %d old item(s) to max=%d",
                log: Self.rawLibraryLog,
                type: .info,
                trimmed,
                rawLibraryMaxItems
            )
        }
        return (id, filename)
    }

    private func loadSystemPrompt() -> String {
        SystemPromptStore().load()
    }

    private func loadChunkPrompt() -> String {
        ChunkPromptStore().loadWithLanguage()
    }

    private func loadTokenEstimatorEncoding() -> String {
        guard let stored = sharedDefaults()?.string(forKey: tokenEstimatorEncodingKey) else {
            return "cl100k_base"
        }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "cl100k_base" : trimmed
    }

    private func loadLongDocumentChunkTokenSize() -> Int {
        let fallback = LongDocumentDefaults.fallbackChunkSize
        let allowed = LongDocumentDefaults.allowedChunkSizeSet
        guard let stored = sharedDefaults()?.object(forKey: longDocumentChunkTokenSizeKey) as? Int else {
            return fallback
        }
        if allowed.contains(stored) { return stored }
        sharedDefaults()?.set(fallback, forKey: longDocumentChunkTokenSizeKey)
        return fallback
    }

    private func loadAutoStrategyThreshold() -> Int {
        LongDocumentDefaults.autoStrategyThresholdValue
    }

    private func loadAutoLocalPreference() -> String {
        guard let stored = sharedDefaults()?.string(forKey: AppConfig.autoLocalModelPreferenceKey) else {
            return "appleIntelligence"
        }
        return stored == "qwen3" ? "qwen3" : "appleIntelligence"
    }

    private func loadLocalQwenEnabled() -> Bool {
        sharedDefaults()?.bool(forKey: AppConfig.localQwenEnabledKey) ?? false
    }

    private func loadLongDocumentMaxChunks() -> Int {
        let fallback = LongDocumentDefaults.fallbackMaxChunkCount
        let allowed = LongDocumentDefaults.allowedMaxChunkCountSet
        guard let stored = sharedDefaults()?.object(forKey: longDocumentMaxChunkCountKey) as? Int else {
            return fallback
        }
        if allowed.contains(stored) { return stored }
        sharedDefaults()?.set(fallback, forKey: longDocumentMaxChunkCountKey)
        return fallback
    }

    private func readInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let doubleValue = value as? Double { return Int(doubleValue) }
        if let stringValue = value as? String, let intValue = Int(stringValue) { return intValue }
        return nil
    }

    private func saveSystemPrompt(_ value: String?) {
        guard let defaults = sharedDefaults() else { return }
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: systemPromptKey)
        } else {
            defaults.set(normalizeBaseSystemPrompt(trimmed), forKey: systemPromptKey)
        }
    }

    private func composeSystemPrompt(base: String, languageLine: String) -> String {
        let normalizedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLanguageLine = languageLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedLanguageLine.isEmpty { return normalizedBase }
        if normalizedBase.contains(normalizedLanguageLine) { return normalizedBase }
        return "\(normalizedBase)\n\n\(normalizedLanguageLine)"
    }

    private func normalizeBaseSystemPrompt(_ base: String) -> String {
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

    private func normalizeLanguageTag(_ tag: String) -> String {
        tag.replacingOccurrences(of: "_", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isSupportedModelLanguageTag(_ tag: String) -> Bool {
        let normalized = normalizeLanguageTag(tag)
        return Self.supportedModelLanguages.contains(where: { $0.tag.caseInsensitiveCompare(normalized) == .orderedSame })
    }

    private func canonicalModelLanguageTag(_ tag: String) -> String {
        let normalized = normalizeLanguageTag(tag)
        return Self.supportedModelLanguages.first(where: { $0.tag.caseInsensitiveCompare(normalized) == .orderedSame })?.tag ?? normalized
    }

    private func modelLanguageDisplayName(forTag tag: String) -> String {
        let normalized = normalizeLanguageTag(tag)
        return Self.supportedModelLanguages.first(where: { $0.tag.caseInsensitiveCompare(normalized) == .orderedSame })?.displayName ?? normalized
    }

    private func recommendedModelLanguageTag(for locale: Locale) -> String {
        let identifier = normalizeLanguageTag(locale.identifier)
        if isSupportedModelLanguageTag(identifier) {
            return canonicalModelLanguageTag(identifier)
        }

        let components = Locale.components(fromIdentifier: locale.identifier)
        let language = components[NSLocale.Key.languageCode.rawValue] ?? ""
        let script = components[NSLocale.Key.scriptCode.rawValue]
        let region = components[NSLocale.Key.countryCode.rawValue]

        if !language.isEmpty {
            if language == "zh" {
                if let script, isSupportedModelLanguageTag("zh-\(script)") {
                    return canonicalModelLanguageTag("zh-\(script)")
                }
                if let region {
                    let upper = region.uppercased()
                    if ["TW", "HK", "MO"].contains(upper) { return "zh-Hant" }
                    if ["CN", "SG"].contains(upper) { return "zh-Hans" }
                }
                return "zh-Hans"
            }

            if language == "en" {
                if let region, region.uppercased() == "GB" { return "en-GB" }
                return "en-US"
            }

            if language == "pt" {
                if let region, region.uppercased() == "PT" { return "pt-PT" }
                if let region, region.uppercased() == "BR" { return "pt-BR" }
                return "pt-BR"
            }

            if let region, isSupportedModelLanguageTag("\(language)-\(region)") {
                return canonicalModelLanguageTag("\(language)-\(region)")
            }

            if let script, isSupportedModelLanguageTag("\(language)-\(script)") {
                return canonicalModelLanguageTag("\(language)-\(script)")
            }

            if isSupportedModelLanguageTag(language) {
                return canonicalModelLanguageTag(language)
            }
        }

        return "en-US"
    }

    private func loadModelLanguageTag() -> String {
        guard let defaults = sharedDefaults() else {
            return recommendedModelLanguageTag(for: .current)
        }

        guard let stored = defaults.string(forKey: modelLanguageKey) else {
            let recommended = recommendedModelLanguageTag(for: .current)
            defaults.set(recommended, forKey: modelLanguageKey)
            return recommended
        }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || !isSupportedModelLanguageTag(trimmed) {
            let recommended = recommendedModelLanguageTag(for: .current)
            defaults.set(recommended, forKey: modelLanguageKey)
            return recommended
        }
        let canonical = canonicalModelLanguageTag(trimmed)
        if canonical != trimmed {
            defaults.set(canonical, forKey: modelLanguageKey)
        }
        return canonical
    }

    private func loadGenerationBackendSelection() -> GenerationBackendSelection {
        guard let raw = sharedDefaults()?.string(forKey: AppConfig.generationBackendKey) else {
            return .local
        }
        if let selection = GenerationBackendSelection(rawValue: raw) {
            return selection
        }
        if raw == ExecutionBackend.mlc.rawValue || raw == ExecutionBackend.appleIntelligence.rawValue {
            return .local
        }
        if raw == ExecutionBackend.byok.rawValue {
            return .byok
        }
        return .local
    }

    private func isFoundationModelsExtensionEnabled() -> Bool {
        let backend = loadGenerationBackendSelection()
        return backend == .auto || backend == .byok || backend == .local
    }

    private func loadBYOKSettings() -> BYOKSettingsPayload {
        let defaults = sharedDefaults()
        let provider = defaults?.string(forKey: AppConfig.byokProviderKey) ?? ""
        let apiURL = defaults?.string(forKey: AppConfig.byokApiURLKey) ?? ""
        let apiKey = defaults?.string(forKey: AppConfig.byokApiKeyKey) ?? ""
        let model = defaults?.string(forKey: AppConfig.byokModelKey) ?? ""
        return BYOKSettingsPayload(provider: provider, apiURL: apiURL, apiKey: apiKey, model: model)
    }

    private func resolveExecutionBackend(
        payload: [String: Any]?,
        selection: GenerationBackendSelection
    ) -> ExecutionBackend {
        if let raw = payload?["backend"] as? String,
           let backend = ExecutionBackend(rawValue: raw) {
            return backend
        }
        switch selection {
        case .byok:
            return .byok
        case .local:
            return .appleIntelligence
        case .auto:
            return .byok
        }
    }

    private func byokPayloadDict(_ payload: BYOKSettingsPayload) -> [String: Any] {
        [
            "provider": payload.provider,
            "apiURL": payload.apiURL,
            "apiKey": payload.apiKey,
            "model": payload.model,
        ]
    }

    private func complete(_ context: NSExtensionContext, responseMessage: [String: Any]) {
        let response = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            response.userInfo = [SFExtensionMessageKey: responseMessage]
        } else {
            response.userInfo = ["message": responseMessage]
        }
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    private func complete(
        _ context: NSExtensionContext,
        error: Error,
        name: String,
        fallbackCode: String
    ) {
        let errorType = String(describing: type(of: error))
        let resolvedCode = (error as? FoundationModelsStreamManager.StreamError)?.code ?? fallbackCode
        os_log(
            "[Eison-Native] ResponseError=%{public}@ errorType=%{public}@ code=%{public}@ message=%{public}@",
            log: Self.nativeLog,
            type: .info,
            name,
            errorType,
            resolvedCode,
            error.localizedDescription
        )
        complete(context, responseMessage: [
            "v": 1,
            "type": "error",
            "name": name,
            "payload": [
                "code": resolvedCode,
                "message": error.localizedDescription,
            ],
        ])
    }

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let profile: UUID?
        if #available(iOS 17.0, macOS 14.0, *) {
            profile = request?.userInfo?[SFExtensionProfileKey] as? UUID
        } else {
            profile = request?.userInfo?["profile"] as? UUID
        }

        let message: Any?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        let profileString = profile?.uuidString ?? "none"
        if let dict = message as? [String: Any] {
            let command = (dict["command"] as? String) ?? (dict["name"] as? String) ?? ""
//            os_log(
//                "[Eison-Native] Received native message command=%{public}@ (profile: %{public}@)",
//                log: Self.nativeLog,
//                type: .info,
//                command,
//                profileString
//            )
        } else {
            let messageType = message.map { String(describing: type(of: $0)) } ?? "nil"
            os_log(
                "[Eison-Native] Received native message (non-dict) (profile: %{public}@) type=%{public}@",
                log: Self.nativeLog,
                type: .error,
                profileString,
                messageType
            )
        }

        guard let dict = message as? [String: Any] else {
            complete(context, responseMessage: [
                "v": 1,
                "type": "error",
                "name": "error",
                "payload": [
                    "code": "INVALID_MESSAGE",
                    "message": "Expected an object message payload.",
                ],
            ])
            return
        }

        let command = (dict["command"] as? String) ?? (dict["name"] as? String) ?? ""
        switch command {
        case "getSystemPrompt":
            complete(context, responseMessage: [
                "v": 1,
                "type": "response",
                "name": "systemPrompt",
                "payload": [
                    "prompt": loadSystemPrompt(),
                ],
            ])
            return

        case "getChunkPrompt":
            complete(context, responseMessage: [
                "v": 1,
                "type": "response",
                "name": "chunkPrompt",
                "payload": [
                    "prompt": loadChunkPrompt(),
                ],
            ])
            return

        case "getTokenEstimatorEncoding":
            complete(context, responseMessage: [
                "v": 1,
                "type": "response",
                "name": "tokenEstimatorEncoding",
                "payload": [
                    "encoding": loadTokenEstimatorEncoding(),
                ],
            ])
            return

        case "getLongDocumentChunkTokenSize":
            complete(context, responseMessage: [
                "v": 1,
                "type": "response",
                "name": "longDocumentChunkTokenSize",
                "payload": [
                    "chunkTokenSize": loadLongDocumentChunkTokenSize(),
                    "allowedChunkSizes": LongDocumentDefaults.allowedChunkSizes,
                    "fallbackChunkSize": LongDocumentDefaults.fallbackChunkSize,
                    "routingThreshold": LongDocumentDefaults.routingThresholdValue,
                ],
            ])
            return

        case "getLongDocumentMaxChunks":
            complete(context, responseMessage: [
                "v": 1,
                "type": "response",
                "name": "longDocumentMaxChunks",
                "payload": [
                    "maxChunks": loadLongDocumentMaxChunks(),
                    "allowedMaxChunks": LongDocumentDefaults.allowedMaxChunkCounts,
                    "fallbackMaxChunks": LongDocumentDefaults.fallbackMaxChunkCount,
                ],
            ])
            return

        case "getAutoStrategySettings":
            Task {
                let applePayload = await FoundationModelsStreamManager.shared.appleAvailabilityPayload()
                complete(context, responseMessage: [
                    "v": 1,
                    "type": "response",
                    "name": "autoStrategySettings",
                    "payload": [
                        "strategyThreshold": loadAutoStrategyThreshold(),
                        "localPreference": loadAutoLocalPreference(),
                        "qwenEnabled": loadLocalQwenEnabled(),
                        "appleAvailability": applePayload,
                    ],
                ])
            }
            return

        case "getGenerationBackend":
            complete(context, responseMessage: [
                "v": 1,
                "type": "response",
                "name": "generationBackend",
                "payload": [
                    "backend": loadGenerationBackendSelection().rawValue,
                ],
            ])
            return

        case "getBYOKSettings":
            let byokSettings = loadBYOKSettings()
            complete(context, responseMessage: [
                "v": 1,
                "type": "response",
                "name": "byokSettings",
                "payload": byokPayloadDict(byokSettings),
            ])
            return

        case "setSystemPrompt":
            let prompt = dict["prompt"] as? String
            saveSystemPrompt(prompt)
            complete(context, responseMessage: [
                "v": 1,
                "type": "response",
                "name": "systemPrompt",
                "payload": [
                    "prompt": loadSystemPrompt(),
                ],
            ])
            return

        case "resetSystemPrompt":
            saveSystemPrompt(nil)
            complete(context, responseMessage: [
                "v": 1,
                "type": "response",
                "name": "systemPrompt",
                "payload": [
                    "prompt": loadSystemPrompt(),
                ],
            ])
            return

        case "fm.checkAvailability":
            Task {
                let selection = loadGenerationBackendSelection()
                let payloadDict = dict["payload"] as? [String: Any]
                let backend = resolveExecutionBackend(payload: payloadDict, selection: selection)
                let byokSettings = loadBYOKSettings()
                let payload = await FoundationModelsStreamManager.shared.checkAvailabilityPayload(
                    backend: backend,
                    byok: byokSettings
                )
                complete(context, responseMessage: [
                    "v": 1,
                    "type": "response",
                    "name": "fm.checkAvailability",
                    "payload": payload,
                ])
            }
            return

        case "fm.prewarm":
            Task {
                let selection = loadGenerationBackendSelection()
                let byokSettings = loadBYOKSettings()
                let payload = dict["payload"] as? [String: Any]
                let systemPrompt = (payload?["systemPrompt"] as? String) ?? ""
                let promptPrefix = payload?["promptPrefix"] as? String
                let backend = resolveExecutionBackend(payload: payload, selection: selection)

                do {
                    try await FoundationModelsStreamManager.shared.prewarm(
                        systemPrompt: systemPrompt,
                        promptPrefix: promptPrefix,
                        backend: backend,
                        byok: byokSettings,
                        tokenEstimate: readInt(payload?["tokenEstimate"])
                    )
                    complete(context, responseMessage: [
                        "v": 1,
                        "type": "response",
                        "name": "fm.prewarm",
                        "payload": [
                            "ok": true,
                        ],
                    ])
                } catch {
                    complete(context, responseMessage: [
                        "v": 1,
                        "type": "error",
                        "name": "fm.prewarm",
                        "payload": [
                            "code": "PREWARM_FAILED",
                            "message": error.localizedDescription,
                        ],
                    ])
                }
            }
            return

        case "fm.stream.start":
            Task {
                let selection = loadGenerationBackendSelection()
                let byokSettings = loadBYOKSettings()

                let payload = dict["payload"] as? [String: Any]
                let systemPrompt = (payload?["systemPrompt"] as? String) ?? ""
                let userPrompt = (payload?["userPrompt"] as? String) ?? ""
                let optionsDict = payload?["options"] as? [String: Any]
                let temperature = optionsDict?["temperature"] as? Double
                let maximumResponseTokens = optionsDict?["maximumResponseTokens"] as? Int
                let backend = resolveExecutionBackend(payload: payload, selection: selection)

                do {
                    let jobId = try await FoundationModelsStreamManager.shared.start(
                        systemPrompt: systemPrompt,
                        userPrompt: userPrompt,
                        temperature: temperature,
                        maximumResponseTokens: maximumResponseTokens,
                        backend: backend,
                        byok: byokSettings,
                        tokenEstimate: readInt(payload?["tokenEstimate"])
                    )
                    complete(context, responseMessage: [
                        "v": 1,
                        "type": "response",
                        "name": "fm.stream.start",
                        "payload": [
                            "jobId": jobId,
                            "cursor": 0,
                        ],
                    ])
                } catch {
                    complete(context, responseMessage: [
                        "v": 1,
                        "type": "error",
                        "name": "fm.stream.start",
                        "payload": [
                            "code": "START_FAILED",
                            "message": error.localizedDescription,
                        ],
                    ])
                }
            }
            return

        case "fm.stream.poll":
            Task {
                let payload = dict["payload"] as? [String: Any]
                let jobId = (payload?["jobId"] as? String) ?? ""
                let cursor = (payload?["cursor"] as? Int) ?? 0

                let result = await FoundationModelsStreamManager.shared.poll(jobId: jobId, cursor: cursor)
                switch result {
                case let .success(responsePayload):
                    complete(context, responseMessage: [
                        "v": 1,
                        "type": "response",
                        "name": "fm.stream.poll",
                        "payload": responsePayload,
                    ])
                case let .failure(error):
                    complete(
                        context,
                        error: error,
                        name: "fm.stream.poll",
                        fallbackCode: "POLL_FAILED"
                    )
                }
            }
            return

        case "fm.stream.cancel":
            Task {
                let payload = dict["payload"] as? [String: Any]
                let jobId = (payload?["jobId"] as? String) ?? ""
                await FoundationModelsStreamManager.shared.cancel(jobId: jobId)
                complete(context, responseMessage: [
                    "v": 1,
                    "type": "response",
                    "name": "fm.stream.cancel",
                    "payload": [
                        "ok": true,
                    ],
                ])
            }
            return

        case "saveRawItem":
            do {
                let payload = dict["payload"] as? [String: Any]
                let url = (payload?["url"] as? String) ?? ""
                let title = (payload?["title"] as? String) ?? ""
                let articleText = (payload?["articleText"] as? String) ?? ""
                let summaryText = (payload?["summaryText"] as? String) ?? ""
                let systemPrompt = (payload?["systemPrompt"] as? String) ?? ""
                let userPrompt = (payload?["userPrompt"] as? String) ?? ""
                let modelId = (payload?["modelId"] as? String) ?? ""
                let tokenEstimate = readInt(payload?["tokenEstimate"])
                let tokenEstimator = payload?["tokenEstimator"] as? String
                let chunkTokenSize = readInt(payload?["chunkTokenSize"])
                let routingThreshold = readInt(payload?["routingThreshold"])
                let isLongDocument = payload?["isLongDocument"] as? Bool
                let readingAnchors: [ReadingAnchorChunk]? = (payload?["readingAnchors"] as? [[String: Any]])?.compactMap { item in
                    guard let index = readInt(item["index"]),
                          let tokenCount = readInt(item["tokenCount"]),
                          let text = item["text"] as? String else {
                        return nil
                    }
                    let startUTF16 = readInt(item["startUTF16"])
                    let endUTF16 = readInt(item["endUTF16"])
                    return ReadingAnchorChunk(
                        index: index,
                        tokenCount: tokenCount,
                        text: text,
                        startUTF16: startUTF16,
                        endUTF16: endUTF16
                    )
                }

                let urlHash = sha256Hex(url)
                os_log(
                    "[Eison-Native] saveRawItem requested (profile: %{public}@) urlHash=%{public}@ urlLen=%d titleLen=%d articleLen=%d summaryLen=%d model=%{public}@",
                    log: Self.rawLibraryLog,
                    type: .info,
                    profile?.uuidString ?? "none",
                    urlHash,
                    url.count,
                    title.count,
                    articleText.count,
                    summaryText.count,
                    modelId
                )

                if summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw NSError(
                        domain: "EisonAI.RawLibrary",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "summaryText is required."]
                    )
                }

                let directoryURL: URL
                do {
                    directoryURL = try rawLibraryItemsDirectoryURL()
                    os_log(
                        "[Eison-Native] RawLibrary directory: %{public}@",
                        log: Self.rawLibraryLog,
                        type: .info,
                        directoryURL.path
                    )
                } catch {
                    os_log(
                        "[Eison-Native] RawLibrary directory unavailable: %{public}@",
                        log: Self.rawLibraryLog,
                        type: .error,
                        error.localizedDescription
                    )
                    throw error
                }

                let result = try saveRawHistoryItem(
                    url: url,
                    title: title,
                    articleText: articleText,
                    summaryText: summaryText,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    modelId: modelId,
                    readingAnchors: readingAnchors,
                    tokenEstimate: tokenEstimate,
                    tokenEstimator: tokenEstimator,
                    chunkTokenSize: chunkTokenSize,
                    routingThreshold: routingThreshold,
                    isLongDocument: isLongDocument
                )

                do {
                    let savedURL = directoryURL.appendingPathComponent(result.filename)
                    let items = try FileManager.default.contentsOfDirectory(
                        at: directoryURL,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    )
                    let jsonCount = items.filter { $0.pathExtension.lowercased() == "json" }.count
                    os_log(
                        "[Eison-Native] saveRawItem saved id=%{public}@ file=%{public}@ path=%{public}@ totalJSON=%d",
                        log: Self.rawLibraryLog,
                        type: .info,
                        result.id,
                        result.filename,
                        savedURL.path,
                        jsonCount
                    )

                    complete(context, responseMessage: [
                        "v": 1,
                        "type": "response",
                        "name": "saveRawItem",
                        "payload": [
                            "ok": true,
                            "id": result.id,
                            "filename": result.filename,
                            "directoryPath": directoryURL.path,
                            "savedPath": savedURL.path,
                            "totalJSON": jsonCount,
                        ],
                    ])
                } catch {
                    os_log(
                        "[Eison-Native] saveRawItem post-save listing failed: %{public}@",
                        log: Self.rawLibraryLog,
                        type: .error,
                        error.localizedDescription
                    )

                    complete(context, responseMessage: [
                        "v": 1,
                        "type": "response",
                        "name": "saveRawItem",
                        "payload": [
                            "ok": true,
                            "id": result.id,
                            "filename": result.filename,
                            "directoryPath": directoryURL.path,
                        ],
                    ])
                }
            } catch {
                os_log(
                    "[Eison-Native] saveRawItem failed: %{public}@",
                    log: Self.rawLibraryLog,
                    type: .error,
                    error.localizedDescription
                )
                complete(context, responseMessage: [
                    "v": 1,
                    "type": "error",
                    "name": "saveRawItem",
                    "payload": [
                        "code": "SAVE_FAILED",
                        "message": error.localizedDescription,
                    ],
                ])
            }
            return

        default:
            complete(context, responseMessage: [
                "v": 1,
                "type": "error",
                "name": "error",
                "payload": [
                    "code": "UNKNOWN_COMMAND",
                    "message": "Unsupported native command: \(command)",
                ],
            ])
            return
        }
    }
}

actor FoundationModelsStreamManager {
    static let shared = FoundationModelsStreamManager()

    enum StreamError: LocalizedError {
        case notSupported
        case unavailable(String)
        case jobNotFound
        case jobFailed(message: String, code: String?)

        var errorDescription: String? {
            switch self {
            case .notSupported:
                return "Native models require iOS 26+."
            case let .unavailable(reason):
                return reason
            case .jobNotFound:
                return "Stream job not found."
            case let .jobFailed(message, _):
                return message
            }
        }

        var code: String? {
            switch self {
            case .notSupported:
                return "NOT_SUPPORTED"
            case .unavailable:
                return "UNAVAILABLE"
            case .jobNotFound:
                return "JOB_NOT_FOUND"
            case let .jobFailed(_, code):
                return code ?? "JOB_FAILED"
            }
        }
    }

    private struct Job {
        var output: String = ""
        var done: Bool = false
        var error: String?
        var errorCode: String?
        var task: Task<Void, Never>?
    }

    private var prewarmSystemPrompt: String?
    private var prewarmPromptPrefix: String?
    private var prewarmedSession: AnyObject?

    private var jobs: [String: Job] = [:]

    func checkAvailabilityPayload(
        backend: ExecutionBackend,
        byok: BYOKSettingsPayload
    ) async -> [String: Any] {
        switch backend {
        case .mlc:
            return [
                "enabled": false,
                "available": false,
                "reason": "Using WebLLM backend.",
            ]
        case .byok:
            if let error = validateBYOK(byok) {
                return [
                    "enabled": true,
                    "available": false,
                    "reason": error,
                ]
            }
            return [
                "enabled": true,
                "available": true,
                "reason": "",
            ]
        case .appleIntelligence:
            return appleAvailabilityPayload()
        }
    }

    func appleAvailabilityPayload() -> [String: Any] {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return [
                "enabled": true,
                "available": false,
                "reason": "Requires iOS 26+ with Apple Intelligence.",
            ]
        }

        #if canImport(FoundationModels) && canImport(AnyLanguageModel)
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return [
                    "enabled": true,
                    "available": true,
                    "reason": "",
                ]
            case let .unavailable(reason):
                let message: String
                switch reason {
                case .deviceNotEligible:
                    message = "Device not eligible for Apple Intelligence."
                case .appleIntelligenceNotEnabled:
                    message = "Apple Intelligence is not enabled."
                case .modelNotReady:
                    message = "Apple Intelligence models are still downloading."
                @unknown default:
                    message = "Apple Intelligence is unavailable."
                }
                return [
                    "enabled": true,
                    "available": false,
                    "reason": message,
                ]
            }
        #else
            return [
                "enabled": true,
                "available": false,
                "reason": "Apple Intelligence framework is unavailable.",
            ]
        #endif
    }

    func prewarm(
        systemPrompt: String,
        promptPrefix: String?,
        backend: ExecutionBackend,
        byok: BYOKSettingsPayload,
        tokenEstimate: Int?
    ) async throws {
        if backend == .mlc {
            throw StreamError.notSupported
        }
        if backend == .byok {
            return
        }
        guard #available(iOS 26.0, macOS 26.0, *) else { throw StreamError.notSupported }
        #if canImport(FoundationModels) && canImport(AnyLanguageModel)
            let availability = SystemLanguageModel.default.availability
            if case let .unavailable(reason) = availability {
                let message: String
                switch reason {
                case .deviceNotEligible:
                    message = "Device not eligible for Apple Intelligence."
                case .appleIntelligenceNotEnabled:
                    message = "Apple Intelligence is not enabled."
                case .modelNotReady:
                    message = "Apple Intelligence models are still downloading."
                @unknown default:
                    message = "Apple Intelligence is unavailable."
                }
                throw StreamError.unavailable(message)
            }

            let trimmedPrefix = promptPrefix?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let prewarmedSession,
               prewarmSystemPrompt == systemPrompt,
               prewarmPromptPrefix == trimmedPrefix {
                return
            }

            let model = SystemLanguageModel(useCase: .general, guardrails: .default)
            let session = LanguageModelSession(model: model, instructions: Instructions(systemPrompt))
            session.prewarm(promptPrefix: Prompt(trimmedPrefix ?? ""))

            prewarmedSession = session
            prewarmSystemPrompt = systemPrompt
            prewarmPromptPrefix = trimmedPrefix
        #else
            throw StreamError.notSupported
        #endif
    }

    func start(
        systemPrompt: String,
        userPrompt: String,
        temperature: Double?,
        maximumResponseTokens: Int?,
        backend: ExecutionBackend,
        byok: BYOKSettingsPayload,
        tokenEstimate: Int?
    ) async throws -> String {
        if backend == .mlc {
            throw StreamError.notSupported
        }
        if backend == .byok, let error = validateBYOK(byok) {
            throw StreamError.unavailable(error)
        }
        if backend == .appleIntelligence {
            guard #available(iOS 26.0, macOS 26.0, *) else { throw StreamError.notSupported }
        }

        let jobId = UUID().uuidString
        var job = Job()

        let temp = temperature
        let maxTok = maximumResponseTokens

        job.task = Task {
            await self.runJob(
                jobId: jobId,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                temperature: temp,
                maximumResponseTokens: maxTok,
                backend: backend,
                byok: byok
            )
        }

        jobs[jobId] = job
        return jobId
    }

    #if canImport(AnyLanguageModel)
        private func runJob(
            jobId: String,
            systemPrompt: String,
            userPrompt: String,
            temperature: Double?,
            maximumResponseTokens: Int?,
            backend: ExecutionBackend,
            byok: BYOKSettingsPayload
        ) async {
            let options = GenerationOptions(
                sampling: nil,
                temperature: temperature,
                maximumResponseTokens: maximumResponseTokens
            )

            do {
                let model = try buildModel(backend: backend, byok: byok)
                let session = takePrewarmedSession(systemPrompt: systemPrompt, userPrompt: userPrompt)
                    ?? LanguageModelSession(model: model, instructions: Instructions(systemPrompt))
                let stream = session.streamResponse(to: Prompt(userPrompt), options: options)

                var previous = ""
                for try await partial in stream {
                    if Task.isCancelled { break }
                    let current = String(partial.content)
                    let delta: String
                    if current.hasPrefix(previous) {
                        delta = String(current.dropFirst(previous.count))
                    } else {
                        delta = current
                    }
                    previous = current
                    if !delta.isEmpty {
                        appendDelta(jobId: jobId, delta: delta)
                    }
                }

                markDone(jobId: jobId)
            } catch let generationError as LanguageModelSession.GenerationError {
                let errorCode = FoundationModelsStreamManager.mapFoundationModelsGenerationErrorCode(generationError)
                markError(jobId: jobId, message: generationError.localizedDescription, code: errorCode)
            } catch {
                let errorCode = resolveFoundationModelsErrorCode(error)
                markError(jobId: jobId, message: error.localizedDescription, code: errorCode)
            }
        }
    #endif

    #if canImport(AnyLanguageModel)
        private func takePrewarmedSession(systemPrompt: String, userPrompt: String) -> LanguageModelSession? {
            guard let prewarmedSession = prewarmedSession as? LanguageModelSession,
                  prewarmSystemPrompt == systemPrompt else {
                return nil
            }

            if let prefix = prewarmPromptPrefix,
               !prefix.isEmpty,
               !userPrompt.hasPrefix(prefix) {
                return nil
            }

            self.prewarmedSession = nil
            prewarmSystemPrompt = nil
            prewarmPromptPrefix = nil
            return prewarmedSession
        }
    #endif

    private func validateBYOK(_ byok: BYOKSettingsPayload) -> String? {
        let trimmedURL = byok.apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL.isEmpty {
            return "API URL 必填"
        }
        let lower = trimmedURL.lowercased()
        if !(lower.hasSuffix("/v1") || lower.hasSuffix("/v1/")) {
            return "URL 缺乏 /v1 結尾"
        }
        if URL(string: trimmedURL) == nil {
            return "API URL 無效"
        }
        if byok.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Model 必填"
        }
        return nil
    }

    #if canImport(AnyLanguageModel)
        private enum BYOKHTTPProvider: String {
            case ollama
            case anthropic
            case gemini
            case openAIChat = "openai.chat"
            case openAIResponses = "openai.responses"
        }

        private func buildModel(
            backend: ExecutionBackend,
            byok: BYOKSettingsPayload
        ) throws -> any LanguageModel {
            switch backend {
            case .mlc:
                throw StreamError.notSupported
            case .appleIntelligence:
                guard #available(iOS 26.0, macOS 26.0, *) else {
                    throw StreamError.notSupported
                }
                #if canImport(FoundationModels)
                    let availability = SystemLanguageModel.default.availability
                    if case let .unavailable(reason) = availability {
                        let message: String
                        switch reason {
                        case .deviceNotEligible:
                            message = "Device not eligible for Apple Intelligence."
                        case .appleIntelligenceNotEnabled:
                            message = "Apple Intelligence is not enabled."
                        case .modelNotReady:
                            message = "Apple Intelligence models are still downloading."
                        @unknown default:
                            message = "Apple Intelligence is unavailable."
                        }
                        throw StreamError.unavailable(message)
                    }
                    return SystemLanguageModel(useCase: .general, guardrails: .default)
                #else
                    throw StreamError.notSupported
                #endif
            case .byok:
                if let error = validateBYOK(byok) {
                    throw StreamError.unavailable(error)
                }
                let provider = BYOKHTTPProvider(rawValue: byok.provider) ?? .openAIChat
                let baseURL = try resolveBaseURL(for: provider, rawValue: byok.apiURL)
                let modelID = byok.model.trimmingCharacters(in: .whitespacesAndNewlines)
                switch provider {
                case .openAIChat:
                    return OpenAILanguageModel(
                        baseURL: baseURL,
                        apiKey: byok.apiKey,
                        model: modelID,
                        apiVariant: .chatCompletions
                    )
                case .openAIResponses:
                    return OpenAILanguageModel(
                        baseURL: baseURL,
                        apiKey: byok.apiKey,
                        model: modelID,
                        apiVariant: .responses
                    )
                case .ollama:
                    return OllamaLanguageModel(baseURL: baseURL, model: modelID)
                case .anthropic:
                    return AnthropicLanguageModel(baseURL: baseURL, apiKey: byok.apiKey, model: modelID)
                case .gemini:
                    return GeminiLanguageModel(baseURL: baseURL, apiKey: byok.apiKey, model: modelID)
                }
            }
        }

        private func resolveBaseURL(for provider: BYOKHTTPProvider, rawValue: String) throws -> URL {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed) else {
                throw StreamError.unavailable("API URL 無效")
            }

            var resolved = url
            let lowercasedPath = resolved.path.lowercased()
            if provider != .openAIChat && provider != .openAIResponses {
                if lowercasedPath.hasSuffix("/v1") || lowercasedPath.hasSuffix("/v1/") {
                    resolved.deleteLastPathComponent()
                }
            }
            if !resolved.path.hasSuffix("/") {
                resolved.appendPathComponent("")
            }
            return resolved
        }
    #endif

    private func appendDelta(jobId: String, delta: String) {
        guard var job = jobs[jobId] else { return }
        guard !job.done else { return }
        job.output.append(delta)
        jobs[jobId] = job
    }

    private func markDone(jobId: String) {
        guard var job = jobs[jobId] else { return }
        job.done = true
        job.task = nil
        jobs[jobId] = job
    }

    private func markError(jobId: String, message: String, code: String?) {
        guard var job = jobs[jobId] else { return }
        job.done = true
        job.error = message
        job.errorCode = code
        job.task = nil
        jobs[jobId] = job
    }

    func poll(jobId: String, cursor: Int) async -> Result<[String: Any], Error> {
        guard let job = jobs[jobId] else { return .failure(StreamError.jobNotFound) }
        if let error = job.error {
            return .failure(StreamError.jobFailed(message: error, code: job.errorCode))
        }

        let safeCursor = max(0, min(cursor, job.output.utf16.count))
        let startIndex = String.Index(utf16Offset: safeCursor, in: job.output)
        let delta = String(job.output[startIndex...])

        return .success([
            "delta": delta,
            "cursor": job.output.utf16.count,
            "done": job.done,
            "error": job.error ?? "",
            "errorCode": job.errorCode ?? "",
        ])
    }

    func cancel(jobId: String) async {
        guard var job = jobs[jobId] else { return }
        job.task?.cancel()
        job.done = true
        jobs[jobId] = job
    }

    private func resolveFoundationModelsErrorCode(_ error: Error) -> String? {
        var pending: [Error] = [error]
        var seenDescriptions = Set<String>()

        while let current = pending.popLast() {
            let description = String(describing: current)
            if !description.isEmpty, !seenDescriptions.insert(description).inserted {
                continue
            }

            if let generationError = current as? LanguageModelSession.GenerationError {
                return FoundationModelsStreamManager.mapFoundationModelsGenerationErrorCode(generationError)
            }

            let nsError = current as NSError
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                pending.append(underlying)
            }
            if let underlyingErrors = nsError.userInfo[NSMultipleUnderlyingErrorsKey] as? [Error] {
                pending.append(contentsOf: underlyingErrors)
            }
        }
        return nil
    }

    #if canImport(AnyLanguageModel)
        fileprivate static func mapFoundationModelsGenerationErrorCode(
            _ generationError: LanguageModelSession.GenerationError
        ) -> String {
            switch generationError {
            case .exceededContextWindowSize:
                return "EXCEEDED_CONTEXT_WINDOW"
            case .unsupportedLanguageOrLocale:
                return "FM_UNSUPPORTED_LOCALE"
            case .assetsUnavailable:
                return "FM_GEN_ASSETS_UNAVAILABLE"
            case .guardrailViolation:
                return "FM_GEN_GUARDRAIL_VIOLATION"
            case .decodingFailure:
                return "FM_GEN_DECODING_FAILURE"
            case .unsupportedGuide:
                return "FM_GEN_UNSUPPORTED_GUIDE"
            case .rateLimited:
                return "FM_GEN_RATE_LIMITED"
            case .concurrentRequests:
                return "FM_GEN_CONCURRENT_REQUESTS"
            case .refusal:
                return "FM_GEN_REFUSAL"
            @unknown default:
                return "FM_GEN_UNKNOWN"
            }
        }
    #endif
}
