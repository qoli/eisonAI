import SwiftUI

struct DocumentsSettingsView: View {
    private let longDocumentSettingsStore = LongDocumentSettingsStore.shared
    private let longDocumentChunkSizeOptions: [Int] = [2000, 2200, 2600, 3000, 3200]
    private let longDocumentMaxChunkOptions: [Int] = [4, 5, 6, 7]
    private let tokenEstimatorSettingsStore = TokenEstimatorSettingsStore.shared
    private let tokenEstimatorOptions: [Encoding] = [.cl100k, .o200k, .p50k, .r50k]

    @State private var didLoad = false
    @State private var longDocumentChunkTokenSize: Int = 2000
    @State private var longDocumentMaxChunkCount: Int = 5
    @State private var tokenEstimatorEncoding: Encoding = .cl100k

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Long Document Processing")
                        .font(.headline)

                    Text("eisonAI estimates token count with the selected tokenizer. If a document exceeds the routing threshold, it is split into fixed-size chunks. The app extracts key points per chunk, then generates a short summary from those key points.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Overview")
            }

            Section {
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
            } header: {
                Text("Chunk Size")
            } footer: {
                Text("Chunk size is measured in tokens. Routing threshold is fixed at 2600 tokens.")
            }

            Section {
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
            } header: {
                Text("Chunk Limit")
            } footer: {
                Text("Chunks beyond the limit are discarded to keep processing time predictable.")
            }

            Section {
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

            } header: {
                Text("Token Counting")
            } footer: {
                Text("Applies to token estimation and chunking in both the app and Safari extension.")
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
