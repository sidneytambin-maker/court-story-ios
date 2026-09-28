import XCTest

final class TennisMatchListUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testScheduledMatchesStayScheduledAcrossDatesAtBothTextSizes() {
        for large in [false, true] {
            let app = launch(filter: "-match-list-scheduled-only", large: large)
            XCTAssertTrue(app.staticTexts["Scheduled matches"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Match history"].exists)
            XCTAssertFalse(app.staticTexts["In progress"].exists)
            for opponent in ["Past Scheduled", "Future Scheduled"] {
                let match = revealPhoneElement(row(opponent, in: app), in: app, showing: .top)
                let summary = (match.value as? String) ?? ""
                XCTAssertTrue(summary.contains("Scheduled"))
                XCTAssertTrue(summary.contains("Example Centre Court"))
                XCTAssertTrue(summary.contains("Example Town"))
                XCTAssertTrue(summary.contains(" at "))
                if opponent == "Future Scheduled" {
                    XCTAssertTrue(summary.contains("Example Nationals"))
                    XCTAssertTrue(summary.contains("Scheduled doubles semi-final"))
                    XCTAssertTrue(summary.contains("Taylor Example"))
                    XCTAssertTrue(summary.contains("Casey Example"))
                }
                capturePhoneSummary(match, in: app, name: "Scheduled \(opponent) \(large ? "large" : "normal")")
            }
            XCTAssertFalse(app.staticTexts["Match history"].exists)
            app.terminate()
        }
    }

    func testRecordedFutureOutcomeStaysInHistoryAndInProgressHasOwnSection() {
        let finished = launch(filter: "-match-list-finished-only")
        XCTAssertTrue(finished.staticTexts["Match history"].waitForExistence(timeout: 5))
        XCTAssertFalse(finished.staticTexts["Scheduled matches"].exists)
        XCTAssertFalse(finished.staticTexts["In progress"].exists)
        let future = revealPhoneElement(row("Future Result", in: finished), in: finished, showing: .top)
        XCTAssertTrue((future.value as? String)?.contains("Completed") == true)
        XCTAssertTrue((future.value as? String)?.contains("beat Future Result") == true)
        future.tap()
        XCTAssertTrue(finished.navigationBars["Match detail"].waitForExistence(timeout: 5))
        finished.terminate()

        let mixed = launch()
        XCTAssertTrue(mixed.staticTexts["In progress"].waitForExistence(timeout: 5))
        let active = revealPhoneElement(row("Live Opponent", in: mixed), in: mixed, showing: .top)
        XCTAssertTrue((active.value as? String)?.contains("In progress") == true)
        capturePhoneSummary(active, in: mixed, name: "In-progress match separated from scheduled and history")
        revealPhoneElement(mixed.staticTexts["Scheduled matches"], in: mixed)
        revealPhoneElement(mixed.staticTexts["Match history"], in: mixed)
    }

    func testEmptyMatchListHasOneEmptyStateAndNoStatusHeadings() {
        for mode in ["Basic", "Standard", "Power"] {
            let app = launch(filter: "-match-list-empty", mode: mode)
            XCTAssertTrue(app.staticTexts["No matches recorded yet"].waitForExistence(timeout: 5))
            for title in ["Scheduled matches", "In progress", "Match history"] { XCTAssertFalse(app.staticTexts[title].exists) }
            XCTAssertEqual(app.staticTexts.matching(identifier: "No matches recorded yet").count, 1)
            XCTAssertTrue(app.buttons["addMatchButton"].isEnabled)
            app.terminate()
        }
    }

    private func launch(filter: String = "", large: Bool = false, mode: String = "Basic") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset-store", "-ui-testing-match-list", "-match-list-mode=" + mode]
        if !filter.isEmpty { app.launchArguments.append(filter) }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Matches"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Matches"].tap()
        return app
    }

    private func row(_ opponent: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND value CONTAINS %@", "Match", opponent)).firstMatch
    }
}
