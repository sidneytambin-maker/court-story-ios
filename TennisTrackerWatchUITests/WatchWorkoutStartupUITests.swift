import XCTest

final class WatchWorkoutStartupUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func start(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-watch", "-watch-page=Track", "-watch-scheduled-training", "-watch-health=" + mode]
        app.launch()
        XCTAssertTrue(app.buttons["Track Training Session"].waitForExistence(timeout: 10))
        app.buttons["Track Training Session"].tap()
        let start = app.buttons["startWatchWorkout"]
        reveal(start, in: app)
        XCTAssertEqual(start.label, "Start Workout")
        XCTAssertEqual(app.buttons.matching(identifier: "startWatchWorkout").count, 1)
        XCTAssertFalse(app.buttons["Begin without Health"].exists)
        start.tap()
        return app
    }

    func testGrantedHealthStartsAndSavesThroughSingleAction() {
        let app = start("authorized")
        assertRecording(app)
        finish(app)
        XCTAssertTrue(app.staticTexts["Tennis workout saved."].waitForExistence(timeout: 10))
    }

    func testUndecidedPermissionStartsAfterGrant() {
        let app = start("new-access")
        assertRecording(app)
        XCTAssertFalse(app.staticTexts["healthStartFailure"].exists)
    }

    func testStartFailureIsVisibleAndRetryStartsSameSession() {
        let app = start("retry")
        XCTAssertTrue(app.staticTexts["healthStartFailure"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["endTrainingWorkout"].exists)
        let retry = app.buttons["retryWatchWorkout"]
        reveal(retry, in: app); retry.tap()
        assertRecording(app)
        finish(app)
        XCTAssertEqual(app.buttons.matching(identifier: "Completed training summary").count, 1)
    }

    func testKnownDenialIsNotMisrepresentedAsRecording() {
        let app = start("denied")
        let failure = app.staticTexts["healthStartFailure"]
        XCTAssertTrue(failure.waitForExistence(timeout: 10))
        XCTAssertTrue(failure.label.contains("Workout saving is turned off"))
        XCTAssertFalse(app.buttons["endTrainingWorkout"].exists)
        capture(app, "Watch Health permission recovery")
    }

    func testCancelledPendingStartCannotBecomeRecordingLater() {
        let app = start("pending")
        let cancel = app.buttons["cancelWatchWorkoutStart"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        cancel.tap()
        XCTAssertTrue(app.staticTexts["No tennis activity in progress."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["endTrainingWorkout"].waitForExistence(timeout: 4))
    }

    func testHealthSaveFailureDoesNotClaimSuccessfulHealthSave() {
        let app = start("save-failure")
        assertRecording(app)
        finish(app)
        XCTAssertTrue(app.staticTexts["Training saved. The Health workout could not be saved."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Tennis workout saved."].exists)
    }

    func testNativeHealthKitStartAndSave() {
        // Uses HKWorkoutSession and HKLiveWorkoutBuilder, not the fault-injection
        // client. Simulator success still cannot establish physical sensor data.
        let app = start("real")
        for _ in 0..<16 {
            if app.buttons["endTrainingWorkout"].waitForExistence(timeout: 2) { break }
            if app.staticTexts["healthStartFailure"].exists { break }
            for title in ["Turn On All", "Allow All", "Next", "Allow", "Done"] {
                let button = app.buttons[title]
                if button.exists && button.isHittable { button.tap() }
            }
            for toggle in app.switches.allElementsBoundByIndex where toggle.isHittable && toggle.value as? String == "0" { toggle.tap() }
        }
        capture(app, "Native Watch HealthKit startup")
        assertRecording(app)
        finish(app)
        XCTAssertTrue(app.staticTexts["Tennis workout saved."].waitForExistence(timeout: 35))
        capture(app, "Native Watch HealthKit saved workout")
    }

    private func assertRecording(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["endTrainingWorkout"].waitForExistence(timeout: 25), app.debugDescription)
        let status = app.staticTexts["activeHealthStatus"]
        XCTAssertTrue(status.label.contains("Health workout recording"), status.label)
        XCTAssertFalse(status.label.contains("without Health"))
    }

    private func finish(_ app: XCUIApplication) {
        app.buttons["endTrainingWorkout"].tap()
        XCTAssertTrue(app.buttons["confirmEndTrainingWorkout"].waitForExistence(timeout: 5))
        app.buttons["confirmEndTrainingWorkout"].tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
