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

    func createPDFAsync(configuration: WKPDFConfiguration) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            createPDF(configuration: configuration) { result in
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func waitForDocumentReady(timeoutSeconds: Double = 5, pollIntervalNanoseconds: UInt64 = 50_000_000) async throws {
        let timeoutDate = Date().addingTimeInterval(timeoutSeconds)
        let readinessScript = """
        (() => {
          const ready = document.readyState === 'complete';
          const fontsReady = !document.fonts || document.fonts.status === 'loaded';
          return ready && fontsReady;
        })()
        """

        while Date() < timeoutDate {
            try Task.checkCancellation()

            let result = try await evaluateJavaScriptAsync(readinessScript)
            if let isReady = result as? Bool, isReady {
                return
            }

            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        throw CocoaError(.coderReadCorrupt)
    }
}
