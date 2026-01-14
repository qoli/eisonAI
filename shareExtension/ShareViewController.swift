import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private var didHandle = false
    private var didScheduleCompletion = false
    private let viewModel = ShareStatusViewModel()
    private var hostingController: UIHostingController<ShareStatusView>?
    private let minimizeDuration: TimeInterval = 0.6
    private let bounceDuration: TimeInterval = 0.7
    private let appGroupIdentifier = "group.com.qoli.eisonAI"
    private let shareOpenAppAfterShareKey = "eison.share.openAppAfterShare"

    override func viewDidLoad() {
        super.viewDidLoad()
        let rootView = ShareStatusView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        self.hostingController = hostingController

        addChild(hostingController)
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)

        setStatus("Processing…", detail: "Please wait")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didHandle else { return }
        didHandle = true
        log("viewDidAppear, starting handleShare")
        Task { await handleShare() }
    }

    private func handleShare() async {
        guard let context = extensionContext else {
            log("extensionContext is nil")
            await MainActor.run {
                setStatus("Share failed", detail: "Missing extension context.")
                scheduleCompletion()
            }
            return
        }

        let items = context.inputItems.compactMap { $0 as? NSExtensionItem }
        log("inputItems count: \(items.count)")

        var urlString: String?
        var text: String?
        var title: String?

        for item in items {
            if let itemTitle = item.attributedTitle?.string.trimmingCharacters(in: .whitespacesAndNewlines),
               !itemTitle.isEmpty,
               title == nil {
                title = itemTitle
                log("picked title: \(itemTitle.prefix(120))")
            }

            if text == nil,
               let contentText = item.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines),
               !contentText.isEmpty {
                text = contentText
                log("picked attributedContentText length: \(contentText.count)")
            }

            let providers = item.attachments ?? []
            log("attachments count: \(providers.count)")
            for provider in providers {
                if urlString == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await loadURLString(from: provider) {
                        urlString = url
                        log("loaded url: \(url)")
                    }
                }

                if text == nil,
                   provider.canLoadObject(ofClass: NSString.self)
                    || provider.canLoadObject(ofClass: NSAttributedString.self)
                    || provider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.rtf.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.html.identifier) {
                    if let loadedText = try? await loadTextString(from: provider) {
                        text = loadedText
                        log("loaded text length: \(loadedText.count)")
                    }
                }

                if urlString != nil, text != nil { break }
            }
        }

        let trimmedURL = urlString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard (trimmedURL?.isEmpty == false) || (trimmedText?.isEmpty == false) else {
            log("no usable URL/text, completing request")
            await MainActor.run {
                setStatus("No shareable content", detail: "Please share a URL or text.")
                scheduleCompletion()
            }
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
            let outcome = try SharePayloadStore().saveIfNotDuplicate(payload)
            let shouldOpenApp = shouldOpenAppAfterShare()
            let deepLinkURL = shareDeepLinkURL(for: payload.id)
            let fallbackURL = URL(string: "eisonai://")
            await MainActor.run {
                var openURL: URL?
                switch outcome {
                case .saved(let fileURL):
                    log("saved payload: \(fileURL.lastPathComponent)")
                    setStatus("Saved", detail: "Closing…")
                    if shouldOpenApp {
                        openURL = deepLinkURL ?? fallbackURL
                    }
                case .duplicate:
                    log("duplicate url, skipping save")
                    setStatus("Already saved", detail: "Closing…")
                    if shouldOpenApp {
                        openURL = fallbackURL
                    }
                }
                if let openURL {
                    openHostApp(url: openURL)
                }
                playMinimizeAndComplete()
            }
        } catch {
            log("failed to save payload: \(error.localizedDescription)")
            await MainActor.run {
                setStatus("Save failed", detail: error.localizedDescription)
                scheduleCompletion()
            }
            return
        }
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func setStatus(_ text: String, detail: String?) {
        viewModel.status = text
        viewModel.detail = detail
    }

    private func scheduleCompletion() {
        guard !didScheduleCompletion else { return }
        didScheduleCompletion = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.completeRequest()
        }
    }

    @MainActor
    private func playMinimizeAndComplete() {
        guard !didScheduleCompletion else { return }
        didScheduleCompletion = true

        withAnimation(.easeInOut(duration: minimizeDuration)) {
            viewModel.isMinimized = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + minimizeDuration) { [weak self] in
            guard let self else { return }
            self.viewModel.bounceTrigger.toggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + self.bounceDuration) { [weak self] in
                self?.completeRequest()
            }
        }
    }

    private func loadURLString(from provider: NSItemProvider) async throws -> String? {
        if let url = try await loadObject(NSURL.self, from: provider) {
            return url.absoluteString
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let data = try await loadDataRepresentation(for: UTType.url, from: provider),
           let url = URL(dataRepresentation: data, relativeTo: nil)
        {
            return url.absoluteString
        }

        if let string = try await loadObject(NSString.self, from: provider) {
            return string as String
        }

        return nil
    }

    private func loadTextString(from provider: NSItemProvider) async throws -> String? {
        if let string = try await loadObject(NSString.self, from: provider) {
            return string as String
        }

        if let attributed = try await loadObject(NSAttributedString.self, from: provider) {
            return attributed.string
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let data = try await loadDataRepresentation(for: UTType.plainText, from: provider)
        {
            return String(data: data, encoding: .utf8)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier),
           let data = try await loadDataRepresentation(for: UTType.text, from: provider) {
            return String(data: data, encoding: .utf8)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.rtf.identifier),
           let data = try await loadDataRepresentation(for: UTType.rtf, from: provider) {
            return attributedStringText(from: data, type: .rtf)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.html.identifier),
           let data = try await loadDataRepresentation(for: UTType.html, from: provider) {
            return attributedStringText(from: data, type: .html)
        }

        return nil
    }

    private func attributedStringText(from data: Data, type: UTType) -> String? {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: type == .rtf ? NSAttributedString.DocumentType.rtf : .html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        return (try? NSAttributedString(data: data, options: options, documentAttributes: nil))?.string
    }

    private func loadObject<T: NSItemProviderReading>(_ type: T.Type, from provider: NSItemProvider) async throws -> T? {
        guard provider.canLoadObject(ofClass: type) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: type) { object, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: object as? T)
            }
        }
    }

    private func loadDataRepresentation(for type: UTType, from provider: NSItemProvider) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    private func log(_ message: String) {
        #if DEBUG
            print("[ShareExtension] \(message)")
        #endif
    }

    private func shouldOpenAppAfterShare() -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return true }
        if defaults.object(forKey: shareOpenAppAfterShareKey) == nil {
            return true
        }
        return defaults.bool(forKey: shareOpenAppAfterShareKey)
    }

    private func shareDeepLinkURL(for id: String) -> URL? {
        var components = URLComponents()
        components.scheme = "eisonai"
        components.host = "share"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url
    }

    @MainActor
    private func openHostApp(url: URL) {
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: #selector(UIApplication.open(_:options:completionHandler:))),
               current.isMember(of: UIApplication.self),
               let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                break
            }
            responder = current.next
        }
    }
}
