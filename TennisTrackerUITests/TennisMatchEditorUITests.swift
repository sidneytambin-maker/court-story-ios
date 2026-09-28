import XCTest

final class TennisMatchEditorUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testBasicRoundAndTimeSaveAndReopenWithoutChangingDate() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset-store", "-ui-testing-match-list", "-match-list-scheduled-only", "-match-list-mode=Basic"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Matches"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Matches"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label == %@ AND value CONTAINS %@", "Match", "Past Scheduled")).firstMatch
        revealPhoneElement(row, in: app).tap()
        app.navigationBars.buttons["Edit"].tap()
        let round = revealPhoneElement(app.buttons["matchRoundPicker"], in: app)
        XCTAssertEqual(round.label, "Match round, Not specified")
        XCTAssertEqual(round.value as? String, "Not specified")
        XCTAssertFalse(app.buttons["matchAces"].exists)
        let date = app.descendants(matching: .any).matching(identifier: "matchDatePicker")
            .matching(NSPredicate(format: "value != nil")).firstMatch
        let originalDate = revealPhoneElement(date, in: app).value as? String
        XCTAssertNotNil(originalDate)
        let minutes = app.buttons["Start time minutes"]
        let originalMinutes = revealPhoneElement(minutes, in: app).value as? String
        XCTAssertNotNil(originalMinutes)
        choose(app.buttons["Start time hour"], value: "13 hours", in: app)
        XCTAssertEqual(minutes.value as? String, originalMinutes)
        choose(minutes, value: "35 minutes", in: app)
        choose(round, value: "Round of 16", in: app)
        saveAndReopen(app)
        XCTAssertEqual(revealPhoneElement(round, in: app).value as? String, "Round of 16")
        XCTAssertEqual(revealPhoneElement(date, in: app).value as? String, originalDate)
        XCTAssertEqual(app.buttons["Start time hour"].value as? String, "13 hours")
        XCTAssertEqual(minutes.value as? String, "35 minutes")
        revealPhoneElement(app.switches["matchStartTimeSpecified"], in: app).tap()
        choose(round, value: "Final", in: app)
        saveAndReopen(app)
        XCTAssertEqual(revealPhoneElement(round, in: app).value as? String, "Final")
        let timeSpecified = revealPhoneElement(app.switches["matchStartTimeSpecified"], in: app)
        XCTAssertEqual(timeSpecified.value as? String, "0")
        timeSpecified.tap()
        XCTAssertEqual(app.buttons["Start time hour"].value as? String, "13 hours")
        XCTAssertEqual(minutes.value as? String, "35 minutes")
        XCTAssertEqual(date.value as? String, originalDate)
        capturePhoneEvidence(app, name: "iPhone Basic match round and preserved start time")
        choose(round, value: "Not specified", in: app)
        app.buttons["saveMatchButton"].tap()
        XCTAssertTrue(app.buttons["saveMatchButton"].waitForNonExistence(timeout: 5))
    }

    func testActiveMatchScheduleIsReadOnlyAndPreservedWhenRoundChanges() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset-store", "-ui-testing-match-list", "-match-list-mode=Basic"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Matches"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Matches"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label == %@ AND value CONTAINS %@", "Match", "Live Opponent")).firstMatch
        revealPhoneElement(row, in: app).tap()
        app.navigationBars.buttons["Edit"].tap()
        let schedule = app.descendants(matching: .any).matching(identifier: "matchReadOnlySchedule")
            .matching(NSPredicate(format: "value != nil")).firstMatch
        let originalSchedule = revealPhoneElement(schedule, in: app).value as? String
        XCTAssertEqual(schedule.label, "Match date and time")
        XCTAssertTrue(originalSchedule?.contains(" at ") == true)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "matchDatePicker").firstMatch.exists)
        XCTAssertFalse(app.switches["matchStartTimeSpecified"].exists)
        XCTAssertFalse(app.buttons["Start time hour"].exists)
        XCTAssertFalse(app.buttons["Start time minutes"].exists)
        let round = app.buttons["matchRoundPicker"]
        choose(round, value: "Semi-final", in: app)
        saveAndReopen(app)
        XCTAssertEqual(revealPhoneElement(round, in: app).value as? String, "Semi-final")
        XCTAssertEqual(revealPhoneElement(schedule, in: app).value as? String, originalSchedule)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "matchDatePicker").firstMatch.exists)
        XCTAssertFalse(app.switches["matchStartTimeSpecified"].exists)
        XCTAssertFalse(app.buttons["Start time hour"].exists)
        XCTAssertFalse(app.buttons["Start time minutes"].exists)
    }

    private func saveAndReopen(_ app: XCUIApplication) {
        app.buttons["saveMatchButton"].tap()
        XCTAssertTrue(app.buttons["saveMatchButton"].waitForNonExistence(timeout: 5))
        app.navigationBars.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["saveMatchButton"].waitForExistence(timeout: 5))
    }

    private func choose(_ picker: XCUIElement, value: String, in app: XCUIApplication) {
        revealPhoneElement(picker, in: app).tap()
        revealPhoneElement(app.buttons[value], in: app).tap()
        XCTAssertEqual(picker.value as? String, value)
    }
}
