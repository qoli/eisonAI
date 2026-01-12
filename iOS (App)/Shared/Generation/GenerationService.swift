import Foundation

@MainActor
final class GenerationService {
    static let shared = GenerationService()

    private let defaultMLC = MLCClient()
    private let defaultAnyLanguageModels = AnyLanguageModelClient()
    private let backendSettings = GenerationBackendSettingsStore()
    private let byokSettingsStore = BYOKSettingsStore()
    private let tokenEstimator = GPTTokenEstimator.shared

    private let rawLibraryStore = RawLibraryStore()
    private let titlePromptStore = TitlePromptStore()

    private init() {}

    /// Generates and persists a title for the given item if needed.
    /// - Returns: Updated item when a new title was saved; otherwise `nil`.
    func generateTitleIfNeeded(
        force: Bool,
        fileURL: URL,
        mlc: MLCClient? = nil,
        anyLanguageModels: AnyLanguageModelClient? = nil,
        backendSettings: GenerationBackendSettingsStore? = nil,
        byokSettingsStore: BYOKSettingsStore? = nil
    ) async -> RawHistoryItem? {
        let mlc = mlc ?? defaultMLC
        let anyLanguageModels = anyLanguageModels ?? defaultAnyLanguageModels
        let backendSettings = backendSettings ?? self.backendSettings
        let byokSettingsStore = byokSettingsStore ?? self.byokSettingsStore

        do {
            let item = try rawLibraryStore.loadItem(fileURL: fileURL)
            let currentTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !force && !currentTitle.isEmpty { return nil }

            log("title generation start force=\(force) path=\(fileURL.lastPathComponent)")

            let systemPrompt = titlePromptStore.load()
            let userPrompt = buildTitleUserPrompt(for: item)

            let stream: AsyncThrowingStream<String, Error>
            let tokenEstimate = await tokenEstimator.estimateTokenCount(for: userPrompt)
            let backend = backendSettings.effectiveBackend(tokenCount: tokenEstimate)
            switch backend {
            case .mlc:
                try await mlc.loadIfNeeded()
                stream = try await mlc.streamChat(systemPrompt: systemPrompt, userPrompt: userPrompt)
            case .appleIntelligence:
                let prefix = clampText(userPrompt, maxChars: 800)
                anyLanguageModels.prewarm(systemPrompt: systemPrompt, promptPrefix: prefix, backend: backend)
                stream = try await anyLanguageModels.streamChat(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    temperature: 0.4,
                    maximumResponseTokens: 128,
                    backend: backend
                )
            case .byok:
                let byokSettings = byokSettingsStore.loadSettings()
                if let error = byokSettingsStore.validationError(for: byokSettings) {
                    log("title generation invalid BYOK error=\(error.message)")
                    return nil
                }
                stream = try await anyLanguageModels.streamChat(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    temperature: 0.4,
                    maximumResponseTokens: 128,
                    backend: backend,
                    byok: byokSettings
                )
            case .auto:
                throw NSError(
                    domain: "EisonAI.Generation",
                    code: 20,
                    userInfo: [NSLocalizedDescriptionKey: "Auto backend must be resolved before generation."]
                )
            }

            var output = ""
            for try await chunk in stream {
                if Task.isCancelled { break }
                output += chunk
            }
            if Task.isCancelled { return nil }

            if backend == .mlc, isQwen3Model(mlc.loadedModelID) {
                log("title generation stripping <think> tags for qwen3")
                output = stripThinkTags(output)
            }

            let title = sanitizeTitle(output)
            guard !title.isEmpty else { return nil }
            log("title generation result=\"\(title)\"")
            return try rawLibraryStore.updateTitle(fileURL: fileURL, title: title)
        } catch {
            log("title generation error \(error.localizedDescription)")
            // No-op: failure strategy is silent.
            return nil
        }
    }

    private func buildTitleUserPrompt(for item: RawHistoryItem) -> String {
        let pieces = [
            item.summaryText,
            item.articleText,
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")

        let content = pieces.isEmpty ? item.url : pieces
        return clampText(content, maxChars: 1400)
    }

    private func sanitizeTitle(_ text: String) -> String {
        let strippedMarkdown = stripMarkdown(text)
        let trimmed = strippedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let stripped = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.trimmingCharacters(in: CharacterSet(charactersIn: "\"「」"))
    }

    private func clampText(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        let idx = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[..<idx])
    }

    private func isQwen3Model(_ modelID: String?) -> Bool {
        guard let modelID else { return false }
        return modelID.lowercased().contains("qwen3-0.6b")
    }

    private func stripThinkTags(_ text: String) -> String {
        let pattern = "(?is)<think>.*?</think>"
        var cleaned = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "<think>", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive)
        return cleaned
    }

    private func stripMarkdown(_ text: String) -> String {
        var output = text
        // Remove fenced code blocks
        output = output.replacingOccurrences(of: "(?s)```.*?```", with: "", options: .regularExpression)
        // Remove inline code
        output = output.replacingOccurrences(of: "`([^`]*)`", with: "$1", options: .regularExpression)
        // Images: ![alt](url) -> alt
        output = output.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\([^\\)]*\\)", with: "$1", options: .regularExpression)
        // Links: [text](url) -> text
        output = output.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]*\\)", with: "$1", options: .regularExpression)
        // Headings and blockquotes
        output = output.replacingOccurrences(of: "(?m)^(\\s{0,3}#{1,6}\\s+)", with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: "(?m)^(\\s*>\\s?)", with: "", options: .regularExpression)
        // Bold/italic markers
        output = output.replacingOccurrences(of: "(\\*\\*|__)", with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: "(\\*|_)", with: "", options: .regularExpression)
        // List markers
        output = output.replacingOccurrences(of: "(?m)^(\\s*[-+*]\\s+)", with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: "(?m)^(\\s*\\d+\\.\\s+)", with: "", options: .regularExpression)
        return output
    }

    private func log(_ message: String) {
        #if DEBUG
            print("[Generation] \(message)")
        #endif
    }
}
