import NaturalLanguage
import SwiftUI
import UIKit

struct ClipboardTokenChunkingView: View {
    @State private var inputText = ""
    @State private var tokensPerChunk = 2000
    @State private var chunks: [String] = []
    @State private var chunkTokenCounts: [Int] = []
    @State private var tokenCount = 0
    @State private var status = ""

    var body: some View {
        Form {
            Section("Input") {
                Text("Paste or type text, then split into \(tokensPerChunk)-token chunks.")
                    .foregroundStyle(.secondary)
                Text("Tokenizer: iOS NaturalLanguage word tokenizer (approximate, not model-specific).")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text("Tokens per chunk")
                    TextField("2000", value: $tokensPerChunk, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 80, maxWidth: 120)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: tokensPerChunk) { newValue in
                            if newValue < 1 {
                                tokensPerChunk = 1
                            }
                        }
                }

                TextEditor(text: $inputText)
                    .frame(minHeight: 160)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                HStack(spacing: 12) {
                    Button("Read Clipboard") {
                        readClipboard()
                    }
                    .buttonStyle(.bordered)

                    Button("Split") {
                        splitIntoChunks()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Clear") {
                        clear()
                    }
                    .buttonStyle(.bordered)
                }

                if !status.isEmpty {
                    Text(status)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Summary") {
                Text("Tokens: \(tokenCount)")
                Text("Chunks: \(chunks.count)")
                    .foregroundStyle(.secondary)
            }

            Section("Copy") {
                if chunks.isEmpty {
                    Text("No chunks yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chunks.indices, id: \.self) { index in
                                Button("Copy \(index + 1)") {
                                    UIPasteboard.general.string = chunks[index]
                                    status = "Copied chunk \(index + 1)."
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Chunks") {
                if chunks.isEmpty {
                    Text("No chunks yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(chunks.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            let tokenCount = chunkTokenCounts[index]
                            Text("Chunk \(index + 1) (\(tokenCount) tokens)")
                                .font(.headline)

                            Text(chunks[index])
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("Token Splitter")
    }

    private func readClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            status = "Clipboard is empty."
            return
        }
        inputText = text
        status = "Loaded \(text.count) characters from clipboard."
        splitIntoChunks()
    }

    private func clear() {
        inputText = ""
        chunks = []
        chunkTokenCounts = []
        tokenCount = 0
        status = "Cleared."
    }

    private func splitIntoChunks() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clear()
            return
        }

        let ranges = tokenRanges(for: trimmed)
        tokenCount = ranges.count
        guard !ranges.isEmpty else {
            chunks = [trimmed]
            chunkTokenCounts = [0]
            status = "Tokenizer produced no tokens."
            return
        }

        var newChunks: [String] = []
        var newTokenCounts: [Int] = []
        var index = 0

        while index < ranges.count {
            let start = ranges[index].lowerBound
            let endIndex = ranges[min(index + tokensPerChunk - 1, ranges.count - 1)].upperBound
            let chunkText = String(trimmed[start..<endIndex])
            newChunks.append(chunkText)

            let count = min(tokensPerChunk, ranges.count - index)
            newTokenCounts.append(count)
            index += tokensPerChunk
        }

        chunks = newChunks
        chunkTokenCounts = newTokenCounts
        status = "Split into \(newChunks.count) chunk(s)."
    }

    private func tokenRanges(for text: String) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ranges.append(range)
            return true
        }
        if ranges.isEmpty, !text.isEmpty {
            return [text.startIndex..<text.endIndex]
        }
        return ranges
    }
}
