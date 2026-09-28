import XCTest

final class TennisDashboardEntryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBasicEntryKeepsCoreInputAndDisclosesOptionalDetails() {
        launch()
        app.buttons["dashboardAddActivity"].tap()
        app.buttons["Track Training Session"].tap()
        XCTAssertTrue(app.buttons["trainingTypePicker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveTrainingButton"].isEnabled)
        XCTAssertFalse(app.buttons["Coaches"].exists)
        XCTAssertFalse(app.switches["trainingIncludeRatings"].exists)
        expandPhoneSection("trainingEntryDetails", in: app)
        reveal(app.buttons["activityVenuePicker"]).tap()
        app.buttons["Training Court, Town"].tap()
        reveal(app.buttons["trainingEntryDetails"]).tap()
        XCTAssertEqual(app.buttons["trainingEntryDetails"].value as? String, "Collapsed")
        XCTAssertFalse(app.buttons["activityVenuePicker"].exists)
        expandPhoneSection("trainingEntryDetails", in: app)
        XCTAssertEqual(reveal(app.buttons["activityVenuePicker"]).value as? String, "Training Court, Town")
        capture("iPhone Basic optional details retain venue and child identifiers")
        reveal(app.buttons["Coaches"]).tap()
        XCTAssertTrue(app.navigationBars["Coaches"].waitForExistence(timeout: 5))
        app.navigationBars["Coaches"].buttons.firstMatch.tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 5))
    }

    func testPowerMetricsSurviveEditsInBasicAndStandard() {
        launch()
        setMode("Power")
        openFixtureMatchEditor()
        reveal(app.buttons["matchAces"]).tap()
        app.buttons["7"].tap()
        app.buttons["saveMatchButton"].tap()
        XCTAssertTrue(app.navigationBars["Match detail"].waitForExistence(timeout: 5))

        for mode in ["Basic", "Standard"] {
            setMode(mode)
            openFixtureMatchEditor()
            XCTAssertFalse(app.buttons["matchAces"].exists)
            // Saving an unrelated edit must not clear hidden performance fields.
            app.buttons["saveMatchButton"].tap()
            XCTAssertTrue(app.navigationBars["Match detail"].waitForExistence(timeout: 5))
            app.tabBars.buttons["Training"].tap()
            app.buttons["addTrainingButton"].tap()
            XCTAssertFalse(app.switches["trainingIncludeRatings"].exists)
            app.buttons["Cancel"].tap()
        }

        setMode("Power")
        openFixtureMatchEditor()
        XCTAssertEqual(reveal(app.buttons["matchAces"]).value as? String, "7")
        app.buttons["Cancel"].tap()
        app.tabBars.buttons["Training"].tap()
        app.buttons["addTrainingButton"].tap()
        XCTAssertTrue(reveal(app.switches["trainingIncludeRatings"]).exists)
    }

    func testDashboardGroupedResultsAndBasicDisclosure() {
        launch()
        let results = revealPhoneElement(element("resultSummary.Doubles matches"), in: app, showing: .top)
        XCTAssertTrue((results.value as? String)?.contains("3 matches. 1 win, 2 losses, 0 draws") == true)
        XCTAssertTrue((results.value as? String)?.contains("Includes 3 matches played during training") == true)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "resultSummary.Doubles matches")
            .matching(NSPredicate(format: "value != nil")).count, 1)
        XCTAssertFalse(app.buttons["dashboardEditGoals"].exists)
        expandPhoneSection("dashboardInsights", in: app)
        XCTAssertTrue(reveal(app.buttons["dashboardEditGoals"]).exists)
        XCTAssertFalse(app.buttons["dashboardCoachPreview"].exists)
    }

    func testCoachPreviewIsPowerOnlyAndPersonalContentIsOptIn() {
        launch()
        for mode in ["Basic", "Standard"] {
            setMode(mode)
            app.tabBars.buttons["Dashboard"].tap()
            XCTAssertFalse(app.buttons["dashboardCoachPreview"].exists)
        }
        setMode("Power")
        app.tabBars.buttons["Dashboard"].tap()
        reveal(app.buttons["dashboardCoachPreview"]).tap()
        XCTAssertTrue(app.navigationBars["Coach Summary"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["coachIncludeGoals"].value as? String, "0")
        let preview = revealPhoneElement(app.staticTexts["coachSummaryText"], in: app, showing: .top)
        XCTAssertTrue(preview.label.contains("Training, last 30 days"))
        XCTAssertFalse(preview.label.contains("Goals & match review"))
        XCTAssertFalse(preview.label.contains("Chris"))
        XCTAssertFalse(preview.label.contains("Alex"))
        XCTAssertFalse(preview.label.contains("heart rate"))
        XCTAssertTrue(reveal(app.buttons["coachShareSummary"]).exists)
        XCTAssertFalse(app.otherElements["ActivityListView"].exists)
        reveal(app.switches["coachIncludeGoals"]).tap()
        XCTAssertTrue(revealPhoneElement(app.staticTexts["coachSummaryText"], in: app, showing: .top).label.contains("Goals & match review"))
        app.buttons["Done"].tap()
    }

    func testManualDurationUpdatesDetailAndDashboardWithoutRelabellingHealthWindow() {
        launch(fixture: "-ui-testing-manual-duration")
        app.tabBars.buttons["Training"].tap()
        let session = app.buttons.matching(NSPredicate(format: "label == %@", "Training session")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.tap()
        app.navigationBars.buttons["Edit"].tap()
        let hours = reveal(app.buttons["durationHours"])
        XCTAssertEqual(hours.label, "Duration hours")
        XCTAssertEqual(hours.value as? String, "5 hours")
        hours.tap()
        app.buttons["2 hours"].tap()
        XCTAssertEqual(app.buttons["durationHours"].value as? String, "2 hours")
        let minutes = reveal(app.buttons["durationMinutes"])
        XCTAssertEqual(minutes.label, "Duration minutes")
        XCTAssertEqual(minutes.value as? String, "52 minutes")
        minutes.tap()
        app.buttons["0 minutes"].tap()
        XCTAssertEqual(app.buttons["durationMinutes"].value as? String, "0 minutes")
        app.buttons["saveTrainingButton"].tap()
        let detail = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Fitness measurements cover the original 5 hours 52 minutes recording")).firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(detail.label.contains("2 hours"))
        capture("iPhone corrected duration and original Health window")
        app.navigationBars.buttons["Edit"].tap()
        XCTAssertEqual(reveal(app.buttons["durationHours"]).value as? String, "2 hours")
        XCTAssertEqual(reveal(app.buttons["durationMinutes"]).value as? String, "0 minutes")
        app.buttons["Cancel"].tap()
        app.tabBars.buttons["Dashboard"].tap()
        let summary = reveal(element("dashboardTrainingSummary"))
        XCTAssertTrue((summary.value as? String)?.contains("2 hours") == true)
        XCTAssertFalse((summary.value as? String)?.contains("5 hours") == true)
    }

    func testNormalAndLargeTextDashboardAndEntryScreenshots() {
        for large in [false, true] {
            launch(large: large)
            for mode in ["Basic", "Standard", "Power"] {
                setMode(mode)
                app.tabBars.buttons["Dashboard"].tap()
                scrollToTop()
                capture("iPhone \(mode) dashboard \(large ? "accessibility XXXL" : "normal")")
                let result = revealPhoneElement(element("resultSummary.Doubles matches"), in: app, showing: .top)
                assertFitsHorizontally(result)
                capturePhoneSummary(result, in: app, name: "iPhone \(mode) results \(large ? "accessibility XXXL" : "normal")")
                let insights = reveal(app.buttons["dashboardInsights"])
                XCTAssertEqual(insights.value as? String, mode == "Basic" ? "Collapsed" : "Expanded")
                if mode == "Basic" { expandPhoneSection("dashboardInsights", in: app) }
                XCTAssertEqual(app.buttons.matching(identifier: "dashboardInsights").count, 1)
                reveal(app.buttons["dashboardEditGoals"])
                capture("iPhone \(mode) goals controls \(large ? "accessibility XXXL" : "normal")")
                app.buttons["dashboardAddActivity"].tap()
                app.buttons["Track Training Session"].tap()
                XCTAssertTrue(app.buttons["saveTrainingButton"].waitForExistence(timeout: 5))
                capture("iPhone \(mode) training entry \(large ? "accessibility XXXL" : "normal")")
                assertFitsHorizontally(app.buttons["saveTrainingButton"])
                let minutes = reveal(app.buttons["durationMinutes"])
                XCTAssertEqual(minutes.label, "Duration minutes")
                capture("iPhone \(mode) duration controls \(large ? "accessibility XXXL" : "normal")")
                app.buttons["Cancel"].tap()
                app.buttons["dashboardAddActivity"].tap()
                app.buttons["Record Match"].tap()
                XCTAssertTrue(app.buttons["saveMatchButton"].waitForExistence(timeout: 5))
                capture("iPhone \(mode) match entry \(large ? "accessibility XXXL" : "normal")")
                reveal(app.buttons["set1YourGames"])
                capture("iPhone \(mode) recorded score \(large ? "accessibility XXXL" : "normal")")
                app.buttons["Cancel"].tap()
            }
            app.terminate()
        }
    }

    private func launch(fixture: String = "-ui-testing-venue-dashboard", large: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset-store", fixture]
        if large {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 10))
    }

    private func setMode(_ mode: String) {
        app.tabBars.buttons["Settings"].tap()
        reveal(app.buttons["settingsTrackingModePicker"]).tap()
        app.buttons[mode].tap()
        if app.buttons["settingsTrackingModePicker"].value as? String != mode {
            capture("Unexpected spoken tracking mode " + mode)
        }
        XCTAssertEqual(app.buttons["settingsTrackingModePicker"].value as? String, mode)
    }

    private func openFixtureMatchEditor() {
        app.tabBars.buttons["Matches"].tap()
        if !app.navigationBars["Match detail"].exists {
            let match = app.buttons.matching(NSPredicate(format: "label == %@ AND value CONTAINS %@", "Match", "Sam")).firstMatch
            reveal(match).tap()
        }
        XCTAssertTrue(app.navigationBars["Match detail"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["saveMatchButton"].waitForExistence(timeout: 5))
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id)
            .matching(NSPredicate(format: "value != nil")).firstMatch
    }

    @discardableResult
    private func reveal(_ element: XCUIElement) -> XCUIElement {
        revealPhoneElement(element, in: app)
    }

    private func scrollToTop() {
        reveal(app.staticTexts["Welcome, Alex"])
    }

    private func assertFitsHorizontally(_ element: XCUIElement) {
        XCTAssertGreaterThan(element.frame.width, 0)
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX)
    }

    private func capture(_ name: String) {
        capturePhoneEvidence(app, name: name)
    }
}
