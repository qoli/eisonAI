import Darwin
import Foundation
import os

private enum MLCLog {
    private static let logger = Logger(subsystem: "com.qoli.eisonAI", category: "MLC")
    private static let groupID = "group.com.qoli.eisonAI"
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static var logFileURL: URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            return nil
        }
        return containerURL
            .appending(path: "Library")
            .appending(path: "Caches")
            .appending(path: "mlc_locator.log")
    }

    static func write(_ message: String) {
        logger.info("\(message, privacy: .public)")
        guard let url = logFileURL else { return }
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        let dirURL = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: fileSystemPath(url)) {
            if let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}

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
    case missingModelLib(String)

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            return "Missing `mlc-app-config.json` in app bundle."
        case let .missingBundledModel(modelID):
            return "Model not found in `mlc-app-config.json`: \(modelID)"
        case let .missingModelDirectory(dir):
            return "Missing model directory: \(dir). Run `python3 Scripts/download_webllm_assets.py` and rebuild the app to bundle WebLLM assets."
        case let .missingModelFile(path):
            return "Missing model file: \(path). Run `python3 Scripts/download_webllm_assets.py` and rebuild the app to bundle WebLLM assets."
        case let .missingModelLib(name):
            return "Missing model lib: \(name). Rebuild MLC xcframeworks and ensure libmodel_iphone.xcframework is linked into the app."
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
            MLCLog.write("MLC config missing in app bundle.")
            throw MLCModelLocatorError.missingConfig
        }
        MLCLog.write("MLC config url: \(fileSystemPath(configURL))")

        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(MLCAppConfig.self, from: data)

        for modelID in modelIDCandidates {
            guard let record = config.modelList.first(where: { $0.modelID == modelID }) else { continue }

            let modelDirName = record.modelPath ?? modelID
            if let url = resolveModelDirFromWebLLMAssets(modelDirName: modelDirName) {
                try validateModelDir(url)
                try validateModelLib(record.modelLib)
                return MLCModelSelection(modelID: modelID, modelPath: fileSystemPath(url), modelLib: record.modelLib)
            }

            MLCLog.write("MLC model directory not found: \(modelDirName)")
            throw MLCModelLocatorError.missingModelDirectory(modelDirName)
        }

        MLCLog.write("MLC model not found in config. candidates=\(modelIDCandidates.joined(separator: ","))")
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
        let configPath = fileSystemPath(config)
        guard FileManager.default.fileExists(atPath: configPath) else {
            MLCLog.write("MLC missing model file: \(configPath)")
            throw MLCModelLocatorError.missingModelFile(configPath)
        }

        let tokenizer = url.appending(path: "tokenizer.json")
        let tokenizerPath = fileSystemPath(tokenizer)
        guard FileManager.default.fileExists(atPath: tokenizerPath) else {
            MLCLog.write("MLC missing model file: \(tokenizerPath)")
            throw MLCModelLocatorError.missingModelFile(tokenizerPath)
        }

        guard
            let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
            items.contains(where: { $0.lastPathComponent.hasPrefix("params_shard_") && $0.pathExtension == "bin" })
        else {
            let modelPath = fileSystemPath(url)
            MLCLog.write("MLC missing model shard files under: \(modelPath)")
            throw MLCModelLocatorError.missingModelFile(
                fileSystemPath(url.appending(path: "params_shard_*.bin"))
            )
        }
    }

    private func resolveModelDirFromWebLLMAssets(modelDirName: String) -> URL? {
        let embeddedBundleURL = resolveEmbeddedExtensionBundleURL()
        let embeddedResourceURL = embeddedBundleURL.flatMap { Bundle(url: $0)?.resourceURL }
        let mainBundleURL = Bundle.main.bundleURL
        let mainResourceURL = Bundle.main.resourceURL

        let embeddedBundlePath = embeddedBundleURL.map(fileSystemPath) ?? "nil"
        let embeddedResourcePath = embeddedResourceURL.map(fileSystemPath) ?? "nil"
        let mainBundlePath = fileSystemPath(mainBundleURL)
        let mainResourcePath = mainResourceURL.map(fileSystemPath) ?? "nil"
        MLCLog.write(
            "MLC resolve model dir=\(modelDirName) embeddedBundleURL=\(embeddedBundlePath) " +
                "embeddedResourceURL=\(embeddedResourcePath) " +
                "mainBundleURL=\(mainBundlePath) mainResourceURL=\(mainResourcePath)"
        )

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
            let rawPath = url.path()
            let fsPath = fileSystemPath(url)
            let exists = FileManager.default.fileExists(atPath: fsPath, isDirectory: &isDir)
            MLCLog.write(
                "MLC candidate path: raw=\(rawPath) fs=\(fsPath) exists=\(exists) isDir=\(isDir.boolValue)"
            )
            if exists, isDir.boolValue {
                return url
            }
        }
        return nil
    }

    private func fileSystemPath(_ url: URL) -> String {
        url.path(percentEncoded: false)
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

        if extensionBundle == nil {
            MLCLog.write("MLC embedded extension not found. bundleID=\(embeddedExtensionBundleID)")
        }
        return extensionBundle?.bundleURL
    }

    private func validateModelLib(_ modelLib: String) throws {
        #if targetEnvironment(simulator)
            _ = modelLib
        #else
            let symbolName = "\(modelLib)___tvm_ffi__library_bin"
            MLCLog.write("MLC validate model lib: \(symbolName)")
            guard let handle = dlopen(nil, RTLD_NOW) else {
                throw MLCModelLocatorError.missingModelLib(modelLib)
            }
            let found = symbolName.withCString { cstr in
                dlsym(handle, cstr) != nil
            }
            guard found else {
                MLCLog.write("MLC model lib missing in process: \(symbolName)")
                throw MLCModelLocatorError.missingModelLib(modelLib)
            }
        #endif
    }
}
