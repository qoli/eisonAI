import Foundation
import TiktokenSwift

struct GPTTokenChunk: Codable, Hashable {
    let index: Int
    let tokenCount: Int
    let text: String
    let startUTF16: Int
    let endUTF16: Int
}

actor TokenizerStore {
    static let shared = TokenizerStore()

    private var encoder: CoreBpe?

    func loadEncoder() async throws -> CoreBpe {
        if let encoder {
            return encoder
        }
        let loaded = try await CoreBpe.o200kBase()
        encoder = loaded
        return loaded
    }
}

final class GPTTokenEstimator {
    static let shared = GPTTokenEstimator()

    private let store = TokenizerStore.shared

    func estimateTokenCount(for text: String) async -> Int {
        guard !text.isEmpty else { return 0 }
        do {
            let encoder = try await store.loadEncoder()
            return encoder.encode(text: text, allowedSpecial: []).count
        } catch {
            return 0
        }
    }

    func chunk(text: String, chunkTokenSize: Int) async -> [GPTTokenChunk] {
        guard chunkTokenSize > 0 else { return [] }
        guard !text.isEmpty else { return [] }

        let tokens: [UInt32]
        let encoder: CoreBpe
        do {
            encoder = try await store.loadEncoder()
            tokens = encoder.encode(text: text, allowedSpecial: [])
        } catch {
            return []
        }
        guard !tokens.isEmpty else { return [] }

        var chunks: [GPTTokenChunk] = []
        chunks.reserveCapacity((tokens.count + chunkTokenSize - 1) / chunkTokenSize)

        var tokenIndex = 0
        var utf16Offset = 0
        while tokenIndex < tokens.count {
            let endIndex = min(tokenIndex + chunkTokenSize, tokens.count)
            let tokenSlice = Array(tokens[tokenIndex ..< endIndex])
            let chunkText: String
            do {
                chunkText = try encoder.decode(tokens: tokenSlice) ?? ""
            } catch {
                chunkText = ""
            }
            let chunkUTF16Count = chunkText.utf16.count

            let chunk = GPTTokenChunk(
                index: chunks.count,
                tokenCount: tokenSlice.count,
                text: chunkText,
                startUTF16: utf16Offset,
                endUTF16: utf16Offset + chunkUTF16Count
            )
            chunks.append(chunk)

            utf16Offset += chunkUTF16Count
            tokenIndex = endIndex
        }

        return chunks
    }
}
