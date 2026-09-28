import XCTest

final class TennisTournamentSummaryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDashboardUpcomingTournamentAnnouncesTwoScheduledMatches() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset-store", "-ui-testing-tournament-summary"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 8))
        let summary = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Example Scheduled Open,")).firstMatch
        revealPhoneElement(summary, in: app)
        XCTAssertTrue(summary.isHittable)
        XCTAssertTrue(summary.label.contains("2 scheduled matches"), summary.label)
        XCTAssertFalse(summary.label.contains("No matches"), summary.label)
        XCTAssertFalse(summary.label.contains("No recorded matches"), summary.label)
        XCTAssertFalse(summary.label.contains("completed matches"), summary.label)
        XCTAssertFalse(summary.label.contains("wins"), summary.label)
        capturePhoneEvidence(app, name: "iPhone dashboard upcoming tournament with two scheduled matches")
    }
}
