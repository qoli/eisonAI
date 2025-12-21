import Foundation

enum KeyPointInput: Identifiable, Equatable {
    case clipboard
    case share(SharePayload)

    var id: String {
        switch self {
        case .clipboard:
            return "clipboard"
        case .share(let payload):
            return payload.id
        }
    }
}
