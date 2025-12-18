import WebKit

extension WKWebView {
    func evaluateJavaScriptAsync(_ javaScriptString: String) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(javaScriptString) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: result as Any)
            }
        }
    }
}

