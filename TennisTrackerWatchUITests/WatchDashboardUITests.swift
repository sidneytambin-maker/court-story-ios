import XCTest

final class WatchDashboardUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBasicDashboardDisclosurePreservesSpokenResults() {
        let app = launch()
        let progress = reveal(app.buttons["overviewProgress"], in: app)
        assertFullyVisible(progress, in: app)
        capture(app, name: "Watch Basic collapsed results control")
        XCTAssertEqual(progress.value as? String, "Collapsed")
        XCTAssertFalse(result("Doubles", in: app).exists)
        progress.tap()
        XCTAssertEqual(progress.value as? String, "Expanded")
        let doubles = reveal(result("Doubles", in: app), in: app, showing: .summaryTop)
        XCTAssertTrue((doubles.value as? String)?.contains("3 matches. 1 win, 2 losses, 0 draws") == true)
        XCTAssertFalse((doubles.value as? String)?.contains("Win rate") == true)
        captureSummary(doubles, in: app, name: "Watch Basic expanded results")
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
                assertFullyVisible(progress, in: app)
                capture(app, name: "Watch \(mode) results control \(large ? "accessibility large" : "normal")")
                XCTAssertEqual(progress.value as? String, mode == "Basic" ? "Collapsed" : "Expanded")
                if mode == "Basic" { progress.tap() }
                let doubles = reveal(result("Doubles", in: app), in: app, showing: .summaryTop)
                XCTAssertTrue((doubles.value as? String)?.contains("1 win, 2 losses") == true)
                XCTAssertEqual((doubles.value as? String)?.contains("Win rate") == true, mode == "Power")
                assertFitsHorizontally(doubles, in: app)
                captureSummary(doubles, in: app, name: "Watch \(mode) results \(large ? "accessibility large" : "normal")")
                app.terminate()
            }
        }
    }

    func testScheduledEntryHasOneStartActionAndCapturesBothTextSizes() {
        for large in [false, true] {
            let app = launch(large: large, fixture: "-watch-scheduled-training")
            let start = reveal(app.buttons["overviewStartSession"], in: app)
            XCTAssertEqual(start.label, "Start Workout")
            XCTAssertTrue(start.isEnabled)
            XCTAssertFalse(app.buttons["Begin with Health Workout"].exists)
            XCTAssertFalse(app.buttons["Begin without Health"].exists)
            XCTAssertEqual(app.buttons.matching(identifier: "overviewStartSession").count, 1)
            assertFullyVisible(start, in: app)
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
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, showing region: VisibleRegion = .control) -> XCUIElement {
        var upward = true
        var previousRows = ""
        var stationarySteps = 0
        for _ in 0..<60 {
            let viewport = contentViewport(in: app)
            var distance = min(60, viewport.height * 0.35)
            if element.exists {
                let target = requiredFrame(of: element, showing: region, viewport: viewport)
                if element.isHittable && !target.isEmpty && viewport.contains(target) { return element }
                if target.maxY > viewport.maxY {
                    upward = true
                    distance = min(distance, target.maxY - viewport.maxY + 2)
                } else if target.minY < viewport.minY {
                    upward = false
                    distance = min(distance, viewport.minY - target.minY + 2)
                }
            } else {
                let rows = visibleRows(in: app, viewport: viewport)
                stationarySteps = !rows.isEmpty && rows == previousRows ? stationarySteps + 1 : 0
                if stationarySteps == 2 {
                    upward.toggle()
                    stationarySteps = 0
                }
                previousRows = rows
            }
            scroll(in: app, viewport: viewport, upward: upward, distance: distance)
        }
        capture(app, name: "Failed to reveal " + element.identifier)
        XCTFail("Could not fully reveal \(element). Element frame: \(element.exists ? element.frame.debugDescription : "missing"); content viewport: \(contentViewport(in: app))")
        return element
    }

    private enum VisibleRegion {
        case control, summaryTop, summaryBottom
    }

    private func contentViewport(in app: XCUIApplication) -> CGRect {
        let screen = app.frame
        let navigation = app.navigationBars.firstMatch
        let status = app.statusBars.firstMatch
        let upperEdge = max(status.exists ? status.frame.maxY : screen.minY,
                            navigation.exists ? navigation.frame.maxY : screen.minY)
        let lowerEdge = screen.maxY
        return CGRect(x: screen.minX, y: upperEdge, width: screen.width, height: max(0, lowerEdge - upperEdge))
    }

    private func requiredFrame(of element: XCUIElement, showing region: VisibleRegion, viewport: CGRect) -> CGRect {
        let frame = element.frame
        // A tall summary may scroll naturally; a button must fit completely.
        let height = min(frame.height, max(0, viewport.height * 0.7))
        switch region {
        case .control: return frame
        case .summaryTop: return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: height)
        case .summaryBottom: return CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
        }
    }

    private func visibleRows(in app: XCUIApplication, viewport: CGRect) -> String {
        let cells = app.cells.allElementsBoundByIndex
        let rows = cells.isEmpty ? app.buttons.allElementsBoundByIndex : cells
        return rows.filter { $0.frame.intersects(viewport) }
            .map { "\($0.identifier):\($0.label):\(Int($0.frame.minY))" }.joined(separator: "|")
    }

    private func scroll(in app: XCUIApplication, viewport: CGRect, upward: Bool, distance: CGFloat) {
        let list = app.scrollViews.allElementsBoundByIndex.last(where: { $0.isHittable })
            ?? app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable })
            ?? app
        // Sub-threshold drags can leave the Watch list stationary even when a row is clipped.
        let travel = min(max(40, distance), viewport.height * 0.45)
        let offset = upward ? travel / 2 : -travel / 2
        let origin = list.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: viewport.midX - list.frame.minX, dy: viewport.midY + offset - list.frame.minY))
        let end = origin.withOffset(CGVector(dx: viewport.midX - list.frame.minX, dy: viewport.midY - offset - list.frame.minY))
        // Stop before release so inertia cannot skip a short, lazily loaded row.
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    private func assertFullyVisible(_ element: XCUIElement, in app: XCUIApplication) {
        assertFitsHorizontally(element, in: app)
        let viewport = contentViewport(in: app)
        XCTAssertGreaterThan(element.frame.height, 0)
        XCTAssertGreaterThanOrEqual(element.frame.minY, viewport.minY)
        XCTAssertLessThanOrEqual(element.frame.maxY, viewport.maxY)
        XCTAssertTrue(element.isHittable)
    }

    private func captureSummary(_ element: XCUIElement, in app: XCUIApplication, name: String) {
        reveal(element, in: app, showing: .summaryTop)
        capture(app, name: name + " top")
        if !contentViewport(in: app).contains(element.frame) {
            reveal(element, in: app, showing: .summaryBottom)
            capture(app, name: name + " bottom")
        }
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
        let accessibility = XCTAttachment(string: app.debugDescription)
        accessibility.name = name + " accessibility tree"
        accessibility.lifetime = .keepAlways
        add(accessibility)
    }
}
