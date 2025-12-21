import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private var didHandle = false
    private var didScheduleCompletion = false
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textColor = .label
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center

        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        detailLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [statusLabel, detailLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])

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

            let providers = item.attachments ?? []
            log("attachments count: \(providers.count)")
            for provider in providers {
                if urlString == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await loadURLString(from: provider) {
                        urlString = url
                        log("loaded url: \(url)")
                    }
                }

                if text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
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
            let fileURL = try SharePayloadStore().save(payload)
            log("saved payload: \(fileURL.lastPathComponent)")
        } catch {
            log("failed to save payload: \(error.localizedDescription)")
            await MainActor.run {
                setStatus("Save failed", detail: error.localizedDescription)
                scheduleCompletion()
            }
            return
        }

        await MainActor.run {
            setStatus("Saved", detail: "Closing in 2 seconds…")
            scheduleCompletion()
        }
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func setStatus(_ text: String, detail: String?) {
        statusLabel.text = text
        detailLabel.text = detail
        detailLabel.isHidden = (detail == nil) || (detail?.isEmpty == true)
    }

    private func scheduleCompletion() {
        guard !didScheduleCompletion else { return }
        didScheduleCompletion = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.completeRequest()
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

        return nil
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
}
