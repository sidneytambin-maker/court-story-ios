import XCTest

final class WatchMatchListUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testScheduledRowsNeverBecomeHistoryBecauseTheirDatePassed() {
        for large in [false, true] {
            let app = launch(filter: "-match-list-scheduled-only", large: large)
            reveal(app.staticTexts["Scheduled matches"], in: app)
            XCTAssertFalse(app.staticTexts["Match history"].exists)
            XCTAssertFalse(app.staticTexts["In progress"].exists)
            for name in ["Past Scheduled", "Future Scheduled"] {
                let row = match(name, in: app)
                reveal(row, in: app)
                XCTAssertTrue(row.label.contains("Scheduled"))
                XCTAssertTrue(row.label.contains("Example Centre Court"))
                XCTAssertTrue(row.label.contains("Example Town"))
                XCTAssertTrue(row.label.contains(" at "))
                if name == "Future Scheduled" {
                    XCTAssertTrue(row.label.contains("Scheduled doubles semi-final"))
                    XCTAssertTrue(row.label.contains("Taylor Example"))
                    XCTAssertTrue(row.label.contains("Casey Example"))
                }
                capture(app, name: "Watch scheduled \(name) top \(large ? "large" : "normal")")
                reveal(row, in: app, showingBottom: true)
                capture(app, name: "Watch scheduled \(name) bottom \(large ? "large" : "normal")")
            }
            XCTAssertFalse(app.staticTexts["Match history"].exists)
            app.terminate()
        }
    }

    func testFutureResultBelongsToHistoryWithoutEmptyReviewHeading() {
        let app = launch(filter: "-match-list-finished-only")
        reveal(app.staticTexts["Match history"], in: app)
        XCTAssertFalse(app.staticTexts["Scheduled matches"].exists)
        XCTAssertFalse(app.staticTexts["In progress"].exists)
        reveal(match("Past Result", in: app), in: app)
        let row = match("Future Result", in: app)
        reveal(row, in: app)
        XCTAssertTrue(row.label.contains("Completed"))
        XCTAssertTrue(row.label.contains("beat Future Result"))
        XCTAssertFalse(app.staticTexts["Needs Details"].exists)
    }

    func testSavedInProgressAndScheduledScoringChoicesAreSeparated() {
        let app = launch(page: "Score")
        reveal(app.staticTexts["In progress"], in: app)
        let active = app.buttons["Score Morgan Example against Live Opponent"]
        reveal(active, in: app)
        XCTAssertTrue((active.value as? String)?.contains("In progress") == true)
        reveal(app.staticTexts["Scheduled matches"], in: app)
        let scheduled = app.buttons["Score Morgan Example against Past Scheduled"]
        reveal(scheduled, in: app)
        XCTAssertTrue((scheduled.value as? String)?.contains("Scheduled") == true)
        XCTAssertFalse(app.buttons["Score Morgan Example against Future Result"].exists)
    }

    func testEmptyRecentHasOneEmptyStateAndNoMatchHeadings() {
        for mode in ["Basic", "Standard", "Power"] {
            let app = launch(filter: "-match-list-empty", mode: mode)
            XCTAssertTrue(app.staticTexts["No recent activity"].waitForExistence(timeout: 5))
            for title in ["Scheduled matches", "In progress", "Match history", "Needs Details"] {
                XCTAssertFalse(app.staticTexts[title].exists)
            }
            XCTAssertEqual(app.staticTexts.matching(identifier: "No recent activity").count, 1)
            app.terminate()
        }
    }

    func testReverseInsertionPlaces1205FirstInRecentScoreAndOverview() {
        for page in ["Recent", "Score", "Overview"] {
            let app = launch(page: page, filter: "-match-list-time-order")
            let first = page == "Score"
                ? app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Score Morgan Example against")).firstMatch
                : app.buttons.matching(identifier: "Match summary").firstMatch
            reveal(first, in: app)
            XCTAssertTrue(first.label.contains("Earlier 1205"))
            XCTAssertFalse(first.label.contains("Later 1400"))
            capture(app, name: "Watch \(page) selects 1205 before 1400")
            app.terminate()
        }
    }

    private func launch(page: String = "Recent", filter: String = "", large: Bool = false, mode: String = "Basic") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-watch", "-ui-testing-match-list", "-watch-page=" + page, "-match-list-mode=" + mode]
        if !filter.isEmpty { app.launchArguments.append(filter) }
        if large { app.launchArguments.append("-watch-large-text") }
        app.launch()
        XCTAssertTrue(app.navigationBars[page].waitForExistence(timeout: 10) || app.staticTexts[page].exists)
        return app
    }

    private func match(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "Match summary").matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, showingBottom: Bool = false) {
        for _ in 0..<40 {
            let navigation = app.navigationBars.firstMatch
            let status = app.statusBars.firstMatch
            let top = max(status.exists ? status.frame.maxY : app.frame.minY,
                          navigation.exists ? navigation.frame.maxY : app.frame.minY)
            let bottom = app.frame.maxY
            var upward = true
            if element.exists {
                // Reveal readable portions of a tall native row, with slack for a non-flinging drag.
                let height = min(element.frame.height, (bottom - top) * 0.7)
                let y = showingBottom ? element.frame.maxY - height : element.frame.minY
                if element.isHittable && y >= top && y + height <= bottom { return }
                upward = y >= top
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let mid = (top + bottom) / 2 - app.frame.minY
            let delta: CGFloat = upward ? 26 : -26
            let start = origin.withOffset(CGVector(dx: app.frame.width / 2, dy: mid + delta))
            let end = origin.withOffset(CGVector(dx: app.frame.width / 2, dy: mid - delta))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        capture(app, name: "Failed match-list reveal")
        XCTFail("Could not reveal \(element)")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + " accessibility tree"; tree.lifetime = .keepAlways; add(tree)
    }
}
