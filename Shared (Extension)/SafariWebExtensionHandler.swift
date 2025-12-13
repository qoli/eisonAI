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

    guard name == "summarize.start" else {
        return makeError(requestId: requestId, code: "INVALID_INPUT", message: "Unsupported request: \(name ?? "unknown")")
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
