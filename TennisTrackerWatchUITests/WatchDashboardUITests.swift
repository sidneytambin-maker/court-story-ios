import XCTest

final class WatchDashboardUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBasicDashboardDisclosurePreservesSpokenResults() {
        let app = launch()
        let progress = reveal(app.buttons["overviewProgress"], in: app)
        XCTAssertEqual(progress.value as? String, "Collapsed")
        XCTAssertFalse(result("Doubles", in: app).exists)
        progress.tap()
        XCTAssertEqual(progress.value as? String, "Expanded")
        let doubles = reveal(result("Doubles", in: app), in: app)
        XCTAssertTrue((doubles.value as? String)?.contains("3 matches. 1 win, 2 losses, 0 draws") == true)
        XCTAssertFalse((doubles.value as? String)?.contains("Win rate") == true)
        capture(app, name: "Watch Basic expanded results")
        reveal(progress, in: app).tap()
        XCTAssertEqual(progress.value as? String, "Collapsed")
        XCTAssertFalse(result("Doubles", in: app).exists)
    }

    func testNormalAndLargeTextModesKeepAdvancedMetricsPowerOnly() {
        for large in [false, true] {
            for mode in ["Basic", "Standard", "Power"] {
                let app = launch(mode: mode, large: large)
                capture(app, name: "Watch \(mode) overview \(large ? "accessibility large" : "normal")")
                let progress = reveal(app.buttons["overviewProgress"], in: app)
                XCTAssertEqual(progress.value as? String, mode == "Basic" ? "Collapsed" : "Expanded")
                if mode == "Basic" { progress.tap() }
                let doubles = reveal(result("Doubles", in: app), in: app)
                XCTAssertTrue((doubles.value as? String)?.contains("1 win, 2 losses") == true)
                XCTAssertEqual((doubles.value as? String)?.contains("Win rate") == true, mode == "Power")
                assertFitsHorizontally(doubles, in: app)
                capture(app, name: "Watch \(mode) results \(large ? "accessibility large" : "normal")")
                app.terminate()
            }
        }
    }

    func testScheduledEntryHasOneStartActionAndCapturesBothTextSizes() {
        for large in [false, true] {
            let app = launch(large: large, fixture: "-watch-scheduled-training")
            let start = reveal(app.buttons["overviewStartSession"], in: app)
            XCTAssertEqual(start.label, "Start Session")
            XCTAssertTrue(start.isEnabled)
            XCTAssertFalse(app.buttons["Begin with Health Workout"].exists)
            XCTAssertFalse(app.buttons["Begin without Health"].exists)
            XCTAssertEqual(app.buttons.matching(identifier: "overviewStartSession").count, 1)
            assertFitsHorizontally(start, in: app)
            capture(app, name: "Watch scheduled entry \(large ? "accessibility large" : "normal")")
            app.terminate()
        }
    }

    func testActiveMatchResumePrecedesDashboardDetails() {
        let app = launch(fixture: "-watch-active-match")
        let resume = app.buttons["overviewResumeMatch"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        resume.tap()
        XCTAssertTrue(app.buttons["Record Point for Alex"].waitForExistence(timeout: 5))
    }

    func testEmptyOverviewOffersTrackingAndSyncStatusCanBeExpanded() {
        let app = launch(fixture: "")
        let track = app.buttons["overviewTrackActivity"]
        XCTAssertTrue(track.waitForExistence(timeout: 10))
        let sync = reveal(app.buttons["overviewSyncStatus"], in: app)
        XCTAssertEqual(sync.value as? String, "Collapsed")
        sync.tap()
        XCTAssertEqual(sync.value as? String, "Expanded")
        reveal(track, in: app).tap()
        XCTAssertTrue(app.buttons["Track Training Session"].waitForExistence(timeout: 5))
    }

    private func launch(mode: String = "Basic", large: Bool = false, fixture: String = "-watch-venue-regression") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-watch", "-watch-page=Overview", "-watch-mode=" + mode]
        if !fixture.isEmpty { app.launchArguments.append(fixture) }
        if large { app.launchArguments.append("-watch-large-text") }
        app.launch()
        XCTAssertTrue(app.navigationBars["Overview"].waitForExistence(timeout: 10) || app.staticTexts["Overview"].exists)
        return app
    }

    private func result(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "overviewResults." + name)
            .matching(NSPredicate(format: "value != nil")).firstMatch
    }

    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<16 {
            if element.exists && element.isHittable { return element }
            app.swipeUp()
        }
        for _ in 0..<20 {
            if element.exists && element.isHittable { return element }
            app.swipeDown()
        }
        XCTFail("Could not reach \(element)")
        return element
    }

    private func assertFitsHorizontally(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertGreaterThan(element.frame.width, 0)
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
