//
//  RootView.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import SwiftUI

struct RootView: View {
    private let store = SystemPromptStore()

    @State private var draftPrompt = ""
    @State private var status = ""
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Safari Extension") {
                    Text("Enable eisonAI’s Safari extension in Settings → Safari → Extensions.")
                    Text("Summaries run in the extension popup via WebLLM (bundled assets).")
                        .foregroundStyle(.secondary)
                }

                Section("History") {
                    NavigationLink("View history") {
                        HistoryView()
                    }
                    Text("Saved summaries are stored in the shared App Group folder.")
                        .foregroundStyle(.secondary)
                }

                Section("System prompt") {
                    Text("Used by the Safari extension popup summary.")
                        .foregroundStyle(.secondary)

                    TextEditor(text: $draftPrompt)
                        .frame(minHeight: 180)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    HStack {
                        Button("Save") {
                            store.save(draftPrompt)
                            draftPrompt = store.load()
                            status = "Saved."
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Reset to default") {
                            store.save(nil)
                            draftPrompt = store.load()
                            status = "Reset to default."
                        }
                        .buttonStyle(.bordered)
                    }

                    if !status.isEmpty {
                        Text(status)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("eisonAI")
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            draftPrompt = store.load()
        }
    }
}
