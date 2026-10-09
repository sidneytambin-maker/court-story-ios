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
        if ["Cancel", "Save", "saveWatchTraining"].contains(label) {
            // Native watchOS toolbar buttons have nested accessibility wrappers.
            let toolbarButton = app.navigationBars.buttons.matching(identifier: label).firstMatch
            if toolbarButton.exists && toolbarButton.isHittable { toolbarButton.tap(); return }
        }
        let button = app.buttons[label]
        reveal(button, label: label)
        button.press(forDuration: 0.15)
    }
    private func reveal(_ button: XCUIElement, label: String) {
        for step in 0..<40 {
            let top = app.navigationBars.allElementsBoundByIndex.last(where: { $0.isHittable })?.frame.maxY ?? 48
            if button.exists && button.isHittable &&
                ((button.frame.midY > top && button.frame.midY < app.frame.maxY - 6) || ["Cancel", "Save"].contains(label)) {
                return
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
        XCTAssertTrue(app.navigationBars["Observation"].waitForExistence(timeout: 10))
        reveal(app.textFields["What happened"], label: "What happened")
        XCTAssertTrue(app.textFields["What happened"].exists)
        evidence("Watch observation editor")
        tap("Cancel")
        tap("Record Measured Drill")
        reveal(app.textFields["Drill name"], label: "Drill name")
        XCTAssertTrue(app.textFields["Drill name"].exists)
        evidence("Watch measured drill editor")
        tap("Cancel")
    }
    func testBasicRosterKeepsHistoryWithoutAdvancedJournalRoute() {
        launch("Basic", large: true); tap("Your Players"); tap("Demo Player Morgan")
        for _ in 0..<8 { app.swipeUp() }
        XCTAssertFalse(app.buttons["Journal and Progress"].exists)
        evidence("Large text Basic player details")
    }
    func testObservationCreatesPracticePlanThatSurvivesRelaunch() {
        launch(); tap("Your Players"); tap("Demo Player Morgan"); tap("Journal and Progress")
        let observation = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Demo observation: deeper returns")).firstMatch
        reveal(observation, label: "Saved observation"); observation.tap()
        tap("Plan Practice")
        XCTAssertTrue(app.navigationBars["Plan Practice"].waitForExistence(timeout: 10))
        tap("saveWatchTraining")
        XCTAssertTrue(app.navigationBars["Observation"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["Your Players"].waitForExistence(timeout: 20))
        tap("Your Players"); tap("Demo Player Morgan")
        let planned = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS[c] %@", "watchPlannedTraining", "Returning")).firstMatch
        reveal(planned, label: "Saved planned returning practice")
        XCTAssertTrue(planned.exists)
        evidence("Watch saved practice plan after relaunch")
    }
    func testAthleteProgressHasPeriodAndScopedResults() {
        launch(); tap("Your Players"); tap("Demo Player Morgan")
        tap("Journal and Progress"); tap("Progress by Period")
        XCTAssertTrue(app.navigationBars["Player Progress"].waitForExistence(timeout: 10))
        tap("watchProgressPeriod"); tap("Last 7 days")
        let close = app.buttons["close-sheet"]
        if close.waitForExistence(timeout: 1) { close.tap() }
        let training = app.descendants(matching: .any).matching(identifier: "watchProgress.Training")
            .matching(NSPredicate(format: "value != nil")).firstMatch
        reveal(training, label: "Training progress")
        XCTAssertTrue(training.exists)
        XCTAssertTrue((training.value as? String ?? "").contains("recorded sessions"))
        evidence("Watch scoped seven-day athlete progress")
    }
    func testPlayerEditorRoutesKeepAthleteIdentityAndReturnAfterSave() {
        launch(); tap("Your Players"); tap("Demo Player Morgan"); tap("Edit Player")
        XCTAssertEqual(app.textFields["watchCourtPlayerName"].value as? String, "Demo Player Morgan")
        tap("Access Preferences")
        XCTAssertTrue(app.navigationBars["Access Preferences"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["accessPreferenceSummary"].exists)
        evidence("Watch athlete access preferences")
        app.navigationBars["Access Preferences"].buttons.firstMatch.tap()
        tap("Default Match Format")
        XCTAssertTrue(app.navigationBars["Match Format"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["courtOfficialFormat"].exists)
        app.navigationBars["Match Format"].buttons.firstMatch.tap()
        tap("watchSaveCourtPlayer")
        XCTAssertTrue(app.navigationBars["Demo Player Morgan"].waitForExistence(timeout: 10))
        tap("Edit Player")
        XCTAssertEqual(app.textFields["watchCourtPlayerName"].value as? String, "Demo Player Morgan")
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
