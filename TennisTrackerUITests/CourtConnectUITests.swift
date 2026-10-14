import XCTest

final class CourtConnectUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure=false }
    private func openConnect(large: Bool=false) -> XCUIApplication {
        let app=XCUIApplication()
        app.launchArguments=["-ui-testing-reset-store","-ui-testing-venue-dashboard"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout:10))
        app.tabBars.buttons["Settings"].tap()
        revealPhoneElement(app.buttons["Court Story Connect"],in:app).tap()
        XCTAssertTrue(app.navigationBars["Court Story Connect"].waitForExistence(timeout:8))
        return app
    }
    func testOptionalDeviceConnectionNeedsNoEmailAndReturnsToTracking() throws {
        let app=openConnect()
        XCTAssertFalse(app.textFields["Email address"].exists)
        XCTAssertFalse(app.textFields["Email sign-in code"].exists)
        XCTAssertTrue(app.buttons["Enable Connect"].exists)
        var issues: [String]=[]
        try app.performAccessibilityAudit { issue in
            issues.append(issue.compactDescription + ": " + (issue.element?.debugDescription ?? issue.detailedDescription))
            return true
        }
        XCTAssertTrue(issues.isEmpty,issues.joined(separator:"\n"))
        app.navigationBars["Court Story Connect"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.exists)
    }
    func testLargeTextDeviceConnectionRemainsReachable() {
        let app=openConnect(large:true)
        XCTAssertTrue(revealPhoneElement(app.buttons["Enable Connect"],in:app).isHittable)
    }
}
