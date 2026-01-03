import SwiftUI

struct DocumentsSettingsView: View {
    private let longDocumentSettingsStore = LongDocumentSettingsStore.shared
    private let longDocumentChunkSizeOptions: [Int] = [2200, 2600, 3000, 3200]
    private let longDocumentMaxChunkOptions: [Int] = [4, 5, 6, 7]
    private let tokenEstimatorSettingsStore = TokenEstimatorSettingsStore.shared
    private let tokenEstimatorOptions: [Encoding] = [.cl100k, .o200k, .p50k, .r50k]

    @State private var didLoad = false
    @State private var longDocumentChunkTokenSize: Int = 2600
    @State private var longDocumentMaxChunkCount: Int = 5
    @State private var tokenEstimatorEncoding: Encoding = .cl100k

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Long Document Processing")
                        .font(.headline)

                    Text("eisonAI estimates document length with the selected tokenizer. If a document exceeds the chunk threshold, it is split into fixed-size chunks. The app extracts key points per chunk, then creates a short summary from those points. Extra chunks beyond the limit are skipped to keep results fast and stable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("How It Works")
            }

            Section("Long Documents") {
                Picker(
                    "Chunk size for long documents",
                    selection: Binding(
                        get: { longDocumentChunkTokenSize },
                        set: { newValue in
                            longDocumentChunkTokenSize = newValue
                            longDocumentSettingsStore.setChunkTokenSize(newValue)
                        }
                    )
                ) {
                    ForEach(longDocumentChunkSizeOptions, id: \.self) { size in
                        Text("\(size)").tag(size)
                    }
                }

                Text("Long documents are split into chunks of this size.")
                    .foregroundStyle(.secondary)

                Picker(
                    "Max number of chunks",
                    selection: Binding(
                        get: { longDocumentMaxChunkCount },
                        set: { newValue in
                            longDocumentMaxChunkCount = newValue
                            longDocumentSettingsStore.setMaxChunkCount(newValue)
                        }
                    )
                ) {
                    ForEach(longDocumentMaxChunkOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }

                Text("Chunks beyond the limit are discarded.")
                    .foregroundStyle(.secondary)
            }

            Section("Token Counting") {
                Picker(
                    "Token counting model",
                    selection: Binding(
                        get: { tokenEstimatorEncoding },
                        set: { newValue in
                            tokenEstimatorEncoding = newValue
                            tokenEstimatorSettingsStore.setSelectedEncoding(newValue)
                        }
                    )
                ) {
                    ForEach(tokenEstimatorOptions, id: \.self) { encoding in
                        Text(encoding.rawValue).tag(encoding)
                    }
                }

                Text("This affects token counts in both the app and Safari extension.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Documents")
        .onAppear {
            if !didLoad {
                didLoad = true
                longDocumentChunkTokenSize = longDocumentSettingsStore.chunkTokenSize()
                longDocumentMaxChunkCount = longDocumentSettingsStore.maxChunkCount()
                tokenEstimatorEncoding = tokenEstimatorSettingsStore.selectedEncoding()
            }
        }
    }
}

#Preview {
    NavigationStack {
        DocumentsSettingsView()
    }
}
