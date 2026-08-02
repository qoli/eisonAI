import XCTest
@testable import eisonAI

final class RawGenerationStateTests: XCTestCase {
    func testLegacyItemWithoutGenerationStateRemainsExplicitlyLegacy() throws {
        let json = """
        {
          "v": 1,
          "id": "legacy-item",
          "createdAt": "2026-08-02T00:00:00Z",
          "url": "https://example.com/article",
          "title": "Legacy",
          "articleText": "Original article",
          "summaryText": "Existing summary",
          "tags": [],
          "systemPrompt": "System",
          "userPrompt": "User",
          "modelId": "legacy-model"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(RawHistoryItem.self, from: Data(json.utf8))

        XCTAssertNil(item.generationState)
        XCTAssertEqual(item.resolvedGenerationState, .legacy)
        XCTAssertNil(item.generationError)
    }

    func testFailedGenerationStateRoundTripsWithError() throws {
        let item = RawHistoryItem(
            v: 1,
            id: "failed-item",
            createdAt: Date(timeIntervalSince1970: 0),
            url: "https://example.com/article",
            title: "Failed",
            articleText: "Original article",
            summaryText: "",
            systemPrompt: "",
            userPrompt: "",
            modelId: "",
            generationState: .failed,
            generationError: "Exceeded rate limit"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RawHistoryItem.self, from: data)

        XCTAssertEqual(decoded.resolvedGenerationState, .failed)
        XCTAssertEqual(decoded.generationError, "Exceeded rate limit")
        XCTAssertEqual(decoded.articleText, "Original article")
        XCTAssertTrue(decoded.summaryText.isEmpty)
    }
}
