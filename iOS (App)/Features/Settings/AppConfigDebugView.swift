import SwiftUI

struct AppConfigDebugView: View {
    @State private var defaultsSnapshot: [String: String] = [:]

    private struct ConstantEntry: Identifiable {
        let id = UUID()
        let name: String
        let value: String
    }

    private struct DefaultsEntry: Identifiable {
        let id = UUID()
        let name: String
        let key: String
    }

    private var constants: [ConstantEntry] {
        [
            ConstantEntry(name: "appGroupIdentifier", value: AppConfig.appGroupIdentifier),
            ConstantEntry(name: "rawLibraryMaxItems", value: String(AppConfig.rawLibraryMaxItems)),
            ConstantEntry(
                name: "rawLibraryRootPathComponents",
                value: AppConfig.rawLibraryRootPathComponents.joined(separator: " / ")
            ),
            ConstantEntry(
                name: "rawLibraryItemsPathComponents",
                value: AppConfig.rawLibraryItemsPathComponents.joined(separator: " / ")
            ),
            ConstantEntry(
                name: "rawLibraryFavoriteItemsPathComponents",
                value: AppConfig.rawLibraryFavoriteItemsPathComponents.joined(separator: " / ")
            ),
            ConstantEntry(name: "rawLibraryFavoriteIndexFilename", value: AppConfig.rawLibraryFavoriteIndexFilename),
            ConstantEntry(name: "rawLibraryTagsCacheFilename", value: AppConfig.rawLibraryTagsCacheFilename),
            ConstantEntry(name: "rawLibrarySyncManifestFilename", value: AppConfig.rawLibrarySyncManifestFilename),
            ConstantEntry(
                name: "sharePayloadsPathComponents",
                value: AppConfig.sharePayloadsPathComponents.joined(separator: " / ")
            ),
            ConstantEntry(name: "lifetimeAccessProductId", value: AppConfig.lifetimeAccessProductId),
            ConstantEntry(
                name: "defaultSystemPrompt (chars)",
                value: String(AppConfig.defaultSystemPrompt.count)
            ),
            ConstantEntry(
                name: "defaultChunkPrompt (chars)",
                value: String(AppConfig.defaultChunkPrompt.count)
            ),
            ConstantEntry(
                name: "defaultTitlePrompt (chars)",
                value: String(AppConfig.defaultTitlePrompt.count)
            ),
        ]
    }

    private var defaultsEntries: [DefaultsEntry] {
        [
            DefaultsEntry(name: "systemPromptKey", key: AppConfig.systemPromptKey),
            DefaultsEntry(name: "modelLanguageKey", key: AppConfig.modelLanguageKey),
            DefaultsEntry(name: "chunkPromptKey", key: AppConfig.chunkPromptKey),
            DefaultsEntry(name: "translatedSummaryPromptKey", key: AppConfig.translatedSummaryPromptKey),
            DefaultsEntry(name: "translatedChunkPromptKey", key: AppConfig.translatedChunkPromptKey),
            DefaultsEntry(name: "titlePromptKey", key: AppConfig.titlePromptKey),
            DefaultsEntry(name: "generationBackendKey", key: AppConfig.generationBackendKey),
            DefaultsEntry(name: "foundationModelsAppEnabledKey", key: AppConfig.foundationModelsAppEnabledKey),
            DefaultsEntry(name: "foundationModelsExtensionEnabledKey", key: AppConfig.foundationModelsExtensionEnabledKey),
            DefaultsEntry(name: "byokProviderKey", key: AppConfig.byokProviderKey),
            DefaultsEntry(name: "byokApiURLKey", key: AppConfig.byokApiURLKey),
            DefaultsEntry(name: "byokApiKeyKey", key: AppConfig.byokApiKeyKey),
            DefaultsEntry(name: "byokModelKey", key: AppConfig.byokModelKey),
            DefaultsEntry(
                name: "byokLongDocumentChunkTokenSizeKey",
                key: AppConfig.byokLongDocumentChunkTokenSizeKey
            ),
            DefaultsEntry(
                name: "byokLongDocumentRoutingThresholdKey",
                key: AppConfig.byokLongDocumentRoutingThresholdKey
            ),
            DefaultsEntry(name: "autoStrategyThresholdKey", key: AppConfig.autoStrategyThresholdKey),
            DefaultsEntry(name: "autoLocalModelPreferenceKey", key: AppConfig.autoLocalModelPreferenceKey),
            DefaultsEntry(name: "localQwenEnabledKey", key: AppConfig.localQwenEnabledKey),
            DefaultsEntry(name: "sharePollingEnabledKey", key: AppConfig.sharePollingEnabledKey),
            DefaultsEntry(name: "shareOpenAppAfterShareKey", key: AppConfig.shareOpenAppAfterShareKey),
            DefaultsEntry(name: "tokenEstimatorEncodingKey", key: AppConfig.tokenEstimatorEncodingKey),
            DefaultsEntry(name: "longDocumentChunkTokenSizeKey", key: AppConfig.longDocumentChunkTokenSizeKey),
            DefaultsEntry(name: "longDocumentMaxChunkCountKey", key: AppConfig.longDocumentMaxChunkCountKey),
            DefaultsEntry(name: "onboardingCompletedKey", key: AppConfig.onboardingCompletedKey),
        ]
    }

    var body: some View {
        Form {
            Section("Constants") {
                ForEach(constants) { entry in
                    AppConfigRow(title: entry.name, value: entry.value)
                }
            }

            Section("UserDefaults (App Group)") {
                ForEach(defaultsEntries) { entry in
                    AppConfigRow(
                        title: entry.name,
                        value: defaultsSnapshot[entry.key] ?? "(unset)"
                    )
                }
            }
        }
        .navigationTitle("AppConfig")
        .toolbar {
            Button("Refresh") {
                reload()
            }
        }
        .onAppear {
            reload()
        }
    }

    private func reload() {
        guard let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier) else {
            defaultsSnapshot = [:]
            return
        }
        var snapshot: [String: String] = [:]
        for entry in defaultsEntries {
            let rawValue = defaults.object(forKey: entry.key)
            snapshot[entry.key] = formatValue(entry.key, rawValue)
        }
        defaultsSnapshot = snapshot
    }

    private func formatValue(_ key: String, _ value: Any?) -> String {
        guard let value else { return "(unset)" }

        if key == AppConfig.byokApiKeyKey {
            let raw = String(describing: value)
            if raw.isEmpty { return "(empty)" }
            return "•••••••• (\(raw.count) chars)"
        }

        switch value {
        case let boolValue as Bool:
            return boolValue ? "true" : "false"
        case let intValue as Int:
            return String(intValue)
        case let doubleValue as Double:
            return String(doubleValue)
        case let stringValue as String:
            return shorten(stringValue)
        case let arrayValue as [String]:
            return arrayValue.joined(separator: ", ")
        default:
            return shorten(String(describing: value))
        }
    }

    private func shorten(_ value: String, limit: Int = 200) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(empty)" }
        if trimmed.count <= limit { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return "\(trimmed[..<idx])… (\(trimmed.count) chars)"
    }
}

private struct AppConfigRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        AppConfigDebugView()
    }
}
