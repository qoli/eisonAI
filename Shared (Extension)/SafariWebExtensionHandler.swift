//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import SafariServices
import os.log

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let profile: UUID?
        if #available(iOS 17.0, macOS 14.0, *) {
            profile = request?.userInfo?[SFExtensionProfileKey] as? UUID
        } else {
            profile = request?.userInfo?["profile"] as? UUID
        }

        let message: Any?
        if #available(iOS 17.0, macOS 14.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        os_log(.default, "Received message from browser.runtime.sendNativeMessage: %@ (profile: %@)", String(describing: message), profile?.uuidString ?? "none")

        let response = NSExtensionItem()

        let responseMessage = handleMessage(message)
        response.userInfo = [ SFExtensionMessageKey: responseMessage ]

        context.completeRequest(returningItems: [ response ], completionHandler: nil)
    }

}

private func handleMessage(_ message: Any?) -> [String: Any] {
    guard let dict = message as? [String: Any] else {
        return makeError(requestId: nil, code: "INVALID_INPUT", message: "Message must be an object")
    }

    let requestId = dict["id"] as? String
    let name = dict["name"] as? String

    if name == "model.getStatus" {
        return [
            "v": dict["v"] as? Int ?? 1,
            "id": requestId ?? "",
            "type": "response",
            "name": "model.status",
            "payload": modelStatusPayload()
        ]
    }

    guard name == "summarize.start" else {
        return makeError(requestId: requestId, code: "INVALID_INPUT", message: "Unsupported request: \(name ?? "unknown")")
    }

    let modelStatus = modelStatusPayload()
    let modelState = modelStatus["state"] as? String ?? "notInstalled"
    if modelState != "ready" {
        return makeError(
            requestId: requestId,
            code: "MODEL_NOT_READY",
            message: "模型尚未下載，請打開 App 完成模型下載。"
        )
    }

    let payload = dict["payload"] as? [String: Any]
    let title = payload?["title"] as? String ?? ""
    let text = payload?["text"] as? String ?? ""

    // M1: echo mode — return the Readability-extracted text as-is.
    return [
        "v": dict["v"] as? Int ?? 1,
        "id": requestId ?? "",
        "type": "response",
        "name": "summarize.done",
        "payload": [
            "requestId": requestId ?? "",
            "result": [
                "titleText": title.isEmpty ? "正文" : title,
                "summaryText": text
            ]
        ]
    ]
}

private func modelStatusPayload() -> [String: Any] {
    let repoId = "lmstudio-community/Qwen3-0.6B-MLX-4bit"
    let revision = "75429955681c1850a9c8723767fe4252da06eb57"

    if let persisted = loadPersistedModelStatus(appGroupID: "group.com.qoli.eisonAI"),
       persisted.repoId == repoId,
       persisted.revision == revision
    {
        if persisted.state == "ready", isModelReady(appGroupID: "group.com.qoli.eisonAI", repoId: repoId, revision: revision) {
            return pruneNilValues([
                "state": "ready",
                "progress": 1.0,
                "error": nil,
                "repoId": repoId,
                "revision": revision,
            ])
        }

        if persisted.state == "downloading" || persisted.state == "verifying" || persisted.state == "failed" {
            return pruneNilValues([
                "state": persisted.state,
                "progress": persisted.progress,
                "error": persisted.error,
                "repoId": repoId,
                "revision": revision,
            ])
        }
    }

    if isModelReady(appGroupID: "group.com.qoli.eisonAI", repoId: repoId, revision: revision) {
        return pruneNilValues([
            "state": "ready",
            "progress": 1.0,
            "error": nil,
            "repoId": repoId,
            "revision": revision,
        ])
    }

    return pruneNilValues([
        "state": "notInstalled",
        "progress": 0.0,
        "error": nil,
        "repoId": repoId,
        "revision": revision,
    ])
}

private func pruneNilValues(_ dict: [String: Any?]) -> [String: Any] {
    var pruned: [String: Any] = [:]
    for (key, value) in dict {
        guard let value else { continue }
        pruned[key] = value
    }
    return pruned
}

private struct PersistedModelStatus: Decodable {
    let state: String
    let progress: Double
    let error: String?
    let repoId: String
    let revision: String
}

private func loadPersistedModelStatus(appGroupID: String) -> PersistedModelStatus? {
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
        return nil
    }
    let url = container.appendingPathComponent("Config/modelStatus.json")
    guard let data = try? Data(contentsOf: url) else {
        return nil
    }
    return try? JSONDecoder().decode(PersistedModelStatus.self, from: data)
}

private func isModelReady(appGroupID: String, repoId: String, revision: String) -> Bool {
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
        return false
    }

    let modelDir = container
        .appendingPathComponent("Models", isDirectory: true)
        .appendingPathComponent(repoId, isDirectory: true)
        .appendingPathComponent(revision, isDirectory: true)

    let requiredFiles: [String] = [
        "added_tokens.json",
        "config.json",
        "merges.txt",
        "model.safetensors",
        "model.safetensors.index.json",
        "special_tokens_map.json",
        "tokenizer.json",
        "tokenizer_config.json",
        "vocab.json",
    ]

    for file in requiredFiles {
        let url = modelDir.appendingPathComponent(file)
        if !FileManager.default.fileExists(atPath: url.path) {
            return false
        }
    }

    return true
}

private func makeError(requestId: String?, code: String, message: String) -> [String: Any] {
    return [
        "v": 1,
        "id": requestId ?? "",
        "type": "event",
        "name": "error",
        "payload": [
            "requestId": requestId ?? "",
            "code": code,
            "message": message
        ]
    ]
}
