//
//  MLCQwenDemoView.swift
//  iOS (App)
//
//  Single-turn streaming demo using MLC Swift SDK (MLCSwift).
//

import SwiftUI

#if canImport(MLCSwift)
import MLCSwift
#endif

@MainActor
final class MLCQwenDemoViewModel: ObservableObject {
    @Published var prompt: String = ""
    @Published var output: String = ""
    @Published var status: String = ""
    @Published var isLoading: Bool = false
    @Published var isGenerating: Bool = false

    private var loadTask: Task<Void, Never>?
    private var generateTask: Task<Void, Never>?

#if canImport(MLCSwift)
    private let engine = MLCEngine()
#endif
    private let modelIDCandidates = [
        "Qwen3-0.6B-q4f16_1-MLC",
        "Qwen3-0.6B-q0f16-MLC",
    ]

    func onAppear() {
        guard loadTask == nil else { return }
        status = "Loading model…"
        isLoading = true

        loadTask = Task { [weak self] in
            guard let self else { return }
#if canImport(MLCSwift)
            do {
                let selected = try self.resolveBundledModel()
                try await self.loadEngine(modelPath: selected.modelPath, modelLib: selected.modelLib)
                self.status = "Ready (\(selected.modelID))"
            } catch {
                self.status = "Error: \(error.localizedDescription)"
            }
#else
            self.status = "MLCSwift not integrated."
#endif
            self.isLoading = false
        }
    }

    func clear() {
        generateTask?.cancel()
        generateTask = nil
        prompt = ""
        output = ""
        status = "Cleared."
        isGenerating = false
#if canImport(MLCSwift)
        Task { [engine] in
            await engine.reset()
        }
#endif
    }

    func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isLoading else { return }

        generateTask?.cancel()
        generateTask = nil

        output = ""
        status = "Generating…"
        isGenerating = true

        generateTask = Task { [weak self] in
            guard let self else { return }
#if canImport(MLCSwift)
            do {
                await self.engine.reset()
                let stream = await self.engine.chat.completions.create(
                    messages: [
                        ChatCompletionMessage(role: .user, content: text),
                    ]
                )
                for await res in stream {
                    if Task.isCancelled { break }
                    if let delta = res.choices.first?.delta.content?.asText() {
                        self.output.append(delta)
                    }
                }
                if Task.isCancelled {
                    self.status = "Canceled"
                } else {
                    self.status = "Done"
                }
            } catch {
                if Task.isCancelled {
                    self.status = "Canceled"
                } else {
                    self.status = "Error: \(error.localizedDescription)"
                }
            }
#else
            self.status = "MLCSwift not integrated."
#endif
            self.isGenerating = false
        }
    }

#if canImport(MLCSwift)
    private func loadEngine(modelPath: String, modelLib: String) async throws {
        await engine.reload(modelPath: modelPath, modelLib: modelLib)
    }
#endif

    private struct BundledModel {
        let modelID: String
        let modelPath: String
        let modelLib: String
    }

    private struct AppConfig: Decodable {
        struct ModelRecord: Decodable {
            let modelPath: String?
            let modelLib: String
            let modelID: String

            enum CodingKeys: String, CodingKey {
                case modelPath = "model_path"
                case modelLib = "model_lib"
                case modelID = "model_id"
            }
        }

        let modelList: [ModelRecord]

        enum CodingKeys: String, CodingKey {
            case modelList = "model_list"
        }
    }

    private enum DemoError: LocalizedError {
        case missingBundledConfig(URL)
        case missingBundledModel(String)

        var errorDescription: String? {
            switch self {
            case .missingBundledConfig(let url):
                return "Missing bundled config: \(url.lastPathComponent). Did you add `dist/bundle` to app resources?"
            case .missingBundledModel(let modelID):
                return "Model not found in `mlc-app-config.json`: \(modelID)"
            }
        }
    }

    private func resolveBundledModel() throws -> BundledModel {
        let configURL = Bundle.main.bundleURL.appending(path: "bundle/mlc-app-config.json")
        guard FileManager.default.fileExists(atPath: configURL.path()) else {
            throw DemoError.missingBundledConfig(configURL)
        }

        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)

        for modelID in modelIDCandidates {
            if let record = config.modelList.first(where: { $0.modelID == modelID && $0.modelPath != nil }) {
                let modelDir = Bundle.main.bundleURL
                    .appending(path: "bundle")
                    .appending(path: record.modelPath!)
                    .path()
                return BundledModel(modelID: modelID, modelPath: modelDir, modelLib: record.modelLib)
            }
        }

        throw DemoError.missingBundledModel(modelIDCandidates.first ?? "(unknown)")
    }
}

struct MLCQwenDemoView: View {
    @StateObject private var model = MLCQwenDemoViewModel()

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Input", text: $model.prompt, axis: .vertical)
                    .lineLimit(1...6)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { model.send() }

                HStack(spacing: 12) {
                    Button("Send") { model.send() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isLoading || model.isGenerating || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Clear") { model.clear() }
                        .buttonStyle(.bordered)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(model.status)
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(model.output.isEmpty ? "—" : model.output)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

#if !canImport(MLCSwift)
            VStack(alignment: .leading, spacing: 8) {
                Text("Missing dependency: MLCSwift")
                    .font(.headline)
                Text("Follow https://llm.mlc.ai/docs/deploy/ios.html → “Build Apps with MLC Swift API” to add the local package `ios/MLCSwift`, bundle `dist/bundle`, and link the required libraries.")
                    .foregroundStyle(.secondary)
            }
#endif
        }
        .padding()
        .navigationTitle("Qwen3 0.6B Demo")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.onAppear() }
    }
}
