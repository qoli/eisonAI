import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private var didHandle = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didHandle else { return }
        didHandle = true
        Task { await handleShare() }
    }

    private func handleShare() async {
        guard let context = extensionContext else {
            completeRequest()
            return
        }

        let items = context.inputItems.compactMap { $0 as? NSExtensionItem }

        var urlString: String?
        var text: String?
        var title: String?

        for item in items {
            if let itemTitle = item.attributedTitle?.string.trimmingCharacters(in: .whitespacesAndNewlines),
               !itemTitle.isEmpty,
               title == nil {
                title = itemTitle
            }

            let providers = item.attachments ?? []
            for provider in providers {
                if urlString == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await loadURLString(from: provider) {
                        urlString = url
                    }
                }

                if text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let loadedText = try? await loadTextString(from: provider) {
                        text = loadedText
                    }
                }

                if urlString != nil, text != nil { break }
            }
        }

        let trimmedURL = urlString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard (trimmedURL?.isEmpty == false) || (trimmedText?.isEmpty == false) else {
            completeRequest()
            return
        }

        let payload = SharePayload(
            id: UUID().uuidString,
            createdAt: Date(),
            url: trimmedURL,
            text: trimmedText,
            title: trimmedTitle
        )

        do {
            try SharePayloadStore().save(payload)
        } catch {
            completeRequest()
            return
        }

        await openHostApp(with: payload.id)
        completeRequest()
    }

    private func openHostApp(with id: String) async {
        var components = URLComponents()
        components.scheme = "eisonai"
        components.host = "share"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        guard let url = components.url else { return }

        await withCheckedContinuation { continuation in
            extensionContext?.open(url, completionHandler: { _ in
                continuation.resume()
            })
        }
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func loadURLString(from provider: NSItemProvider) async throws -> String? {
        guard let item = try await loadItem(for: UTType.url, from: provider) else { return nil }
        if let url = item as? URL {
            return url.absoluteString
        }
        if let string = item as? String {
            return string
        }
        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url.absoluteString
        }
        return nil
    }

    private func loadTextString(from provider: NSItemProvider) async throws -> String? {
        guard let item = try await loadItem(for: UTType.plainText, from: provider) else { return nil }
        if let string = item as? String {
            return string
        }
        if let attributed = item as? NSAttributedString {
            return attributed.string
        }
        if let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func loadItem(for type: UTType, from provider: NSItemProvider) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: item)
            }
        }
    }
}
