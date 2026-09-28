import XCTest

final class TennisNotificationsAndAchievementsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset-store", "-ui-testing-venue-dashboard"] + arguments
        app.launch(); return app
    }

    func testColdReflectionNotificationOpensFieldsForExactSessionAndPersists() {
        let app = launch(["-test-notification=reflection"])
        XCTAssertTrue(app.navigationBars["Training Reflection"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["reflectionSessionSummary"].label.contains("Chris"))
        let progress = app.textFields["reflectionProgressField"]
        let field = progress.exists ? progress : app.textViews["reflectionProgressField"]
        reveal(field, in: app); field.tap(); field.typeText("Returns improved today")
        app.buttons["saveTrainingReflection"].tap()
        app.terminate()
        app.launchArguments = ["-test-notification=reflection"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Training Reflection"].waitForExistence(timeout: 8))
        let saved = app.descendants(matching: .any).matching(identifier: "reflectionProgressField").firstMatch
        XCTAssertTrue((saved.value as? String ?? "").contains("Returns improved today"))
        capture(app, "iPhone exact training reflection")
    }

    func testWarmReminderMovesFromDashboardDirectlyToReflection() {
        let app = launch(["-test-notification=reflection", "-test-notification-warm"])
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 8))
        app.buttons["openTestReminder"].tap()
        XCTAssertTrue(app.navigationBars["Training Reflection"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reflectionProgressField").firstMatch.exists)
    }

    func testResultReminderOpensScorePickersInsteadOfMatchList() {
        let app = launch(["-test-notification=result"])
        XCTAssertTrue(app.navigationBars["Match Result"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["notificationMatchSummary"].exists)
        let score = app.descendants(matching: .any).matching(identifier: "set1YourGames").firstMatch
        reveal(score, in: app); XCTAssertTrue(score.isHittable)
        XCTAssertTrue(app.buttons["saveNotificationMatchResult"].exists)
        capture(app, "iPhone notification match result")
    }

    func testDeletedReminderExplainsUnavailableWithoutOpeningAnotherSession() {
        let app = launch(["-test-notification=missing"])
        XCTAssertTrue(app.staticTexts["notificationActivityUnavailable"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["saveTrainingReflection"].exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 5))
    }

    func testTournamentAndWeeklyNotificationsOpenTheirSpecificArea() {
        var app = launch(["-test-notification=tournament"])
        XCTAssertTrue(app.navigationBars["Club Open"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Club Open")).firstMatch.exists)
        app.terminate()
        app = launch(["-test-notification=weekly"])
        XCTAssertTrue(app.navigationBars["Weekly Review"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["notificationWeekRange"].exists)
    }

    func testAllFiveSoundChoicesPreviewAndPersistWithoutExplicitSettingsSave() {
        let app = launch()
        openSounds(in: app)
        for id in ["bounce", "racketStrike", "racketSwing", "ballCan", "applause"] {
            let choice = app.buttons["tennisSound." + id]
            reveal(choice, in: app); choice.tap()
            XCTAssertEqual(choice.value as? String, "Selected")
            XCTAssertFalse(app.staticTexts["soundPreviewFailed"].exists)
        }
        capture(app, "Five independent tennis sounds")
        app.terminate(); app.launchArguments = []; app.launch()
        openSounds(in: app)
        let selected = app.buttons["tennisSound.applause"]
        reveal(selected, in: app); XCTAssertEqual(selected.value as? String, "Selected")
        selected.tap(); XCTAssertFalse(app.staticTexts["soundPreviewFailed"].exists)
    }

    func testAchievementBadgesAndDashboardChartsAcrossThemes() {
        for theme in ["", "-ui-theme-classic", "-ui-theme-contrast"] {
            let app = launch(theme.isEmpty ? [] : [theme])
            XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "resultSummary.Doubles matches").matching(NSPredicate(format: "value != nil")).firstMatch.exists)
            capture(app, "Dashboard charts " + theme)
            let link = app.descendants(matching: .any).matching(identifier: "achievementsLink").firstMatch
            reveal(link, in: app); link.tap()
            XCTAssertTrue(app.staticTexts["achievementCollectionSummary"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["achievementCollectionSummary"].label.contains("of 22"))
            let target = app.staticTexts["achievement.training.10"]
            reveal(target, in: app)
            XCTAssertTrue((target.value as? String ?? "").contains("2 of 10"))
            capture(app, "Achievement badges " + theme)
            app.terminate()
        }
    }

    func testLargeTextAchievementBadgesRemainAccessible() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let link = app.descendants(matching: .any).matching(identifier: "achievementsLink").firstMatch
        reveal(link, in: app); link.tap()
        let target = app.staticTexts["achievement.training.10"]
        reveal(target, in: app); XCTAssertTrue(target.isHittable)
        capture(app, "Achievements accessibility text size")
    }

    private func openSounds(in app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Settings"].tap()
        let notifications = app.buttons["notificationSettingsLink"]
        reveal(notifications, in: app); notifications.tap()
        app.buttons["tennisSoundChoices"].tap()
        XCTAssertTrue(app.buttons["tennisSound.bounce"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<25 {
            if element.exists && element.isHittable && element.frame.midY < app.frame.maxY - 75 { return }
            app.swipeUp()
        }
        XCTFail("Could not reach \(element)")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
