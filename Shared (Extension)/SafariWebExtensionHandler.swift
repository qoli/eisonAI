//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import os.log
import SafariServices
import EisonAIKit

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

        let sendableContext = UnsafeSendable(context)
        Task { [message] in
            let responseMessage = await handleMessage(message)

            await MainActor.run {
                let response = NSExtensionItem()
                response.userInfo = [SFExtensionMessageKey: responseMessage]
                sendableContext.value.completeRequest(returningItems: [response], completionHandler: nil)
            }
        }
    }
}

private struct UnsafeSendable<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

private func handleMessage(_ message: Any?) async -> [String: Any] {
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
            "payload": modelStatusPayload(),
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

    do {
        let summary = try await NativeSummarizer.shared.summarize(title: title, text: text)
        return [
            "v": dict["v"] as? Int ?? 1,
            "id": requestId ?? "",
            "type": "response",
            "name": "summarize.done",
            "payload": [
                "requestId": requestId ?? "",
                "result": [
                    "titleText": title.isEmpty ? "Summary" : title,
                    "summaryText": summary,
                ],
            ],
        ]
    } catch {
        return makeError(requestId: requestId, code: "INFERENCE_FAILED", message: error.localizedDescription)
    }
}

private actor NativeSummarizer {
    static let shared = NativeSummarizer()
    private var modelContainer: ModelContainer?

    func summarize(title: String, text: String) async throws -> String {
        let maxInputCharacters = 16_000
        let normalizedText = normalizeInputText(text, limit: maxInputCharacters)

        let systemText = """
        你是一個網頁文章摘要助手。請用繁體中文輸出，並嚴格遵守格式：

        總結：<一行>
        要點：
        - <每行一個要點，開頭請用 emoji>

        除了以上格式，不要輸出任何多餘文字。
        """

        let userPrompt = """
        請摘要以下文章：

        【標題】
        \(title)

        【正文】
        \(normalizedText)
        """

        let container = try await getModelContainer()
        let generateParameters = GenerateParameters(maxTokens: 512, temperature: 0.4)

        let chat: [Chat.Message] = [
            .system(systemText),
            .user(userPrompt),
        ]

        let userInput = UserInput(chat: chat)

        let output = try await container.perform { context in
            let input = try await context.processor.prepare(input: userInput)
            let cache = context.model.newCache(parameters: generateParameters)

            var fullText = ""
            for await item in try MLXLMCommon.generate(
                input: input,
                cache: cache,
                parameters: generateParameters,
                context: context
            ) {
                if let chunk = item.chunk {
                    fullText += chunk
                }
            }
            return fullText
        }

        return normalizeSummaryOutput(output)
    }

    private func getModelContainer() async throws -> ModelContainer {
        if let modelContainer {
            return modelContainer
        }

        let repoId = "lmstudio-community/Qwen3-0.6B-MLX-4bit"
        let revision = "75429955681c1850a9c8723767fe4252da06eb57"
        let appGroupID = "group.com.qoli.eisonAI"

        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            throw NSError(domain: "EisonAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group 容器不可用"])
        }

        let modelDir = container
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(repoId, isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)

        let configuration = ModelConfiguration(directory: modelDir)
        let loaded = try await LLMModelFactory.shared.loadContainer(configuration: configuration)
        modelContainer = loaded
        return loaded
    }
}

private func normalizeInputText(_ text: String, limit: Int) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > limit else { return trimmed }
    let prefix = String(trimmed.prefix(limit))
    return prefix + "\n\n（內容過長，已截斷）"
}

private func normalizeSummaryOutput(_ raw: String) -> String {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    if text.hasPrefix("```") {
        text = text.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    if !text.contains("總結：") {
        text = "總結：\n\n要點：\n- 🧾 \(text)"
    }
    if !text.contains("要點：") {
        text += "\n\n要點：\n- 🧾（模型未輸出要點）"
    }
    return text
}

private func modelStatusPayload() -> [String: Any] {
    let repoId = "lmstudio-community/Qwen3-0.6B-MLX-4bit"
    let revision = "75429955681c1850a9c8723767fe4252da06eb57"

    if let persisted = loadPersistedModelStatus(appGroupID: "group.com.qoli.eisonAI"),
       persisted.repoId == repoId,
       persisted.revision == revision {
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
            "message": message,
        ],
    ]
}
