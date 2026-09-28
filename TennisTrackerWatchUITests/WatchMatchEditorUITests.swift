import XCTest

final class WatchMatchEditorUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testScheduledRoundAndTimeSaveAndReopenWithoutChangingDate() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-watch", "-ui-testing-match-list", "-match-list-scheduled-only", "-match-list-mode=Basic", "-watch-page=Recent"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Recent"].waitForExistence(timeout: 8))
        openEditor(app)
        let round = app.buttons["matchRoundPicker"]
        XCTAssertEqual(reveal(round, in: app).label, "Match round")
        XCTAssertEqual(round.value as? String, "Not specified")
        let date = app.buttons["watchMatchDatePicker"]
        let originalDate = reveal(date, in: app).value as? String
        XCTAssertNotNil(originalDate)
        let minutes = app.buttons["Start time minutes"]
        let originalMinutes = reveal(minutes, in: app).value as? String
        XCTAssertNotNil(originalMinutes)
        choose(app.buttons["Start time hour"], value: "13 hours", in: app)
        XCTAssertEqual(minutes.value as? String, originalMinutes)
        choose(minutes, value: "35 minutes", in: app)
        choose(round, value: "Round robin", in: app)
        saveAndReopen(app)
        XCTAssertEqual(reveal(round, in: app).value as? String, "Round robin")
        XCTAssertEqual(reveal(date, in: app).value as? String, originalDate)
        XCTAssertEqual(reveal(app.buttons["Start time hour"], in: app).value as? String, "13 hours")
        XCTAssertEqual(reveal(minutes, in: app).value as? String, "35 minutes")
        reveal(app.switches["matchStartTimeSpecified"], in: app).tap()
        choose(round, value: "Final", in: app)
        saveAndReopen(app)
        XCTAssertEqual(reveal(round, in: app).value as? String, "Final")
        let specified = reveal(app.switches["matchStartTimeSpecified"], in: app)
        XCTAssertEqual(specified.value as? String, "0")
        specified.tap()
        XCTAssertEqual(reveal(app.buttons["Start time hour"], in: app).value as? String, "13 hours")
        XCTAssertEqual(reveal(minutes, in: app).value as? String, "35 minutes")
        capture(app, name: "Watch match round and retained start time")
        choose(round, value: "Not specified", in: app)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForNonExistence(timeout: 5))
        let summary = app.buttons.matching(identifier: "Match summary")
            .matching(NSPredicate(format: "label CONTAINS %@", "Past Scheduled")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("Scheduled singles match"))
        XCTAssertTrue(summary.label.contains("Example Centre Court"))
    }

    private func openEditor(_ app: XCUIApplication) {
        let cell = app.cells.matching(NSPredicate(format: "label CONTAINS %@", "Past Scheduled")).firstMatch
        reveal(cell.buttons["Edit"], in: app).tap()
        XCTAssertTrue(app.navigationBars["Edit Match"].waitForExistence(timeout: 5))
    }

    private func saveAndReopen(_ app: XCUIApplication) {
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForNonExistence(timeout: 5))
        openEditor(app)
    }

    private func choose(_ picker: XCUIElement, value: String, in app: XCUIApplication) {
        reveal(picker, in: app).tap()
        reveal(app.buttons[value], in: app).tap()
        let close = app.buttons["close-sheet"].firstMatch
        if close.waitForExistence(timeout: 1) {
            close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        }
        XCTAssertEqual(picker.value as? String, value)
    }

    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<32 {
            let navigation = app.navigationBars.firstMatch
            let top = navigation.exists ? navigation.frame.maxY : app.frame.minY + 28
            let bottom = app.frame.maxY
            var upward = true
            if element.exists {
                if element.isHittable && element.frame.minY >= top && element.frame.maxY <= bottom { return element }
                upward = element.frame.minY >= top
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let middle = (top + bottom) / 2 - app.frame.minY
            let delta: CGFloat = upward ? 26 : -26
            let start = origin.withOffset(CGVector(dx: app.frame.width / 2, dy: middle + delta))
            let end = origin.withOffset(CGVector(dx: app.frame.width / 2, dy: middle - delta))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        capture(app, name: "Failed match editor reveal")
        XCTFail("Could not reveal \(element)")
        return element
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: "Application state: \(app.state.rawValue)\n" + app.debugDescription)
        tree.name = name + " accessibility tree"; tree.lifetime = .keepAlways; add(tree)
    }
}
