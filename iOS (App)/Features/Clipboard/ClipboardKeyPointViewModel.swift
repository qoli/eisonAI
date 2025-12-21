import Foundation
import UIKit

@MainActor
final class ClipboardKeyPointViewModel: ObservableObject {
    private static let prewarmPrefixMaxChars = 1200

    private let input: KeyPointInput

    @Published var status: String = "Ready"
    @Published var output: String = ""
    @Published var sourceDescription: String = ""
    @Published var isRunning: Bool = false
    @Published var shouldDismiss: Bool = false

    private let mlc = MLCClient()
    private let foundationModels = FoundationModelsClient()
    private let foundationSettings = FoundationModelsSettingsStore()
    private let extractor = ReadabilityWebExtractor()
    private let store = RawLibraryStore()

    private var runTask: Task<Void, Never>?

    init(input: KeyPointInput = .clipboard) {
        self.input = input
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        status = "Canceled"
        shouldDismiss = false
        Task { [mlc] in
            await mlc.reset()
        }
    }

    func run() {
        runTask?.cancel()
        runTask = nil

        output = ""
        sourceDescription = ""
        isRunning = true
        status = "Preparing…"
        shouldDismiss = false
        log("run started, input=\(inputDescription)")

        runTask = Task { [weak self] in
            guard let self else { return }

            do {
                let normalized: PreparedInput
                switch self.input {
                case .clipboard:
                    let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !clip.isEmpty else {
                        self.status = "Clipboard is empty."
                        self.log("clipboard empty")
                        self.isRunning = false
                        return
                    }
                    self.status = "Reading clipboard…"
                    normalized = try await self.prepareInput(from: clip)
                case .share(let payload):
                    self.status = "Reading shared content…"
                    normalized = try await self.prepareInput(fromSharePayload: payload)
                }
                if Task.isCancelled { throw CancellationError() }
                log("prepared input url=\(normalized.url.isEmpty ? "nil" : normalized.url) titleCount=\(normalized.title.count) textCount=\(normalized.text.count)")

                let systemPrompt = self.loadKeyPointSystemPrompt()
                let userPrompt = Self.buildUserPrompt(title: normalized.title, text: normalized.text)

                let useFoundationModels = self.foundationSettings.isAppEnabled()
                    && FoundationModelsAvailability.currentStatus() == .available

                let stream: AsyncThrowingStream<String, Error>
                if useFoundationModels {
                    let prewarmPrefix = Self.clampText(userPrompt, maxChars: Self.prewarmPrefixMaxChars)
                    foundationModels.prewarm(systemPrompt: systemPrompt, promptPrefix: prewarmPrefix)
                    self.status = "Generating…"
                    stream = try await self.foundationModels.streamChat(
                        systemPrompt: systemPrompt,
                        userPrompt: userPrompt,
                        temperature: 0.4,
                        maximumResponseTokens: 2048
                    )
                } else {
                    self.status = "Loading model…"
                    try await self.mlc.loadIfNeeded()

                    self.status = "Generating…"
                    stream = try await self.mlc.streamChat(systemPrompt: systemPrompt, userPrompt: userPrompt)
                }

                var finalText = ""
                for try await delta in stream {
                    if Task.isCancelled { break }
                    finalText.append(delta)
                    self.output = finalText
                }

                if Task.isCancelled {
                    self.status = "Canceled"
                    self.isRunning = false
                    return
                }

                let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self.status = "Done (empty output)"
                    self.log("empty output")
                    self.isRunning = false
                    return
                }

                self.status = "Saving…"
                try self.store.saveRawItem(
                    url: normalized.url,
                    title: normalized.title,
                    articleText: normalized.text,
                    summaryText: trimmed,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    modelId: useFoundationModels ? "foundation-models" : (self.mlc.loadedModelID ?? "")
                )

                self.status = "Done (saved)"
                self.shouldDismiss = true
                self.log("saved output, dismissing")
            } catch is CancellationError {
                self.status = "Canceled"
                self.log("canceled")
            } catch {
                self.status = "Error: \(error.localizedDescription)"
                self.log("error: \(error.localizedDescription)")
            }

            self.isRunning = false
        }
    }

    private struct PreparedInput {
        var url: String
        var title: String
        var text: String
    }

    private func prepareInput(from clipboardText: String) async throws -> PreparedInput {
        let lower = clipboardText.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://"), let url = URL(string: clipboardText) {
            sourceDescription = clipboardText
            status = "Loading URL…"
            let article = try await extractor.extract(from: url)
            let title = article.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = article.text.trimmingCharacters(in: .whitespacesAndNewlines)
            status = "Extracted article text"
            return PreparedInput(url: article.url, title: title, text: body)
        }

        sourceDescription = "Plain text (\(clipboardText.count) chars)"
        status = "Using clipboard text"
        return PreparedInput(url: "", title: "", text: clipboardText)
    }

    private func prepareInput(fromSharePayload payload: SharePayload) async throws -> PreparedInput {
        let trimmedURL = payload.url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = payload.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let text = trimmedText, !text.isEmpty {
            if let urlString = trimmedURL, !urlString.isEmpty {
                sourceDescription = urlString
            } else {
                sourceDescription = "Shared text (\(text.count) chars)"
            }
            status = "Using shared text"
            return PreparedInput(url: trimmedURL ?? "", title: trimmedTitle ?? "", text: text)
        }

        if let urlString = trimmedURL, !urlString.isEmpty, let url = URL(string: urlString) {
            sourceDescription = urlString
            status = "Loading URL…"
            let article = try await extractor.extract(from: url)
            let title = article.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = article.text.trimmingCharacters(in: .whitespacesAndNewlines)
            status = "Extracted article text"
            return PreparedInput(url: article.url, title: title, text: body)
        }

        throw NSError(
            domain: "EisonAI.SharePayload",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Shared content is empty."]
        )
    }

    private func loadKeyPointSystemPrompt() -> String {
        let fallbackBase = """
        你是一個內容整理助手。
        """

        let base = BundledTextResource.loadUTF8(name: "default_system_prompt", ext: "txt") ?? fallbackBase

        print(base)
        
        return """
        \(base)
        """
        
        
        
    }

    private static func buildUserPrompt(title: String, text: String) -> String {
        let clippedText = clampText(text, maxChars: 8000)
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            normalizedTitle.isEmpty ? "(no title)" : normalizedTitle,
            "【正文】\n\(clippedText.isEmpty ? "(empty)" : clippedText)",
        ].joined(separator: "\n\n")
    }

    private static func clampText(_ text: String, maxChars: Int) -> String {
        guard maxChars > 0 else { return "" }
        if text.count <= maxChars { return text }
        let idx = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[..<idx])
    }

    private var inputDescription: String {
        switch input {
        case .clipboard:
            return "clipboard"
        case .share(let payload):
            return "share(id=\(payload.id))"
        }
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[KeyPoint] \(message)")
        #endif
    }
}
