import Foundation
import UIKit

@MainActor
final class ClipboardKeyPointViewModel: ObservableObject {
    private static let prewarmPrefixMaxChars = 1200
    private static let longDocumentRoutingThreshold = 2600
    private static let chunkTokenSize = 2000
    private static let readingAnchorMaxResponseTokens = 1024

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
    private let tokenEstimator = GPTTokenEstimator.shared

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

                let useFoundationModels = self.foundationSettings.isAppEnabled()
                    && FoundationModelsAvailability.currentStatus() == .available

                let tokenEstimate = self.tokenEstimator.estimateTokenCount(for: normalized.text)
                let isLongDocument = tokenEstimate > Self.longDocumentRoutingThreshold

                let result: PipelineResult
                if isLongDocument {
                result = try await self.runLongDocumentPipeline(
                        normalized,
                        useFoundationModels: useFoundationModels
                    )
                } else {
                result = try await self.runSingleSummary(
                        normalized,
                        useFoundationModels: useFoundationModels
                    )
                }

                if Task.isCancelled {
                    self.status = "Canceled"
                    self.isRunning = false
                    return
                }

                let trimmed = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    systemPrompt: result.systemPrompt,
                    userPrompt: result.userPrompt,
                    modelId: result.modelId,
                    readingAnchors: result.readingAnchors,
                    tokenEstimate: tokenEstimate,
                    tokenEstimator: "gpt2-bpe",
                    chunkTokenSize: isLongDocument ? Self.chunkTokenSize : nil,
                    routingThreshold: Self.longDocumentRoutingThreshold,
                    isLongDocument: isLongDocument
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

    private struct PipelineResult {
        var summary: String
        var systemPrompt: String
        var userPrompt: String
        var modelId: String
        var readingAnchors: [ReadingAnchorChunk]?
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

    private func runSingleSummary(
        _ input: PreparedInput,
        useFoundationModels: Bool
    ) async throws -> PipelineResult {
        let systemPrompt = loadKeyPointSystemPrompt()
        let userPrompt = Self.buildUserPrompt(title: input.title, text: input.text)

        let modelId: String
        let summary: String
        if useFoundationModels {
            let prewarmPrefix = Self.clampText(userPrompt, maxChars: Self.prewarmPrefixMaxChars)
            foundationModels.prewarm(systemPrompt: systemPrompt, promptPrefix: prewarmPrefix)
            status = "Generating…"
            let stream = try await foundationModels.streamChat(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                temperature: 0.4,
                maximumResponseTokens: 2048
            )
            summary = try await collectStream(stream, updateOutput: true)
            modelId = "foundation-models"
        } else {
            status = "Loading model…"
            try await mlc.loadIfNeeded()
            status = "Generating…"
            let stream = try await mlc.streamChat(systemPrompt: systemPrompt, userPrompt: userPrompt)
            summary = try await collectStream(stream, updateOutput: true)
            modelId = mlc.loadedModelID ?? ""
        }

        return PipelineResult(
            summary: summary,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            modelId: modelId,
            readingAnchors: nil
        )
    }

    private func runLongDocumentPipeline(
        _ input: PreparedInput,
        useFoundationModels: Bool
    ) async throws -> PipelineResult {
        status = "Chunking…"
        let chunks = tokenEstimator.chunk(text: input.text, chunkTokenSize: Self.chunkTokenSize)
        if chunks.isEmpty {
            throw NSError(
                domain: "EisonAI.LongDocument",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Chunking produced no output."]
            )
        }

        if !useFoundationModels {
            status = "Loading model…"
            try await mlc.loadIfNeeded()
        }

        var readingAnchors: [ReadingAnchorChunk] = []
        readingAnchors.reserveCapacity(chunks.count)

        for chunk in chunks {
            if Task.isCancelled { throw CancellationError() }
            status = "Reading chunk \(chunk.index + 1)/\(chunks.count)…"

            let anchorSystemPrompt = buildReadingAnchorSystemPrompt(
                chunkIndex: chunk.index + 1,
                chunkTotal: chunks.count
            )
            let anchorUserPrompt = buildReadingAnchorUserPrompt(text: chunk.text)

            let anchorText: String
            if useFoundationModels {
                let stream = try await foundationModels.streamChat(
                    systemPrompt: anchorSystemPrompt,
                    userPrompt: anchorUserPrompt,
                    temperature: 0.4,
                    maximumResponseTokens: Self.readingAnchorMaxResponseTokens
                )
                anchorText = try await collectStream(stream, updateOutput: false)
            } else {
                let stream = try await mlc.streamChat(systemPrompt: anchorSystemPrompt, userPrompt: anchorUserPrompt)
                anchorText = try await collectStream(stream, updateOutput: false)
            }

            let trimmedAnchor = anchorText.trimmingCharacters(in: .whitespacesAndNewlines)
            let anchor = ReadingAnchorChunk(
                index: chunk.index,
                tokenCount: chunk.tokenCount,
                text: trimmedAnchor,
                startUTF16: chunk.startUTF16,
                endUTF16: chunk.endUTF16
            )
            readingAnchors.append(anchor)
        }

        let summarySystemPrompt = AppConfig.defaultSystemPrompt
        let summaryUserPrompt = buildSummaryUserPrompt(from: readingAnchors)

        status = "Generating summary…"
        let summary: String
        let modelId: String
        if useFoundationModels {
            let prewarmPrefix = Self.clampText(summaryUserPrompt, maxChars: Self.prewarmPrefixMaxChars)
            foundationModels.prewarm(systemPrompt: summarySystemPrompt, promptPrefix: prewarmPrefix)
            let stream = try await foundationModels.streamChat(
                systemPrompt: summarySystemPrompt,
                userPrompt: summaryUserPrompt,
                temperature: 0.4,
                maximumResponseTokens: 2048
            )
            summary = try await collectStream(stream, updateOutput: true)
            modelId = "foundation-models"
        } else {
            let stream = try await mlc.streamChat(systemPrompt: summarySystemPrompt, userPrompt: summaryUserPrompt)
            summary = try await collectStream(stream, updateOutput: true)
            modelId = mlc.loadedModelID ?? ""
        }

        return PipelineResult(
            summary: summary,
            systemPrompt: summarySystemPrompt,
            userPrompt: summaryUserPrompt,
            modelId: modelId,
            readingAnchors: readingAnchors
        )
    }

    private func buildReadingAnchorSystemPrompt(chunkIndex: Int, chunkTotal: Int) -> String {
        return """
        你是一個文字整理員。

        你目前的任務是，正在協助用戶完整閱讀超長內容。

        - 當前這是原文中的一個段落（chunks \(chunkIndex) of \(chunkTotal)）
        - 擷取此文章的關鍵點
        """
    }

    private func buildReadingAnchorUserPrompt(text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return "【正文】\n\(trimmed.isEmpty ? "(empty)" : trimmed)"
    }

    private func buildSummaryUserPrompt(from anchors: [ReadingAnchorChunk]) -> String {
        if anchors.isEmpty { return "(empty)" }
        return anchors
            .map { chunk in
                let label = "Chunk \(chunk.index + 1)"
                return "\(label)\n\(chunk.text)"
            }
            .joined(separator: "\n\n")
    }

    private func collectStream(_ stream: AsyncThrowingStream<String, Error>, updateOutput: Bool) async throws -> String {
        var finalText = ""
        for try await delta in stream {
            if Task.isCancelled { break }
            finalText.append(delta)
            if updateOutput {
                output = finalText
            }
        }
        return finalText
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
