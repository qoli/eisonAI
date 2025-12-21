import Foundation

struct SharePayload: Codable, Identifiable, Equatable {
    let id: String
    let createdAt: Date
    let url: String?
    let text: String?
    let title: String?
}
