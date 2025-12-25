//
//  TagEditorView.swift
//  iOS (App)
//
//  Created by Codex on 2025/12/25.
//

import SwiftUI

struct TagEditorView: View {
    var fileURL: URL
    var title: String

    @StateObject private var viewModel = TagEditorViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Current Tags") {
                    if viewModel.tags.isEmpty {
                        Text("No tags")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.tags, id: \.self) { tag in
                            HStack {
                                Text(tag)
                                Spacer()
                                Button {
                                    viewModel.removeTag(tag)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .tint(.red)
                                .accessibilityLabel("Remove tag")
                            }
                        }
                    }
                }

                Section("Add Tag") {
                    HStack {
                        TextField("Tag", text: $viewModel.newTag)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit {
                                viewModel.addTagFromInput()
                            }

                        Button("Add") {
                            viewModel.addTagFromInput()
                        }
                        .disabled(viewModel.newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Recent Tags") {
                    if viewModel.cachedTags.isEmpty {
                        Text("No cached tags")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.cachedTags, id: \.tag) { entry in
                            Button {
                                viewModel.addTag(entry.tag)
                            } label: {
                                HStack {
                                    Text(entry.tag)
                                    Spacer()
                                    Text(entry.lastUsedAt, style: .relative)
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                            .disabled(viewModel.tags.contains(entry.tag))
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                viewModel.load(fileURL: fileURL)
            }
        }
    }
}
