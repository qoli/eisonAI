import XCTest
@testable import eisonAI

@MainActor
final class LongDocumentPromptBuilderTests: XCTestCase {
    func testReadingAnchorSystemPromptIncludesChunkInfo() {
        let viewModel = ClipboardKeyPointViewModel()
        let prompt = viewModel.buildReadingAnchorSystemPrompt(chunkIndex: 2, chunkTotal: 5)
        XCTAssertTrue(prompt.contains("chunk 2 of 5"))
    }

    func testReadingAnchorUserPromptTrimsContentAndHandlesEmpty() {
        let viewModel = ClipboardKeyPointViewModel()
        let prompt = viewModel.buildReadingAnchorUserPrompt(text: "  Hello world  ")
        XCTAssertTrue(prompt.contains("Hello world"))

        let emptyPrompt = viewModel.buildReadingAnchorUserPrompt(text: "   ")
        XCTAssertTrue(emptyPrompt.contains("(empty)"))
    }

    func testSummaryUserPromptRemovesThinkTagsAndIncludesChunks() {
        let viewModel = ClipboardKeyPointViewModel()
        let anchors = [
            ReadingAnchorChunk(index: 0, tokenCount: 1, text: "<think>secret</think>Visible", startUTF16: nil, endUTF16: nil),
            ReadingAnchorChunk(index: 1, tokenCount: 1, text: "Second", startUTF16: nil, endUTF16: nil),
        ]

        let prompt = viewModel.buildSummaryUserPrompt(from: anchors)

        XCTAssertTrue(prompt.contains("Chunk 1"))
        XCTAssertTrue(prompt.contains("Chunk 2"))
        XCTAssertTrue(prompt.contains("Visible"))
        XCTAssertFalse(prompt.lowercased().contains("<think>"))
        XCTAssertFalse(prompt.lowercased().contains("</think>"))
    }
}
