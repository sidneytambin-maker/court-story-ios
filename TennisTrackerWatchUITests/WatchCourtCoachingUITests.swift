import XCTest

final class WatchCourtCoachingUITests: XCTestCase {
    private let app = XCUIApplication()
    override func setUp() { continueAfterFailure = false }
    private func launch(_ mode: String = "Power", large: Bool = false) {
        app.launchArguments = ["-ui-testing-watch", "-ui-testing-court-coach", "-watch-page=Overview", "-watch-mode=" + mode]
        if large { app.launchArguments.append("-watch-large-text") }
        app.launch()
        XCTAssertTrue(app.buttons["Your Players"].waitForExistence(timeout: 30))
    }
    private func tap(_ label: String) {
        let button = app.buttons[label]
        for step in 0..<40 {
            let top = app.navigationBars.allElementsBoundByIndex.last(where: { $0.isHittable })?.frame.maxY ?? 48
            if button.exists && button.isHittable && (button.frame.midY > top || ["Cancel", "Save"].contains(label)) {
                button.tap(); return
            }
            let up = button.exists ? button.frame.midY > top : (step < 12 || step >= 32)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.80 : 0.53))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.53 : 0.80))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        evidence("Failed to reach " + label)
        XCTFail("Could not reach \(label)")
    }
    private func evidence(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + " accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
    func testPlayerJournalProvidesObservationAndMeasurementJourneys() {
        launch(); tap("Your Players"); tap("Demo Player Morgan")
        XCTAssertTrue(app.navigationBars["Demo Player Morgan"].waitForExistence(timeout: 10))
        tap("Journal and Progress")
        tap("Add Observation")
        XCTAssertTrue(app.textFields["What happened"].waitForExistence(timeout: 10))
        evidence("Watch observation editor")
        tap("Cancel")
        tap("Record Measured Drill")
        XCTAssertTrue(app.textFields["Drill name"].waitForExistence(timeout: 10))
        evidence("Watch measured drill editor")
        tap("Cancel")
    }
    func testBasicRosterKeepsHistoryWithoutAdvancedJournalRoute() {
        launch("Basic", large: true); tap("Your Players"); tap("Demo Player Morgan")
        for _ in 0..<8 { app.swipeUp() }
        XCTAssertFalse(app.buttons["Journal and Progress"].exists)
        evidence("Large text Basic player details")
    }
    func testAthleteProgressHasPeriodAndScopedResults() {
        launch(); tap("Your Players"); tap("Demo Player Morgan")
        tap("Journal and Progress"); tap("Progress by Period")
        XCTAssertTrue(app.navigationBars["Player Progress"].waitForExistence(timeout: 10))
        tap("watchProgressPeriod"); tap("Last 7 days")
        let close = app.buttons["close-sheet"]
        if close.waitForExistence(timeout: 1) { close.tap() }
        let training = app.descendants(matching: .any).matching(identifier: "watchProgress.Training").firstMatch
        for _ in 0..<16 {
            if training.exists && training.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(training.exists)
        XCTAssertTrue((training.value as? String ?? "").contains("recorded sessions"))
        evidence("Watch scoped seven-day athlete progress")
    }
    func testWelcomeValidatesNameAndCancelRetainsRoleChoice() {
        app.launchArguments = ["-ui-testing-watch", "-ui-testing-court-welcome", "-ui-testing-reset-setup"]
        app.launch()
        XCTAssertTrue(app.buttons["watchSetupCoach"].waitForExistence(timeout: 20))
        tap("watchSetupCoach")
        tap("watchSetupContinue")
        XCTAssertTrue(app.staticTexts["watchSetupError"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["watchSetupError"].label.contains("Enter your name"))
        tap("Cancel Setup")
        tap("watchSetupPlayer")
        XCTAssertTrue(app.textFields["watchSetupName"].waitForExistence(timeout: 5))
        evidence("Native Watch player welcome and essential fields")
    }
    func testRestoredWelcomeDraftCanChooseSportModeAndFinishCoachSetup() {
        // A saved fictional name exercises resume without relying on simulator dictation.
        app.launchArguments = ["-ui-testing-watch", "-ui-testing-court-welcome", "-ui-testing-reset-setup", "-ui-testing-named-setup"]
        app.launch()
        XCTAssertTrue(app.buttons["watchSetupCoach"].waitForExistence(timeout: 20))
        tap("watchSetupCoach")
        XCTAssertEqual(app.textFields["watchSetupName"].value as? String, "Demo Wrist Player")
        tap("courtSportPicker"); tap("Badminton")
        if app.buttons["close-sheet"].waitForExistence(timeout: 1) { app.buttons["close-sheet"].tap() }
        tap("watchSetupContinue")
        tap("watchSetupMode"); tap("Standard")
        if app.buttons["close-sheet"].waitForExistence(timeout: 1) { app.buttons["close-sheet"].tap() }
        tap("watchSetupContinue")
        evidence("Watch setup summary before finishing")
        app.terminate()
        app.launchArguments = ["-ui-testing-watch", "-ui-testing-court-welcome"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Ready for your court story"].waitForExistence(timeout: 20))
        tap("watchSetupContinue")
        XCTAssertTrue(app.buttons["Your Players"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["watchSetupCoach"].exists)
        evidence("Completed native Watch coach setup")
    }
}
