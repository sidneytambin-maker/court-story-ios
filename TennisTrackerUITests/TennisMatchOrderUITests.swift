import XCTest

final class TennisMatchOrderUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testReverseInsertionShows1205Before1400AndSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset-store", "-ui-testing-match-list", "-match-list-time-order"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Matches"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Matches"].tap()
        let earlier = row("Earlier 1205", in: app)
        let later = row("Later 1400", in: app)
        XCTAssertTrue(earlier.waitForExistence(timeout: 5))
        XCTAssertTrue(later.waitForExistence(timeout: 5))
        XCTAssertLessThan(earlier.frame.minY, later.frame.minY)
        let identifier = earlier.identifier
        capturePhoneEvidence(app, name: "Scheduled 1205 before 1400 despite reverse insertion")
        earlier.tap()
        app.navigationBars.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["saveMatchButton"].waitForExistence(timeout: 5))
        app.buttons["saveMatchButton"].tap()
        XCTAssertTrue(app.navigationBars["Match detail"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Matches"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Matches"].tap()
        let restored = row("Earlier 1205", in: app)
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        XCTAssertEqual(restored.identifier, identifier)
        XCTAssertLessThan(restored.frame.minY, row("Later 1400", in: app).frame.minY)
        XCTAssertFalse(app.staticTexts["Match history"].exists)
    }

    private func row(_ opponent: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND value CONTAINS %@", "Match", opponent)).firstMatch
    }
}
