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
    private func openResponse(_ response: String, expired: Bool=false, fromCoach: Bool=false) -> XCUIApplication {
        let app=XCUIApplication()
        app.launchArguments=["-ui-testing-reset-store","-ui-testing-venue-dashboard","-ui-testing-connect-invitation","-ui-testing-connect-link","https://court-story-connect.firebaseapp.com/connect/invite#"+String(repeating:"a",count:64)+(response.isEmpty ? "" : "/"+response)]
        if expired { app.launchArguments.append("-ui-testing-connect-expired") }
        if fromCoach { app.launchArguments.append("-ui-testing-connect-from-coach") }
        app.launch()
        XCTAssertTrue(app.navigationBars["Court Story Connect"].waitForExistence(timeout:10))
        return app
    }
    func testFirstUseInvitationHasAcceptAndDeclineWithoutEnableStep() {
        let app=openResponse("")
        XCTAssertTrue(app.buttons["Accept invitation"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["Decline invitation"].exists)
        XCTAssertFalse(app.buttons["Enable Connect"].exists)
        app.buttons["Accept invitation"].tap()
        XCTAssertTrue(app.staticTexts["Invitation accepted. The player can now approve sharing."].waitForExistence(timeout:10))
    }
    func testCoachInvitationLeadsToPlayerSharingChoice() {
        let app=openResponse("accept",fromCoach:true)
        XCTAssertTrue(revealPhoneElement(app.buttons["Approve and start sharing"],in:app).waitForExistence(timeout:10))
        XCTAssertFalse(app.staticTexts["Sharing permission saved."].exists)
    }
    func testWebAcceptCompletesWithoutAnotherAcceptOrEnableStep() {
        let app=openResponse("accept")
        XCTAssertTrue(app.staticTexts["Invitation accepted. The player can now approve sharing."].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["Enable Connect"].exists)
        XCTAssertFalse(app.buttons["Accept invitation"].exists)
    }
    func testWebDeclineCompletesWithoutAnotherDeclineOrEnableStep() {
        let app=openResponse("decline")
        XCTAssertTrue(app.staticTexts["Invitation declined. Nothing is shared."].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["Enable Connect"].exists)
        XCTAssertFalse(app.buttons["Decline invitation"].exists)
    }
    func testExpiredInvitationKeepsErrorAndRetryReachable() {
        let app=openResponse("accept",expired:true)
        XCTAssertTrue(app.staticTexts["This invitation has expired. Ask the sender for a new invitation."].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["Try again"].isHittable)
        XCTAssertTrue(app.buttons["Not now"].isHittable)
        XCTAssertFalse(app.staticTexts["Invitation accepted. The player can now approve sharing."].exists)
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
