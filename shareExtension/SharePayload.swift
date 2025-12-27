import Foundation

struct SharePayload: Codable, Identifiable, Equatable {
    // Mockup examples:
    // title: "Deep Work Notes"
    // url: "https://example.com/articles/deep-work"
    // text: "Summary draft: focus blocks, shallow work limits, weekly review."
    // createdAt: 2025-12-27T08:15:30Z
    let id: String
    let createdAt: Date
    let url: String?
    let text: String?
    let title: String?
}
