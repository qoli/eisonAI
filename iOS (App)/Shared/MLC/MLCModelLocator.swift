import Foundation

struct MLCAppConfig: Decodable {
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

struct MLCModelSelection {
    let modelID: String
    let modelPath: String
    let modelLib: String
}

enum MLCModelLocatorError: LocalizedError {
    case missingConfig
    case missingBundledModel(String)
    case missingModelDirectory(String)
    case missingModelFile(String)

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            return "Missing `mlc-app-config.json` in app bundle."
        case .missingBundledModel(let modelID):
            return "Model not found in `mlc-app-config.json`: \(modelID)"
        case .missingModelDirectory(let dir):
            return "Missing model directory: \(dir). Run `python3 Scripts/download_webllm_assets.py` and rebuild the app to bundle WebLLM assets."
        case .missingModelFile(let path):
            return "Missing model file: \(path). Run `python3 Scripts/download_webllm_assets.py` and rebuild the app to bundle WebLLM assets."
        }
    }
}

struct MLCModelLocator {
    var modelIDCandidates: [String] = [
        "Qwen3-0.6B-q4f16_1-MLC",
        "Qwen3-0.6B-q0f16-MLC",
    ]

    var embeddedExtensionBundleID: String = "com.qoli.eisonAI.Extension"

    func resolveSelection() throws -> MLCModelSelection {
        guard let configURL = resolveMLCAppConfigURL() else {
            throw MLCModelLocatorError.missingConfig
        }

        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(MLCAppConfig.self, from: data)

        for modelID in modelIDCandidates {
            guard let record = config.modelList.first(where: { $0.modelID == modelID }) else { continue }

            let modelDirName = record.modelPath ?? modelID
            if let url = resolveModelDirFromWebLLMAssets(modelDirName: modelDirName) {
                try validateModelDir(url)
                return MLCModelSelection(modelID: modelID, modelPath: url.path(), modelLib: record.modelLib)
            }

            throw MLCModelLocatorError.missingModelDirectory(modelDirName)
        }

        throw MLCModelLocatorError.missingBundledModel(modelIDCandidates.first ?? "(unknown)")
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

    private func validateModelDir(_ url: URL) throws {
        let config = url.appending(path: "mlc-chat-config.json")
        guard FileManager.default.fileExists(atPath: config.path()) else {
            throw MLCModelLocatorError.missingModelFile(config.path())
        }

        let tokenizer = url.appending(path: "tokenizer.json")
        guard FileManager.default.fileExists(atPath: tokenizer.path()) else {
            throw MLCModelLocatorError.missingModelFile(tokenizer.path())
        }

        guard
            let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
            items.contains(where: { $0.lastPathComponent.hasPrefix("params_shard_") && $0.pathExtension == "bin" })
        else {
            throw MLCModelLocatorError.missingModelFile(url.appending(path: "params_shard_*.bin").path())
        }
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

        let candidatePaths = modelDirCandidates.map { $0.path() }
        print("[MLCModelLocator] embeddedExtensionBundleURL=", embeddedBundleURL?.path() ?? "nil")
        print("[MLCModelLocator] embeddedExtensionResourceURL=", embeddedResourceURL?.path() ?? "nil")
        print("[MLCModelLocator] mainBundleURL=", mainBundleURL.path())
        print("[MLCModelLocator] mainBundleResourceURL=", mainResourceURL?.path() ?? "nil")
        print("[MLCModelLocator] modelDirCandidates=", candidatePaths)

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
