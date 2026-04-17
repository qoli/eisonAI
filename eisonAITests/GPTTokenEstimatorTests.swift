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

final class BrowserAgentSupportTests: XCTestCase {
    func testResponseParserNormalizesWrappedJSON() throws {
        let raw = """
        ```json
        {
          "response": {
            "evaluation_previous_goal": "Clicked the search field successfully.",
            "memory": "The page is a search form with one main query box.",
            "next_goal": "Type the requested query into the search field.",
            "status": "continue",
            "summary": "Prepare to enter the search text.",
            "action": {
              "type": "input",
              "index": 4,
              "text": "browser agent"
            }
          }
        }
        ```
        """

        let response = try BrowserAgentResponseParser.parse(raw)

        XCTAssertEqual(response.status, .continue)
        XCTAssertEqual(response.evaluationPreviousGoal, "Clicked the search field successfully.")
        XCTAssertEqual(response.memory, "The page is a search form with one main query box.")
        XCTAssertEqual(response.nextGoal, "Type the requested query into the search field.")
        XCTAssertEqual(response.summary, "Prepare to enter the search text.")
        XCTAssertEqual(response.action?.type, .input)
        XCTAssertEqual(response.action?.index, 4)
        XCTAssertEqual(response.action?.text, "browser agent")
    }

    func testResponseParserRejectsContinueWithoutAction() {
        let raw = """
        {
          "evaluationPreviousGoal": "Observation succeeded.",
          "memory": "The page has interactive controls.",
          "nextGoal": "Take the next action.",
          "status": "continue",
          "summary": "Missing the required action."
        }
        """

        XCTAssertThrowsError(try BrowserAgentResponseParser.parse(raw)) { error in
            XCTAssertEqual(error as? BrowserAgentResponseParserError, .missingActionForContinue)
        }
    }

    func testResponseParserRejectsInvalidActionPayload() {
        let raw = """
        {
          "evaluationPreviousGoal": "Observation succeeded.",
          "memory": "The page has interactive controls.",
          "nextGoal": "Click the primary button.",
          "status": "continue",
          "summary": "The model chose a click action without an index.",
          "action": {
            "type": "click"
          }
        }
        """

        XCTAssertThrowsError(try BrowserAgentResponseParser.parse(raw)) { error in
            guard case .invalidAction(let message)? = error as? BrowserAgentResponseParserError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("index"))
        }
    }

    func testTaskStateUpdatesFollowObservationResponseAndActionResult() {
        var state = BrowserAgentTaskState.starting(
            goal: "Search for browser automation news.",
            pageURL: "https://example.com",
            pageTitle: "Example",
            maxSteps: 10
        )

        let observation = BrowserPageObservation(
            url: "https://example.com/search",
            title: "Search",
            header: "Current Page: [Search](https://example.com/search)",
            content: "[4]<input placeholder=Search />",
            footer: "[End of page]"
        )
        state.recordObservation(observation, step: 2)

        let response = BrowserAgentResponse(
            evaluationPreviousGoal: "The page loaded correctly.",
            memory: "Index 4 is the search field.",
            nextGoal: "Type the query into the search field.",
            status: .continue,
            summary: "Use the visible search field.",
            action: BrowserAgentAction(
                type: .input,
                index: 4,
                text: "browser automation news",
                option: nil,
                url: nil,
                direction: nil,
                pages: nil,
                milliseconds: nil
            )
        )
        state.recordModelResponse(response, step: 2)
        state.recordPlannedAction(response.action!, step: 2)

        let result = BrowserBridgeActionResult(success: true, message: "Filled the search field.")
        state.recordActionResult(result, for: response.action!, step: 2)

        XCTAssertEqual(state.currentStep, 2)
        XCTAssertEqual(state.currentPage?.title, "Search")
        XCTAssertEqual(state.latestEvaluation, "The page loaded correctly.")
        XCTAssertEqual(state.latestMemory, "Index 4 is the search field.")
        XCTAssertEqual(state.nextGoal, "Type the query into the search field.")
        XCTAssertEqual(state.lastStepSummary, "Use the visible search field.")
        XCTAssertEqual(state.lastAction?.type, .input)
        XCTAssertEqual(state.lastAction?.outcome, .succeeded)
        XCTAssertTrue(state.importantFacts.contains("Filled a page field for the current task."))
        XCTAssertTrue(state.lastValidationError.isEmpty)
    }
}
