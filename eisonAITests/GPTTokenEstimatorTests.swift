import XCTest
@testable import eisonAI

final class GPTTokenEstimatorTests: XCTestCase {
    private var suiteName: String = ""
    private var defaults: UserDefaults?

    override func setUp() {
        super.setUp()
        suiteName = "eisonAITests.GPTTokenEstimatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suite = defaults {
            suite.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        super.tearDown()
    }

    private func makeEstimator() -> GPTTokenEstimator {
        let settings = TokenEstimatorSettingsStore(defaults: defaults)
        settings.setSelectedEncoding(.cl100k)
        let bundles = [Bundle.main, Bundle(for: GPTTokenEstimatorTests.self)]
        let store = SwiftikTokenStore(resourceBundles: bundles)
        return GPTTokenEstimator(store: store, settingsStore: settings)
    }

    private func makeText(minTokens: Int, estimator: GPTTokenEstimator) async -> String {
        var text = ""
        while await estimator.estimateTokenCount(for: text) < minTokens {
            text += "hello world "
        }
        return text
    }

    func testEstimateTokenCountEmptyIsZero() async {
        let estimator = makeEstimator()
        let count = await estimator.estimateTokenCount(for: "")
        XCTAssertEqual(count, 0)
    }

    func testChunkReturnsEmptyWhenChunkSizeInvalid() async {
        let estimator = makeEstimator()
        let chunksZero = await estimator.chunk(text: "hello", chunkTokenSize: 0)
        XCTAssertTrue(chunksZero.isEmpty)

        let chunksNegative = await estimator.chunk(text: "hello", chunkTokenSize: -1)
        XCTAssertTrue(chunksNegative.isEmpty)
    }

    func testChunkRespectsMaxChunksAndOffsets() async throws {
        let estimator = makeEstimator()
        let sanityCount = await estimator.estimateTokenCount(for: "hello")
        if sanityCount == 0 {
            throw XCTSkip("Tokenizer resources unavailable in test host.")
        }

        let chunkSize = 20
        let text = await makeText(minTokens: chunkSize * 3, estimator: estimator)
        let chunks = await estimator.chunk(text: text, chunkTokenSize: chunkSize, maxChunks: 2)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks.first?.index, 0)
        XCTAssertEqual(chunks.last?.index, 1)

        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.tokenCount, chunkSize)
            XCTAssertGreaterThanOrEqual(chunk.endUTF16, chunk.startUTF16)
        }

        XCTAssertEqual(chunks[0].startUTF16, 0)
        XCTAssertEqual(chunks[1].startUTF16, chunks[0].endUTF16)
    }
}
