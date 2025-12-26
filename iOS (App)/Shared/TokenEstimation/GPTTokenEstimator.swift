import Foundation

struct GPTTokenChunk: Codable, Hashable {
    let index: Int
    let tokenCount: Int
    let text: String
    let startUTF16: Int
    let endUTF16: Int
}

actor SwiftikTokenStore {
    static let shared = SwiftikTokenStore()

    enum Error: Swift.Error {
        case vocabularyFileNotFound
    }

    private var tokenizers: [Encoding: Tokenizer] = [:]

    func loadTokenizer(for encoding: Encoding) async throws -> Tokenizer {
        if let tokenizer = tokenizers[encoding] {
            return tokenizer
        }

        guard let fileURL = Bundle.main.url(
            forResource: encoding.rawValue,
            withExtension: "tiktoken"
        ) else {
            throw Error.vocabularyFileNotFound
        }

        let encoder = try await Loader().load(fileURL: fileURL)
        let regex = try encoding.pattern.makeRegex()
        let tokenEncoder = TokenEncoder(
            encoder: encoder,
            specialTokenEncoder: encoding.specialTokenEncoder,
            regex: regex
        )
        let tokenizer = Tokenizer(
            encoder: tokenEncoder,
            specialTokens: encoding.specialTokens
        )
        tokenizers[encoding] = tokenizer
        return tokenizer
    }

    func encode(text: String, encoding: Encoding) async throws -> [Token] {
        let tokenizer = try await loadTokenizer(for: encoding)
        return try tokenizer.encode(
            text: text,
            allowedSpecial: [],
            disallowedSpecial: []
        )
    }
}

final class GPTTokenEstimator {
    static let shared = GPTTokenEstimator()

    private let store = SwiftikTokenStore.shared
    private let settingsStore = TokenEstimatorSettingsStore.shared

    func estimateTokenCount(for text: String) async -> Int {
        let encoding = settingsStore.selectedEncoding()
        return await estimateTokenCount(for: text, encoding: encoding)
    }

    private func estimateTokenCount(for text: String, encoding: Encoding) async -> Int {
        guard !text.isEmpty else { return 0 }
        do {
            return try await store.encode(text: text, encoding: encoding).count
        } catch {
            return 0
        }
    }

    func chunk(text: String, chunkTokenSize: Int, maxChunks: Int? = nil) async -> [GPTTokenChunk] {
        guard chunkTokenSize > 0 else { return [] }
        guard !text.isEmpty else { return [] }

        let indices = Array(text.indices)
        guard !indices.isEmpty else { return [] }

        let encoding = settingsStore.selectedEncoding()
        var chunks: [GPTTokenChunk] = []
        let maxChunkCount = maxChunks.map { max(1, $0) }
        let reserveCount = maxChunkCount ?? max(1, indices.count / chunkTokenSize)
        chunks.reserveCapacity(reserveCount)

        var startPos = 0
        var utf16Offset = 0
        while startPos < indices.count {
            if let maxChunkCount, chunks.count >= maxChunkCount {
                break
            }
            let endPos = await findChunkEnd(
                text: text,
                indices: indices,
                startPos: startPos,
                chunkTokenSize: chunkTokenSize,
                encoding: encoding
            )
            let startIndex = indices[startPos]
            let endIndex = endPos < indices.count ? indices[endPos] : text.endIndex
            let chunkText = String(text[startIndex..<endIndex])
            let tokenCount = await estimateTokenCount(for: chunkText, encoding: encoding)
            let chunkUTF16Count = chunkText.utf16.count

            chunks.append(
                GPTTokenChunk(
                    index: chunks.count,
                    tokenCount: tokenCount,
                    text: chunkText,
                    startUTF16: utf16Offset,
                    endUTF16: utf16Offset + chunkUTF16Count
                )
            )

            utf16Offset += chunkUTF16Count
            startPos = max(endPos, startPos + 1)
        }

        return chunks
    }

    private func findChunkEnd(
        text: String,
        indices: [String.Index],
        startPos: Int,
        chunkTokenSize: Int,
        encoding: Encoding
    ) async -> Int {
        let totalCount = indices.count
        let startIndex = indices[startPos]

        var low = startPos + 1
        var high = totalCount
        var best = min(startPos + 1, totalCount)

        while low <= high {
            let mid = (low + high) / 2
            let endIndex = mid < totalCount ? indices[mid] : text.endIndex
            let slice = String(text[startIndex..<endIndex])
            let tokenCount = await estimateTokenCount(for: slice, encoding: encoding)

            if tokenCount <= chunkTokenSize {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return best
    }
}
