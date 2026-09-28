import XCTest

final class WatchTournamentSummaryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testUpcomingTournamentAnnouncesAndDisplaysTwoScheduledMatches() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-watch", "-ui-testing-tournament-summary", "-watch-page=Overview"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Overview"].waitForExistence(timeout: 8))
        let summary = app.buttons["Tournament summary"]
        reveal(summary, in: app)
        XCTAssertTrue(summary.isHittable)
        assertScheduledSummary(summary.label)
        capture(app, name: "Watch upcoming tournament with two scheduled matches")
        summary.tap()
        XCTAssertTrue(app.navigationBars["Summary"].waitForExistence(timeout: 5))
        let details = app.staticTexts["watchActivityDetailsSummary"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        reveal(details, in: app, showingBottom: true)
        XCTAssertTrue(details.isHittable)
        assertScheduledSummary(details.label)
        capture(app, name: "Watch visible tournament summary shows two scheduled matches")
    }

    private func assertScheduledSummary(_ text: String) {
        XCTAssertTrue(text.contains("Example Scheduled Open"), text)
        XCTAssertTrue(text.contains("2 scheduled matches"), text)
        XCTAssertFalse(text.contains("No matches"), text)
        XCTAssertFalse(text.contains("No recorded matches"), text)
        XCTAssertFalse(text.contains("completed matches"), text)
        XCTAssertFalse(text.contains("wins"), text)
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
        capture(app, name: "Failed tournament summary reveal")
        XCTFail("Could not reveal \(element)")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + " accessibility tree"; tree.lifetime = .keepAlways; add(tree)
    }
}
