//
//  MLCQwenDemoView.swift
//  iOS (App)
//
//  Single-turn streaming demo using MLC Swift SDK (MLCSwift).
//

import SwiftUI

#if !targetEnvironment(simulator)
    #if canImport(MLCSwift)
        import MLCSwift
    #endif
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

    #if !targetEnvironment(simulator)
        #if canImport(MLCSwift)
            private let engine = MLCEngine()
        #endif
    #endif
    private let modelIDCandidates = [
        "Qwen3-0.6B-q4f16_1-MLC",
        "Qwen3-0.6B-q0f16-MLC",
    ]
    private let embeddedExtensionBundleID = "com.qoli.eisonAI.Extension"

    func onAppear() {
        guard loadTask == nil else { return }
        status = "Loading model…"
        isLoading = true

        loadTask = Task { [weak self] in
            guard let self else { return }
            #if !targetEnvironment(simulator)
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
            #else
                self.status = "MLC is disabled on Simulator."
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
        #if !targetEnvironment(simulator)
            #if canImport(MLCSwift)
                Task { [engine] in
                    await engine.reset()
                }
            #endif
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
            #if !targetEnvironment(simulator)
                #if canImport(MLCSwift)
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
                #else
                    self.status = "MLCSwift not integrated."
                #endif
            #else
                self.status = "MLC is disabled on Simulator."
            #endif
            self.isGenerating = false
        }
    }

    #if !targetEnvironment(simulator)
        #if canImport(MLCSwift)
            private func loadEngine(modelPath: String, modelLib: String) async throws {
                await engine.reload(modelPath: modelPath, modelLib: modelLib)
            }
        #endif
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
        case missingEmbeddedExtension(String)
        case missingModelDirectory(String)
        case missingModelFile(String)

        var errorDescription: String? {
            switch self {
            case let .missingBundledConfig(url):
                return "Missing bundled config: \(url.lastPathComponent). Did you add `iOS (App)/Config/mlc-app-config.json` to app resources?"
            case let .missingBundledModel(modelID):
                return "Model not found in `mlc-app-config.json`: \(modelID)"
            case let .missingEmbeddedExtension(bundleID):
                return "Embedded extension not found: \(bundleID). Is the Safari extension target embedded into the app?"
            case let .missingModelDirectory(dir):
                return "Missing model directory: \(dir)"
            case let .missingModelFile(path):
                return "Missing model file: \(path)"
            }
        }
    }

    private func resolveBundledModel() throws -> BundledModel {
        guard let configURL = resolveMLCAppConfigURL() else {
            let fallbackURL = Bundle.main.bundleURL.appending(path: "mlc-app-config.json")
            throw DemoError.missingBundledConfig(fallbackURL)
        }

        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)

        for modelID in modelIDCandidates {
            if let record = config.modelList.first(where: { $0.modelID == modelID && $0.modelPath != nil }) {
                let modelDirName = record.modelPath ?? modelID
                if let url = resolveModelDirFromWebLLMAssets(modelDirName: modelDirName) {
                    try validateModelDir(url)
                    return BundledModel(modelID: modelID, modelPath: url.path(), modelLib: record.modelLib)
                }

                let appBundledURL = Bundle.main.bundleURL
                    .appending(path: "bundle")
                    .appending(path: modelDirName)
                if FileManager.default.fileExists(atPath: appBundledURL.path()) {
                    try validateModelDir(appBundledURL)
                    return BundledModel(modelID: modelID, modelPath: appBundledURL.path(), modelLib: record.modelLib)
                }

                throw DemoError.missingModelDirectory(modelDirName)
            }
        }

        throw DemoError.missingBundledModel(modelIDCandidates.first ?? "(unknown)")
    }

    private func validateModelDir(_ url: URL) throws {
        let config = url.appending(path: "mlc-chat-config.json")
        guard FileManager.default.fileExists(atPath: config.path()) else {
            throw DemoError.missingModelFile(config.path())
        }

        let tokenizer = url.appending(path: "tokenizer.json")
        guard FileManager.default.fileExists(atPath: tokenizer.path()) else {
            throw DemoError.missingModelFile(tokenizer.path())
        }

        guard
            let items = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            ),
            items.contains(where: { $0.lastPathComponent.hasPrefix("params_shard_") && $0.pathExtension == "bin" })
        else {
            throw DemoError.missingModelFile(url.appending(path: "params_shard_*.bin").path())
        }
    }

    private func resolveMLCAppConfigURL() -> URL? {
        if let url = Bundle.main.url(forResource: "mlc-app-config", withExtension: "json") {
            return url
        }
        if let url = Bundle.main.url(forResource: "mlc-app-config", withExtension: "json", subdirectory: "Config") {
            return url
        }
        return nil
    }

    private func resolveModelDirFromWebLLMAssets(modelDirName: String) -> URL? {
        let embeddedBundleURL = resolveEmbeddedExtensionBundleURL()
        let embeddedResourceURL = embeddedBundleURL.flatMap { Bundle(url: $0)?.resourceURL }
        let mainBundleURL = Bundle.main.bundleURL
        let mainResourceURL = Bundle.main.resourceURL

        let modelDirCandidates = [
            URL(fileURLWithPath: "webllm-assets/models/\(modelDirName)/resolve/main", relativeTo: embeddedResourceURL),
            URL(fileURLWithPath: "webllm-assets/models/\(modelDirName)", relativeTo: embeddedResourceURL),
            URL(fileURLWithPath: "webllm-assets/models/\(modelDirName)/resolve/main", relativeTo: embeddedBundleURL),
            URL(fileURLWithPath: "webllm-assets/models/\(modelDirName)", relativeTo: embeddedBundleURL),
            URL(fileURLWithPath: "webllm-assets/models/\(modelDirName)/resolve/main", relativeTo: mainResourceURL),
            URL(fileURLWithPath: "webllm-assets/models/\(modelDirName)", relativeTo: mainResourceURL),
            URL(fileURLWithPath: "webllm-assets/models/\(modelDirName)/resolve/main", relativeTo: mainBundleURL),
            URL(fileURLWithPath: "webllm-assets/models/\(modelDirName)", relativeTo: mainBundleURL),
        ]

        for url in modelDirCandidates {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path(), isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }
        return nil
    }

    private func resolveEmbeddedExtensionBundleURL() -> URL? {
        guard let pluginsURL = Bundle.main.builtInPlugInsURL else { return nil }
        guard
            let pluginURLs = try? FileManager.default.contentsOfDirectory(
                at: pluginsURL,
                includingPropertiesForKeys: nil
            )
        else { return nil }

        let extensionBundle = pluginURLs
            .filter { $0.pathExtension == "appex" }
            .compactMap(Bundle.init(url:))
            .first(where: { $0.bundleIdentifier == embeddedExtensionBundleID })

        return extensionBundle?.bundleURL
    }
}

struct MLCQwenDemoView: View {
    @StateObject private var model = MLCQwenDemoViewModel()

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Input", text: $model.prompt, axis: .vertical)
                    .lineLimit(1 ... 6)
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

            #if targetEnvironment(simulator)
                VStack(alignment: .leading, spacing: 8) {
                    Text("MLC disabled on Simulator")
                        .font(.headline)
                    Text("MLC Swift cannot run in Simulator or SwiftUI Preview. Test on a real device.")
                        .foregroundStyle(.secondary)
                }
            #else
                #if !canImport(MLCSwift)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Missing dependency: MLCSwift")
                            .font(.headline)
                        Text("Follow https://llm.mlc.ai/docs/deploy/ios.html → “Build Apps with MLC Swift API” to add the local package `ios/MLCSwift`, bundle `dist/bundle`, and link the required libraries.")
                            .foregroundStyle(.secondary)
                    }
                #endif
            #endif
        }
        .padding()
        .navigationTitle("Qwen3 0.6B Demo")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.onAppear() }
    }
}
