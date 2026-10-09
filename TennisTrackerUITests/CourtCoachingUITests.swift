import XCTest

final class CourtCoachingUITests: XCTestCase {
    private let app = XCUIApplication()
    override func setUp() { continueAfterFailure = false }

    private func launch(_ mode: String = "power", large: Bool = false) {
        app.launchArguments = ["-ui-testing-reset-store", "-ui-testing-court-coach", "-ui-court-" + mode]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Players"].waitForExistence(timeout: 30))
    }
    private func reveal(_ element: XCUIElement) {
        for step in 0..<40 {
            if element.exists && element.isHittable { return }
            let up = element.exists ? element.frame.midY > app.frame.midY : (step < 12 || step >= 32)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.78 : 0.40))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.40 : 0.78))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        evidence("Failed to reach requested control")
        XCTFail("Could not reach \(element)")
    }
    private func openAthlete() {
        app.tabBars.buttons["Players"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Demo Player Morgan")).firstMatch
        reveal(row); row.tap()
        XCTAssertTrue(app.navigationBars["Demo Player Morgan"].waitForExistence(timeout: 10))
        reveal(app.buttons["Edit player"])
    }
    private func evidence(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + " accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
    func testCoachRosterObservationEditAndReportPrivacy() {
        launch(); openAthlete(); evidence("Coach athlete progress")
        let observation = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Demo observation: deeper returns")).firstMatch
        reveal(observation); observation.tap()
        let happened = app.textViews["observationHappened"].exists ? app.textViews["observationHappened"] : app.textFields["observationHappened"]
        XCTAssertTrue(happened.waitForExistence(timeout: 10)); happened.tap(); happened.typeText(". UI edit retained")
        app.buttons["saveObservation"].tap()
        let report = app.buttons["Preview progress report"]
        reveal(report); report.tap()
        XCTAssertTrue(app.switches["Include private observations"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.switches["Include private observations"].value as? String, "0")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "UI edit retained", "UI edit retained")).firstMatch.exists)
        evidence("Progress report private details excluded")
        let include = app.switches["Include private observations"]
        include.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5)).tap()
        XCTAssertEqual(include.value as? String, "1")
        let edited = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "UI edit retained", "UI edit retained")).firstMatch
        reveal(edited); XCTAssertTrue(edited.exists)
    }
    func testBasicHidesJournalMediaAndReportsWhileKeepingCoreProgress() {
        launch("basic"); openAthlete()
        for _ in 0..<8 { app.swipeUp() }
        XCTAssertFalse(app.buttons["Photos, clips and moments"].exists)
        XCTAssertFalse(app.buttons["Preview progress report"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Demo observation: deeper returns")).firstMatch.exists)
        evidence("Basic coach athlete progress")
    }
    func testLargeTextMediaNavigationAndCancellation() {
        launch("standard", large: true); openAthlete()
        let media = app.buttons["Photos, clips and moments"]; reveal(media); media.tap()
        XCTAssertTrue(app.buttons["addCoachingMediaPhotos"].waitForExistence(timeout: 10))
        let files = app.buttons["addCoachingMediaFiles"]; reveal(files); evidence("Large text media library")
        files.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.tap()
        XCTAssertTrue(app.buttons["addCoachingMediaFiles"].waitForExistence(timeout: 10))
    }
}
