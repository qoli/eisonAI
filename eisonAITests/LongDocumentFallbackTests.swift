import AnyLanguageModel
import XCTest
@testable import eisonAI

@MainActor
final class LongDocumentFallbackTests: XCTestCase {
    func testIsContextWindowExceededDirectError() {
        let viewModel = ClipboardKeyPointViewModel()
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
        let error = LanguageModelSession.GenerationError.exceededContextWindowSize(context)
        XCTAssertTrue(viewModel.isContextWindowExceeded(error))
    }

    func testIsContextWindowExceededFromUnderlyingError() {
        let viewModel = ClipboardKeyPointViewModel()
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
        let underlying = LanguageModelSession.GenerationError.exceededContextWindowSize(context)
        let error = NSError(domain: "test", code: 1, userInfo: [NSUnderlyingErrorKey: underlying])
        XCTAssertTrue(viewModel.isContextWindowExceeded(error))
    }

    func testIsContextWindowExceededFalseForOtherErrors() {
        let viewModel = ClipboardKeyPointViewModel()
        let error = NSError(domain: "test", code: 2)
        XCTAssertFalse(viewModel.isContextWindowExceeded(error))
    }

    func testNextLowerChunkTokenSize() {
        let viewModel = ClipboardKeyPointViewModel()
        let sizes = [2000, 2200, 2600, 3000]

        XCTAssertEqual(viewModel.nextLowerChunkTokenSize(current: 2600, allowedSizes: sizes), 2200)
        XCTAssertNil(viewModel.nextLowerChunkTokenSize(current: 2000, allowedSizes: sizes))
        XCTAssertEqual(viewModel.nextLowerChunkTokenSize(current: 2500, allowedSizes: sizes), 2200)
    }

    func testSliceTextClampsBounds() {
        let viewModel = ClipboardKeyPointViewModel()
        let text = "abcdef"

        XCTAssertEqual(viewModel.sliceText(text, startUTF16: 1, endUTF16: 4), "bcd")
        XCTAssertEqual(viewModel.sliceText(text, startUTF16: -3, endUTF16: 2), "ab")
        XCTAssertEqual(viewModel.sliceText(text, startUTF16: 10, endUTF16: 12), "")
    }
}
