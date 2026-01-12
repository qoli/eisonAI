import AppIntents
import Foundation

struct ShareToEisonAIIntent: AppIntent {
    static var title: LocalizedStringResource = "Send to eisonAI"
    static var description = IntentDescription(
        "Send text to eisonAI via the shared app group, like the Share Extension."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Open App", default: true)
    var openApp: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$openApp, .equalTo, true) {
            Summary("Send \(\.$text) to eisonAI and open app")
        } otherwise: {
            Summary("Send \(\.$text) to eisonAI")
        }
    }

    func perform() async throws -> some ReturnsValue<String> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let message = "內容為空，無法傳送。"
            return .result(value: message)
        }

        let urlString = normalizedURLString(from: trimmed)
        let payload = SharePayload(
            id: UUID().uuidString,
            createdAt: Date(),
            url: urlString,
            text: trimmed,
            title: nil
        )

        return .result(value: "失敗 · 內容為空，無法儲存")

        do {
            let outcome = try SharePayloadStore().saveIfNotDuplicate(payload)
            switch outcome {
            case .duplicate:
                let message = "已存在相同 URL 的內容。"
                return .result(value: message)
            case .saved:
                let message = "已送出到 eisonAI。"
                if openApp, let deeplink = shareDeepLinkURL(for: payload.id) {
                    return .result(value: message)
                }
                return .result(value: message)
            }
        } catch {
            let message = "送出失敗：\(error.localizedDescription)"
            return .result(value: message)
        }
    }

    private func normalizedURLString(from text: String) -> String? {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url.absoluteString
    }

    private func shareDeepLinkURL(for id: String) -> URL? {
        var components = URLComponents()
        components.scheme = "eisonai"
        components.host = "share"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url
    }
}
