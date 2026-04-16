import Foundation
import WebKit

@MainActor
final class BrowserPageBridge {
    enum BridgeError: LocalizedError {
        case missingScript(String)
        case invalidResponse
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .missingScript(let name):
                return "Missing bundled browser script: \(name)"
            case .invalidResponse:
                return "Browser runtime returned an invalid response."
            case .invalidURL:
                return "The browser agent requested an invalid URL."
            }
        }
    }

    private let pageControllerSource = BundledTextResource.loadUTF8(name: "page-controller.iife", ext: "js")
    private let bridgeSource = BundledTextResource.loadUTF8(name: "browserAgentBridge", ext: "js")
    private let decoder = JSONDecoder()

    func configure(userContentController: WKUserContentController) {
        guard let pageControllerSource else { return }
        guard let bridgeSource else { return }

        userContentController.addUserScript(
            WKUserScript(
                source: pageControllerSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        userContentController.addUserScript(
            WKUserScript(
                source: bridgeSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
    }

    func observe(in webView: WKWebView) async throws -> BrowserPageObservation {
        try ensureScriptsAvailable()
        let json = try await callBridge(command: "observe", payload: [:], in: webView)
        return try decode(BrowserPageObservation.self, from: json)
    }

    func perform(_ action: BrowserAgentAction, in webView: WKWebView) async throws -> BrowserBridgeActionResult {
        switch action.type {
        case .navigate:
            guard let rawURL = action.url?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = normalizedURL(from: rawURL)
            else {
                throw BridgeError.invalidURL
            }
            webView.load(URLRequest(url: url))
            return BrowserBridgeActionResult(success: true, message: "Started navigation to \(url.absoluteString).")
        case .click:
            var payload: [String: Any] = [:]
            if let index = action.index {
                payload["index"] = index
            }
            let json = try await callBridge(command: "click", payload: payload, in: webView)
            return try decode(BrowserBridgeActionResult.self, from: json)
        case .input:
            var payload: [String: Any] = ["text": action.text ?? ""]
            if let index = action.index {
                payload["index"] = index
            }
            let json = try await callBridge(command: "input", payload: payload, in: webView)
            return try decode(BrowserBridgeActionResult.self, from: json)
        case .select:
            var payload: [String: Any] = ["option": action.option ?? ""]
            if let index = action.index {
                payload["index"] = index
            }
            let json = try await callBridge(command: "select", payload: payload, in: webView)
            return try decode(BrowserBridgeActionResult.self, from: json)
        case .scroll:
            let direction = action.direction?.lowercased() == "up" ? "up" : "down"
            var payload: [String: Any] = [
                "direction": direction,
                "pages": max(1, action.pages ?? 1)
            ]
            if let index = action.index {
                payload["index"] = index
            }
            let json = try await callBridge(command: "scroll", payload: payload, in: webView)
            return try decode(BrowserBridgeActionResult.self, from: json)
        case .wait:
            let payload: [String: Any] = [
                "milliseconds": max(250, action.milliseconds ?? 800)
            ]
            let json = try await callBridge(command: "wait", payload: payload, in: webView)
            return try decode(BrowserBridgeActionResult.self, from: json)
        case .pressEnter:
            var payload: [String: Any] = [:]
            if let index = action.index {
                payload["index"] = index
            }
            let json = try await callBridge(command: "pressEnter", payload: payload, in: webView)
            return try decode(BrowserBridgeActionResult.self, from: json)
        }
    }

    private func ensureScriptsAvailable() throws {
        if pageControllerSource == nil {
            throw BridgeError.missingScript("page-controller.iife.js")
        }
        if bridgeSource == nil {
            throw BridgeError.missingScript("browserAgentBridge.js")
        }
    }

    private func callBridge(command: String, payload: [String: Any], in webView: WKWebView) async throws -> String {
        let result = try await webView.callAsyncJavaScriptAsync(
            """
            const runtime = window.__eisonBrowserAgentBridge;
            if (!runtime) {
                throw new Error("Browser agent bridge is unavailable.");
            }
            const response = await runtime.call(command, payload);
            return JSON.stringify(response);
            """,
            arguments: [
                "command": command,
                "payload": payload
            ]
        )
        guard let json = result as? String else {
            throw BridgeError.invalidResponse
        }
        return json
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw BridgeError.invalidResponse
        }
        return try decoder.decode(type, from: data)
    }

    private func normalizedURL(from rawValue: String) -> URL? {
        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(rawValue)")
    }
}
