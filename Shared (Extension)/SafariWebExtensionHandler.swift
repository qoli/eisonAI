//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Native messaging is intentionally disabled.
//  LLM inference runs in the extension popup via WebLLM (bundled assets).
//

import Foundation
import SafariServices
import os.log

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let message: Any?
        if #available(iOS 17.0, macOS 14.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        os_log(.default, "[Eison-Native] Received native message (ignored): %@", String(describing: message))

        let responseMessage: [String: Any] = [
            "v": 1,
            "type": "event",
            "name": "error",
            "payload": [
                "code": "NATIVE_MESSAGING_DISABLED",
                "message": "Native messaging is disabled. Use the WebLLM popup (bundled assets) for inference.",
            ],
        ]

        let response = NSExtensionItem()
        if #available(iOS 17.0, macOS 14.0, *) {
            response.userInfo = [SFExtensionMessageKey: responseMessage]
        } else {
            response.userInfo = ["message": responseMessage]
        }

        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
