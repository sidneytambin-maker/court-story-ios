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
    func testOptionalSignInHasAccessibleFieldsAndReturnsToTracking() throws {
        let app=openConnect()
        XCTAssertTrue(app.textFields["Email address"].exists)
        XCTAssertTrue(app.textFields["Email sign-in code"].exists)
        XCTAssertTrue(app.buttons["Send sign-in code"].exists)
        try app.performAccessibilityAudit()
        app.navigationBars["Court Story Connect"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.exists)
    }
    func testLargeTextSignInControlsRemainReachable() {
        let app=openConnect(large:true)
        XCTAssertTrue(revealPhoneElement(app.textFields["Email address"],in:app).isHittable)
        XCTAssertTrue(revealPhoneElement(app.buttons["Send sign-in code"],in:app).isHittable)
        XCTAssertTrue(revealPhoneElement(app.buttons["Sign in"],in:app).isHittable)
    }
}
