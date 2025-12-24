import SwiftUI
import UIKit

struct ClipboardTokenChunkingView: View {
    @State private var inputText = ""
    @State private var tokensPerChunk = 2600
    @State private var chunks: [String] = []
    @State private var chunkTokenCounts: [Int] = []
    @State private var tokenCount = 0
    @State private var status = ""
    private let tokenEstimator = GPTTokenEstimator.shared

    var body: some View {
        Form {
            Section("Actions") {
                ScrollView(.horizontal, showsIndicators: false) {
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

                        if !chunks.isEmpty {
                            ForEach(chunks.indices, id: \.self) { index in
                                Button("Copy \(index + 1)") {
                                    UIPasteboard.general.string = chunks[index]
                                    status = "Copied chunk \(index + 1)."
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Input") {
                Text("Paste or type text, then split into \(tokensPerChunk)-token chunks.")
                    .foregroundStyle(.secondary)
                Text("Tokenizer: Tiktoken (o200k_base), same as Key-point pipeline.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text("Tokens per chunk")
                    TextField("2600", value: $tokensPerChunk, format: .number)
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

        Task {
            let totalTokens = await tokenEstimator.estimateTokenCount(for: trimmed)
            let chunkSize = max(1, tokensPerChunk)
            let gptChunks = await tokenEstimator.chunk(text: trimmed, chunkTokenSize: chunkSize)
            let newChunks = gptChunks.map { $0.text }
            let newTokenCounts = gptChunks.map { $0.tokenCount }

            await MainActor.run {
                tokenCount = totalTokens
                guard totalTokens > 0 else {
                    chunks = [trimmed]
                    chunkTokenCounts = [0]
                    status = "Tokenizer produced no tokens."
                    return
                }

                chunks = newChunks
                chunkTokenCounts = newTokenCounts
                status = "Split into \(newChunks.count) chunk(s)."
            }
        }
    }
}
