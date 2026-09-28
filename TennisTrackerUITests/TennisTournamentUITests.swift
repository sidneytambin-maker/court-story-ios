import XCTest

final class TennisTournamentUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testStagePositionAndVisibleCompletionActionsStayIndependent() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset-store", "-ui-testing-tournament-outcome"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Tournaments"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Tournaments"].tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "tournamentList.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Meadow Cup")
        expectValue("Status: Completed", on: row)
        reveal(row, in: app).tap()
        let summary = app.descendants(matching: .any).matching(identifier: "tournamentDetailsSummary")
            .matching(NSPredicate(format: "value != nil")).firstMatch
        expectValue("Status: Completed", on: summary)
        app.navigationBars.buttons["Edit"].tap()

        let status = reveal(app.buttons["tournamentStatusPicker"], in: app)
        XCTAssertEqual(status.value as? String, "Completed")
        choose("tournamentStatusPicker", value: "Entered", in: app)
        let stage = reveal(app.buttons["tournamentStagePicker"], in: app)
        XCTAssertTrue(stage.label.contains("Stage reached"))
        XCTAssertEqual(stage.value as? String, "Round robin")
        choose("tournamentStagePicker", value: "5th and 6th place play-off", in: app)
        let position = reveal(app.buttons["tournamentFinishingPositionPicker"], in: app)
        XCTAssertTrue(position.label.contains("Finishing position"))
        XCTAssertEqual(position.value as? String, "Not recorded")
        choose("tournamentFinishingPositionPicker", value: "6th", in: app)
        XCTAssertEqual(app.buttons["tournamentStagePicker"].value as? String, "5th and 6th place play-off")
        app.buttons["saveTournamentButton"].tap()
        XCTAssertTrue(app.buttons["saveTournamentButton"].waitForNonExistence(timeout: 5))
        expectValue("Status: Entered", on: summary)
        assertOutcome(summary)

        // The visible button shares the rotor callback; this test does not perform rotor gestures.
        let action = reveal(app.buttons["tournamentCompletionButton"], in: app)
        XCTAssertEqual(action.label, "Mark Tournament Complete")
        action.tap()
        expectValue("Status: Completed", on: summary)
        expectLabel("Mark Tournament Entered", on: action)
        assertOutcome(summary)
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertEqual(app.sheets.count, 0)
        reveal(action, in: app).tap()
        expectValue("Status: Entered", on: summary)
        expectLabel("Mark Tournament Complete", on: action)
        assertOutcome(summary)
        app.navigationBars.buttons.firstMatch.tap()
        expectValue("Status: Entered", on: row)
        XCTAssertTrue(app.buttons["Mark Tournament Complete"].exists)
        XCTAssertFalse(app.buttons["Mark Tournament Entered"].exists)
        reveal(app.buttons["Mark Tournament Complete"], in: app).tap()
        expectValue("Status: Completed", on: row)
        let reopen = reveal(app.buttons["Mark Tournament Entered"], in: app)
        assertOutcome(row)
        reveal(row, in: app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "iPhone completed tournament row with stage and finishing position"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        reveal(reopen, in: app).tap()
        expectValue("Status: Entered", on: row)
        XCTAssertTrue(app.buttons["Mark Tournament Complete"].exists)
        XCTAssertFalse(app.buttons["Mark Tournament Entered"].exists)
        assertOutcome(row)
    }

    private func assertOutcome(_ summary: XCUIElement) {
        let value = (summary.value as? String) ?? ""
        XCTAssertTrue(value.contains("Stage reached: 5th and 6th place play-off"))
        XCTAssertTrue(value.contains("Finishing position: 6th"))
    }

    private func choose(_ identifier: String, value: String, in app: XCUIApplication) {
        let picker = reveal(app.buttons[identifier], in: app)
        picker.tap()
        reveal(app.buttons[value], in: app).tap()
        expectValue(value, on: picker)
        XCTAssertEqual(picker.value as? String, value)
    }

    private func expectValue(_ value: String, on element: XCUIElement) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    private func expectLabel(_ label: String, on element: XCUIElement) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        revealPhoneElement(element, in: app)
    }
}
