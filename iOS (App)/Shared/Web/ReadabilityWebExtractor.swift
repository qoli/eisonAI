import Foundation
import WebKit

@MainActor
final class ReadabilityWebExtractor: NSObject {
    struct Article {
        let url: String
        let title: String
        let text: String
    }

    enum ExtractError: LocalizedError {
        case invalidURL
        case loadFailed(String)
        case jsFailed(String)
        case timeout
        case missingReadabilityScript

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL."
            case .loadFailed(let msg):
                return "Failed to load page: \(msg)"
            case .jsFailed(let msg):
                return "Failed to extract article: \(msg)"
            case .timeout:
                return "Timed out while loading/extracting."
            case .missingReadabilityScript:
                return "Missing Readability script: contentReadability.js"
            }
        }
    }

    private let webView: WKWebView
    private var continuation: CheckedContinuation<Article, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var currentURLString: String = ""

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    func extract(from url: URL, timeoutSeconds: Double = 20) async throws -> Article {
        if continuation != nil {
            throw ExtractError.loadFailed("Extractor is busy.")
        }

        currentURLString = url.absoluteString
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                guard let self else { return }
                if self.continuation != nil {
                    self.finish(with: .failure(ExtractError.timeout))
                }
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = timeoutSeconds
            webView.load(request)
        }
    }

    private func finish(with result: Result<Article, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil

        let cont = continuation
        continuation = nil

        switch result {
        case .success(let article):
            cont?.resume(returning: article)
        case .failure(let error):
            cont?.resume(throwing: error)
        }
    }
}

extension ReadabilityWebExtractor: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(ExtractError.loadFailed(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(ExtractError.loadFailed(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard let readabilitySource = BundledTextResource.loadUTF8(name: "contentReadability", ext: "js") else {
                finish(with: .failure(ExtractError.missingReadabilityScript))
                return
            }

            do {
                _ = try await webView.evaluateJavaScriptAsync(readabilitySource)

                let extractionScript = """
                (() => {
                  try {
                    const article = new Readability(document).parse();
                    const title = (article && article.title) ? String(article.title) : String(document.title || "");
                    const text = (article && article.textContent) ? String(article.textContent) : "";
                    return { title, text };
                  } catch (e) {
                    return { title: String(document.title || ""), text: "", error: String(e && e.message ? e.message : e) };
                  }
                })()
                """

                let value = try await webView.evaluateJavaScriptAsync(extractionScript)
                guard let dict = value as? [String: Any] else {
                    finish(with: .failure(ExtractError.jsFailed("Unexpected JS return value.")))
                    return
                }

                let title = String(dict["title"] as? String ?? "")
                let text = String(dict["text"] as? String ?? "")
                if let err = dict["error"] as? String, !err.isEmpty {
                    finish(with: .failure(ExtractError.jsFailed(err)))
                    return
                }

                finish(with: .success(Article(url: currentURLString, title: title, text: text)))
            } catch {
                finish(with: .failure(ExtractError.jsFailed(error.localizedDescription)))
            }
        }
    }
}
