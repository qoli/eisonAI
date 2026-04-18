import XCTest

final class BrowserAgentAutomationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWikipediaOscarsAgentRun() throws {
        let app = XCUIApplication()
        app.launchEnvironment["EISON_UI_TEST_OPEN_BROWSER"] = "1"
        app.launchEnvironment["EISON_UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["EISON_UI_TEST_BROWSER_URL"] = "https://www.wikipedia.org"
        app.launchEnvironment["EISON_UI_TEST_BROWSER_PROMPT"] = "Check Wikipedia about Oscars 2026. Tell me who won the best picture."
        app.launchEnvironment["EISON_UI_TEST_BROWSER_AUTO_RUN"] = "1"
        app.launch()

        let taskStateTitle = app.staticTexts["Task State"]
        XCTAssertTrue(taskStateTitle.waitForExistence(timeout: 30), app.debugDescription)

        let hideLogButton = app.buttons["Hide Log"]
        XCTAssertTrue(hideLogButton.waitForExistence(timeout: 30), app.debugDescription)

        let stopButton = app.buttons["Stop"]
        XCTAssertTrue(
            stopButton.waitForExistence(timeout: 60),
            "Expected browser agent automation to enter a running state.\n\(app.debugDescription)"
        )
        stopButton.tap()

        let runButton = app.buttons["Run"]
        XCTAssertTrue(
            runButton.waitForExistence(timeout: 20),
            "Expected browser agent automation to stop after tapping Stop.\n\(app.debugDescription)"
        )

        XCTAssertTrue(
            hasTerminalStatus(in: app),
            "Expected browser agent automation to finish as Completed, Failed, or Stopped.\n\(app.debugDescription)"
        )
    }

    private func hasTerminalStatus(in app: XCUIApplication) -> Bool {
        app.staticTexts["Completed"].exists
            || app.staticTexts["Failed"].exists
            || app.staticTexts["Stopped"].exists
    }
}
