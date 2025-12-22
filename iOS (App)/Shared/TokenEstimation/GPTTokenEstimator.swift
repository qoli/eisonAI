import Foundation

struct GPTTokenChunk: Codable, Hashable {
    let index: Int
    let tokenCount: Int
    let text: String
    let startUTF16: Int
    let endUTF16: Int
}

final class GPTTokenEstimator {
    static let shared = GPTTokenEstimator()

    private let encoder = GPTEncoder()
    private let lock = NSLock()

    func estimateTokenCount(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return encode(text).count
    }

    func chunk(text: String, chunkTokenSize: Int) -> [GPTTokenChunk] {
        guard chunkTokenSize > 0 else { return [] }
        guard !text.isEmpty else { return [] }

        let tokens = encode(text)
        guard !tokens.isEmpty else { return [] }

        var chunks: [GPTTokenChunk] = []
        chunks.reserveCapacity((tokens.count + chunkTokenSize - 1) / chunkTokenSize)

        var tokenIndex = 0
        var utf16Offset = 0
        while tokenIndex < tokens.count {
            let endIndex = min(tokenIndex + chunkTokenSize, tokens.count)
            let tokenSlice = Array(tokens[tokenIndex ..< endIndex])
            let chunkText = decode(tokenSlice)
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

    private func encode(_ text: String) -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return encoder.encode(text: text)
    }

    private func decode(_ tokens: [Int]) -> String {
        lock.lock()
        defer { lock.unlock() }
        return encoder.decode(tokens: tokens)
    }
}
