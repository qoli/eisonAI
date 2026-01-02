import SwiftUI

struct PromptSettingsView: View {
    private let systemPromptStore = SystemPromptStore()
    private let chunkPromptStore = ChunkPromptStore()
    private let titlePromptStore = TitlePromptStore()

    @State private var summaryPrompt = ""
    @State private var chunkPrompt = ""
    @State private var titlePrompt = ""
    @State private var modelLanguage = ""

    @State private var summaryStatus = ""
    @State private var chunkStatus = ""
    @State private var titleStatus = ""
    @State private var didLoad = false

    var body: some View {
        Form {
            Section("Summary system prompt") {
                Text("Used by Safari extension summaries and in-app clipboard summaries.")
                    .foregroundStyle(.secondary)

                TextEditor(text: $summaryPrompt)
                    .frame(minHeight: 160)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Text("A language hint is automatically appended: \"- 請使用\(ModelLanguage.displayName(forTag: modelLanguage))輸出\".")
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Save") {
                        systemPromptStore.saveBase(summaryPrompt)
                        summaryPrompt = systemPromptStore.loadBase()
                        summaryStatus = "Saved."
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reset to default") {
                        systemPromptStore.saveBase(nil)
                        summaryPrompt = systemPromptStore.loadBase()
                        summaryStatus = "Reset to default."
                    }
                    .buttonStyle(.bordered)
                }

                if !summaryStatus.isEmpty {
                    Text(summaryStatus)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Chunk system prompt") {
                Text("Used when extracting key points from long documents.")
                    .foregroundStyle(.secondary)

                TextEditor(text: $chunkPrompt)
                    .frame(minHeight: 160)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                HStack {
                    Button("Save") {
                        chunkPromptStore.save(chunkPrompt)
                        chunkPrompt = chunkPromptStore.load()
                        chunkStatus = "Saved."
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reset to default") {
                        chunkPromptStore.save(nil)
                        chunkPrompt = chunkPromptStore.load()
                        chunkStatus = "Reset to default."
                    }
                    .buttonStyle(.bordered)
                }

                if !chunkStatus.isEmpty {
                    Text(chunkStatus)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Title prompt") {
                Text("Used when rebuilding missing titles in the Library detail view.")
                    .foregroundStyle(.secondary)

                TextEditor(text: $titlePrompt)
                    .frame(minHeight: 120)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                HStack {
                    Button("Save") {
                        titlePromptStore.save(titlePrompt)
                        titlePrompt = titlePromptStore.load()
                        titleStatus = "Saved."
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reset to default") {
                        titlePromptStore.save(nil)
                        titlePrompt = titlePromptStore.load()
                        titleStatus = "Reset to default."
                    }
                    .buttonStyle(.bordered)
                }

                if !titleStatus.isEmpty {
                    Text(titleStatus)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Prompt Settings")
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            summaryPrompt = systemPromptStore.loadBase()
            chunkPrompt = chunkPromptStore.load()
            titlePrompt = titlePromptStore.load()
            modelLanguage = ModelLanguageStore().loadOrRecommended()
        }
    }
}
