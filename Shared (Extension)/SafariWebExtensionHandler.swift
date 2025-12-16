//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Native messaging is used only for lightweight configuration (e.g. system prompt).
//  LLM inference runs in the extension popup via WebLLM (bundled assets).
//

import Foundation
import SafariServices
import os.log

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let appGroupIdentifier = "group.com.qoli.eisonAI"
    private let systemPromptKey = "eison.systemPrompt"
    private let defaultSystemPrompt = """
你是一個資料整理員。

Summarize this post in 3-4 sentences.
Emphasize the key insights and main takeaways.

以繁體中文輸出。
"""

    private func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private func loadSystemPrompt() -> String {
        guard let stored = sharedDefaults()?.string(forKey: systemPromptKey) else {
            return defaultSystemPrompt
        }
        if stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return defaultSystemPrompt
        }
        return stored
    }

    private func saveSystemPrompt(_ value: String?) {
        guard let defaults = sharedDefaults() else { return }
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: systemPromptKey)
        } else {
            defaults.set(trimmed, forKey: systemPromptKey)
        }
    }

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let profile: UUID?
        if #available(iOS 17.0, macOS 14.0, *) {
            profile = request?.userInfo?[SFExtensionProfileKey] as? UUID
        } else {
            profile = request?.userInfo?["profile"] as? UUID
        }

        let message: Any?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        os_log(.default, "[Eison-Native] Received native message: %@ (profile: %@)", String(describing: message), profile?.uuidString ?? "none")

        let responseMessage: [String: Any]
        if let dict = message as? [String: Any] {
            let command = (dict["command"] as? String) ?? (dict["name"] as? String) ?? ""
            switch command {
            case "getSystemPrompt":
                responseMessage = [
                    "v": 1,
                    "type": "response",
                    "name": "systemPrompt",
                    "payload": [
                        "prompt": loadSystemPrompt(),
                    ],
                ]
            case "setSystemPrompt":
                let prompt = dict["prompt"] as? String
                saveSystemPrompt(prompt)
                responseMessage = [
                    "v": 1,
                    "type": "response",
                    "name": "systemPrompt",
                    "payload": [
                        "prompt": loadSystemPrompt(),
                    ],
                ]
            case "resetSystemPrompt":
                saveSystemPrompt(nil)
                responseMessage = [
                    "v": 1,
                    "type": "response",
                    "name": "systemPrompt",
                    "payload": [
                        "prompt": loadSystemPrompt(),
                    ],
                ]
            default:
                responseMessage = [
                    "v": 1,
                    "type": "error",
                    "name": "error",
                    "payload": [
                        "code": "UNKNOWN_COMMAND",
                        "message": "Unsupported native command: \(command)",
                    ],
                ]
            }
        } else {
            responseMessage = [
                "v": 1,
                "type": "error",
                "name": "error",
                "payload": [
                    "code": "INVALID_MESSAGE",
                    "message": "Expected an object message payload.",
                ],
            ]
        }

        let response = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            response.userInfo = [SFExtensionMessageKey: responseMessage]
        } else {
            response.userInfo = ["message": responseMessage]
        }

        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
