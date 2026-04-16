import UIKit
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

    @MainActor
    func callAsyncJavaScriptAsync(
        _ functionBody: String,
        arguments: [String: Any] = [:],
        in frame: WKFrameInfo? = nil,
        contentWorld: WKContentWorld = .page
    ) async throws -> Any {
        let result = try await callAsyncJavaScript(
            functionBody,
            arguments: arguments,
            in: frame,
            contentWorld: contentWorld
        )
        return result as Any
    }

    @MainActor
    func takeSnapshotAsync(configuration: WKSnapshotConfiguration? = nil) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            takeSnapshot(with: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let image else {
                    continuation.resume(throwing: SnapshotError.imageUnavailable)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }
}

private enum SnapshotError: LocalizedError {
    case imageUnavailable

    var errorDescription: String? {
        "Failed to capture web snapshot."
    }
}
