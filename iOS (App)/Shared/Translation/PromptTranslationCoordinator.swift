import Foundation
import SwiftUI

#if canImport(Translation)
    import Translation
#endif

@MainActor
final class PromptTranslationCoordinator: ObservableObject {
    static let shared = PromptTranslationCoordinator()

    @Published private var configurationStorage: Any?

    private var pendingRequest: TranslationRequest?

    struct TranslationResult {
        let summary: String
        let chunk: String
    }

    func requestTranslation(
        summary: String,
        chunk: String,
        targetLanguageTag: String
    ) async -> TranslationResult? {
        #if canImport(Translation)
            guard #available(iOS 17.4, macOS 14.4, macCatalyst 26.0, *) else { return nil }
            return await withCheckedContinuation { continuation in
                pendingRequest = TranslationRequest(
                    summary: summary,
                    chunk: chunk,
                    continuation: continuation
                )
                configurationStorage = TranslationSession.Configuration(
                    source: nil,
                    target: Locale.Language(identifier: targetLanguageTag)
                )
            }
        #else
            return nil
        #endif
    }

    #if canImport(Translation)
        @available(iOS 17.4, macOS 14.4, macCatalyst 26.0, *)
        func handleTranslation(session: TranslationSession) async {
            guard let request = pendingRequest else { return }
            pendingRequest = nil

            do {
                let summaryText = try await translateIfNeeded(request.summary, with: session)
                let chunkText = try await translateIfNeeded(request.chunk, with: session)
                request.continuation.resume(
                    returning: TranslationResult(summary: summaryText, chunk: chunkText)
                )
            } catch {
                request.continuation.resume(returning: nil)
            }

            configurationStorage = nil
        }
    #endif
}

@MainActor
private extension PromptTranslationCoordinator {
    struct TranslationRequest {
        let summary: String
        let chunk: String
        let continuation: CheckedContinuation<TranslationResult?, Never>
    }

    #if canImport(Translation)
        @available(iOS 17.4, macOS 14.4, macCatalyst 26.0, *)
        func translateIfNeeded(_ text: String, with session: TranslationSession) async throws -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            let response = try await session.translate(trimmed)
            return response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    #endif
}

#if canImport(Translation)
    @available(iOS 17.4, macOS 14.4, macCatalyst 26.0, *)
    extension PromptTranslationCoordinator {
        var configuration: TranslationSession.Configuration? {
            get { configurationStorage as? TranslationSession.Configuration }
            set { configurationStorage = newValue }
        }
    }

    @available(iOS 17.4, macOS 14.4, macCatalyst 26.0, *)
    struct TranslationTaskHost: View {
        @ObservedObject private var coordinator = PromptTranslationCoordinator.shared

        var body: some View {
            Color.clear
                .translationTask(coordinator.configuration) { session in
                    print("[TranslationTaskHost] translationTask started")
                    await coordinator.handleTranslation(session: session)
                    print("[TranslationTaskHost] translationTask finished")
                }
        }
    }
#endif
