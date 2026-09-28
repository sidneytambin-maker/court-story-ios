import XCTest

final class WatchTournamentUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testStagePositionAndVisibleCompletionActionsUpdateSummary() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-watch", "-ui-testing-tournament-outcome", "-test-notification=tournament"]
        app.launch()
        let summary = app.buttons["Tournament summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 8))
        expectSummary("Status: Completed", on: summary)
        reveal(app.buttons["Mark Tournament Entered"], in: app).tap()
        expectSummary("Status: Entered", on: summary)

        reveal(app.buttons["Edit"], in: app).tap()
        XCTAssertTrue(app.navigationBars["Edit Tournament"].waitForExistence(timeout: 5))
        let stage = reveal(control("watchTournamentStagePicker", in: app), in: app)
        XCTAssertTrue(stage.label.contains("Stage reached"))
        XCTAssertEqual(stage.value as? String, "Round robin")
        choose("watchTournamentStagePicker", value: "5th and 6th place play-off", in: app)
        let position = reveal(control("watchTournamentFinishingPositionPicker", in: app), in: app)
        XCTAssertTrue(position.label.contains("Finishing position"))
        XCTAssertEqual(position.value as? String, "Not recorded")
        choose("watchTournamentFinishingPositionPicker", value: "6th", in: app)
        XCTAssertEqual(control("watchTournamentStagePicker", in: app).value as? String, "5th and 6th place play-off")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForNonExistence(timeout: 5))
        expectSummary("Status: Entered", on: summary)
        assertOutcome(summary.label)

        // These are the visible counterparts, not XCTest emulation of VoiceOver rotor gestures.
        let complete = reveal(app.buttons["Mark Tournament Complete"], in: app)
        XCTAssertEqual(app.buttons.matching(identifier: "Mark Tournament Complete").count, 1)
        complete.tap()
        expectSummary("Status: Completed", on: summary)
        let reopen = reveal(app.buttons["Mark Tournament Entered"], in: app)
        XCTAssertFalse(app.buttons["Mark Tournament Complete"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        assertOutcome(summary.label)

        reveal(summary, in: app).tap()
        let details = app.staticTexts["watchActivityDetailsSummary"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(details.label.contains("Status: Completed"))
        assertOutcome(details.label)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Watch tournament completed with separate stage and finishing position"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Done"].tap()

        reveal(reopen, in: app).tap()
        expectSummary("Status: Entered", on: summary)
        XCTAssertTrue(reveal(app.buttons["Mark Tournament Complete"], in: app).isHittable)
        XCTAssertFalse(app.buttons["Mark Tournament Entered"].exists)
        assertOutcome(summary.label)
    }

    private func assertOutcome(_ summary: String) {
        XCTAssertTrue(summary.contains("Stage reached: 5th and 6th place play-off"))
        XCTAssertTrue(summary.contains("Finishing position: 6th"))
    }

    private func control(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func choose(_ identifier: String, value: String, in app: XCUIApplication) {
        let picker = reveal(control(identifier, in: app), in: app)
        picker.tap()
        reveal(app.buttons[value], in: app).tap()
        let close = app.buttons["close-sheet"].firstMatch
        if close.waitForExistence(timeout: 1) {
            close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        }
        XCTAssertEqual(picker.value as? String, value)
    }

    private func expectSummary(_ value: String, on summary: XCUIElement) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", value), object: summary)
        let result = XCTWaiter.wait(for: [changed], timeout: 5)
        if result != .completed {
            let app = XCUIApplication()
            let tree = XCTAttachment(string: "Application state: \(app.state.rawValue)\n" + app.debugDescription)
            tree.name = "Tournament status timeout full accessibility tree"
            tree.lifetime = .keepAlways
            add(tree)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Tournament status timeout " + value
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertEqual(result, .completed)
    }

    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<20 {
            let upperEdge = max(app.frame.minY + 40, app.navigationBars.firstMatch.frame.maxY) + 8
            let lowerEdge = app.frame.maxY - 32
            if element.exists && element.isHittable && element.frame.midY > upperEdge && element.frame.midY < lowerEdge {
                return element
            }
            let upward = !element.exists || element.frame.midY >= (upperEdge + lowerEdge) / 2
            if let list = app.scrollViews.allElementsBoundByIndex.last(where: { $0.isHittable })
                ?? app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable }) {
                let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.8 : 0.45))
                let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.45 : 0.8))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            } else if upward { app.swipeUp() } else { app.swipeDown() }
        }
        XCTFail("Could not reach tournament control \(element)")
        return element
    }
}
