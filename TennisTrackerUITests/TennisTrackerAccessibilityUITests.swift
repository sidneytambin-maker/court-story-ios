import XCTest

final class TennisTrackerAccessibilityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset-store"]
        app.launch()
    }

    func testOnboardingCanCreateProfileAndTabsActivate() throws {
        XCTAssertTrue(app.buttons["setupProfileButton"].waitForExistence(timeout: 5))
        app.buttons["setupProfileButton"].tap()

        let nameField = app.textFields["playerNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Sidney")

        continueOnboarding(to: "Choose Tennis Details")
        continueOnboarding(to: "Choose Preferences")
        finishOnboarding()

        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 5))
        for destination in ["Matches", "Tournaments", "Training", "Player", "Dashboard"] {
            openDestination(destination)
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5), "Missing destination \(destination)")
        }
    }

    func testSettingsSaveActivates() throws {
        completeOnboarding()
        openDestination("Settings")
        let save = app.buttons["settingsToolbarSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts["Settings saved."].waitForExistence(timeout: 5))
    }

    func testPrivacyPolicyIsReadableBeforeSetupAndInSettings() {
        let policy = app.buttons["onboardingPrivacyPolicyLink"]
        XCTAssertTrue(policy.waitForExistence(timeout: 5))
        policy.tap()
        XCTAssertTrue(app.staticTexts["privacyPolicySummary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Privacy Policy"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["setupProfileButton"].waitForExistence(timeout: 5))
        completeOnboarding()
        openDestination("Settings")
        tapPossiblyScrolledButton("privacyPolicyLink")
        XCTAssertTrue(app.staticTexts["privacyPolicySummary"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    func testImportantLiveScoringControlsActivate() throws {
        completeOnboarding()
        openDestination("Matches")
        app.buttons["Track Match Scoring"].tap()
        XCTAssertTrue(app.buttons["startConfiguredLiveScoringButton"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "startConfiguredLiveScoringButton").count, 1)
        app.buttons["startConfiguredLiveScoringButton"].tap()
        XCTAssertTrue(app.buttons["playerWinsPointButton"].waitForExistence(timeout: 5))
        app.buttons["playerWinsPointButton"].tap()
        app.buttons["opponentWinsPointButton"].tap()
        tapPossiblyScrolledButton("undoScoreButton")
        tapPossiblyScrolledButton("saveLiveProgressButton")
        tapPossiblyScrolledButton("hearFullScoreButton")
        tapPossiblyScrolledButton("resetScoreButton")
    }

    func testFreshSetupShowsPersonalEmptyDashboardWithoutSeedData() throws {
        completeOnboarding()
        openDestination("Dashboard")
        XCTAssertTrue(app.staticTexts["Welcome, Sidney"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Current activity"].exists)
        XCTAssertFalse(app.staticTexts["No activity in progress."].exists)
        XCTAssertFalse(app.staticTexts["Player One"].exists)
        XCTAssertFalse(app.staticTexts["Practice opponent"].exists)
        for action in ["dashboardFirstMatch", "dashboardFirstTraining", "dashboardFirstTournament"] {
            XCTAssertTrue(app.buttons[action].exists, "Missing first-activity action \(action)")
        }
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["setupProfileButton"].exists, "A completed setup with no activities must not restart")
    }

    func testTournamentAndTrainingCreationAreReachable() throws {
        completeOnboarding()
        openDestination("Tournaments")
        app.buttons["addTournamentButton"].tap()
        let tournamentName = app.textFields["tournamentNameField"]
        XCTAssertTrue(tournamentName.waitForExistence(timeout: 5))
        tournamentName.tap()
        tournamentName.typeText("Regional Open")
        app.buttons["saveTournamentButton"].tap()
        XCTAssertTrue(textContaining("Regional Open").waitForExistence(timeout: 5))

        openDestination("Training")
        app.buttons["addTrainingButton"].tap()
        XCTAssertTrue(app.buttons["trainingTypePicker"].waitForExistence(timeout: 5))
        app.buttons["saveTrainingButton"].tap()
        XCTAssertTrue(textContaining("Singles practice").waitForExistence(timeout: 5))
    }

    func testSportingScreenshots() {
        completeOnboarding()
        for destination in ["Dashboard", "Training", "Matches", "Tournaments"] {
            openDestination(destination)
            XCTAssertTrue(app.navigationBars[destination].waitForExistence(timeout: 5))
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "iPhone \(destination) tennis theme"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testTrainingFocusCanBeChosenChangedAndCancelledIndependentlyOfType() {
        completeOnboarding()
        openDestination("Training")
        app.buttons["addTrainingButton"].tap()
        app.buttons["trainingTypePicker"].tap()
        app.buttons["Doubles practice"].tap()
        let focus = app.buttons["trainingFocusPicker"]
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        XCTAssertEqual(focus.value as? String, "No focus selected")
        focus.tap()
        app.buttons["trainingFocusOption.Serve and return"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(focus.value as? String, "Serve and return")
        app.buttons["saveTrainingButton"].tap()
        let training = app.buttons.matching(NSPredicate(format: "value CONTAINS %@", "Focus: Serve and return")).firstMatch
        XCTAssertTrue(training.waitForExistence(timeout: 5))
        training.tap()
        app.navigationBars.buttons["Edit"].tap()
        app.buttons["trainingFocusPicker"].tap()
        app.buttons["trainingFocusOption.Serves"].tap()
        app.buttons["Done"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(textContaining("Focus: Serve and return").waitForExistence(timeout: 5))
        app.navigationBars.buttons["Edit"].tap()
        app.buttons["trainingFocusPicker"].tap()
        app.buttons["trainingFocusOption.none"].tap()
        app.buttons["trainingFocusOption.Returns"].tap()
        app.buttons["Done"].tap()
        app.buttons["saveTrainingButton"].tap()
        XCTAssertTrue(textContaining("Focus: Returns").waitForExistence(timeout: 5))
        XCTAssertTrue(textContaining("Doubles practice").exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "iPhone training with explicit focus"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTennisSetupAddsCoachAndRegularPartner() throws {
        completeOnboarding()
        openDestination("Settings")
        app.buttons["tennisSetupLink"].tap()
        app.buttons["Coaches"].tap()
        app.buttons["Add Coach"].tap()
        let coachName = app.textFields["Name"]
        XCTAssertTrue(coachName.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        coachName.tap()
        coachName.typeText("Chris")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Chris"].waitForExistence(timeout: 5))
        let coachesNavigation = app.navigationBars["Coaches"]
        XCTAssertTrue(coachesNavigation.waitForExistence(timeout: 5))
        coachesNavigation.buttons.element(boundBy: 0).tap()
        let partners = app.buttons["Regular Doubles Partners"]
        XCTAssertTrue(partners.waitForExistence(timeout: 5))
        partners.tap()
        app.buttons["addPlayerButton"].tap()
        let playerName = app.textFields["playerNameField"]
        XCTAssertTrue(playerName.waitForExistence(timeout: 5))
        playerName.tap()
        playerName.typeText("Jo")
        app.buttons["savePlayerButton"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Jo")).firstMatch.waitForExistence(timeout: 5))
    }

    func testOneSetEditorDoesNotExposeAdditionalSets() throws {
        completeOnboarding()
        openDestination("Matches")
        app.buttons["addMatchButton"].tap()
        let setOne = app.staticTexts["Set 1"]
        for _ in 0..<8 {
            if setOne.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(setOne.exists)
        XCTAssertFalse(app.staticTexts["Set 2"].exists)
        XCTAssertFalse(app.buttons["Sets played"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["addMatchButton"].waitForExistence(timeout: 5))
    }

    func testThemeAndSetupHaveNoDuplicateNavigationControls() throws {
        completeOnboarding()
        openDestination("Settings")
        let theme = app.buttons["settingsThemePicker"]
        for _ in 0..<5 { if theme.isHittable { break }; app.swipeUp() }
        XCTAssertEqual(app.buttons.matching(identifier: "settingsThemePicker").count, 1)
        XCTAssertLessThanOrEqual(app.staticTexts.matching(identifier: "Theme").count, 1)
        for _ in 0..<5 { if app.buttons["tennisSetupLink"].isHittable { break }; app.swipeDown() }
        app.buttons["tennisSetupLink"].tap()
        for destination in ["Players", "Coaches", "Training Venues", "Match Venues"] {
            app.buttons[destination].tap()
            let bar = app.navigationBars[destination]
            XCTAssertTrue(bar.waitForExistence(timeout: 5))
            XCTAssertEqual(bar.buttons.count, 1, "Expected one Back action on \(destination)")
            bar.buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Tennis Setup"].waitForExistence(timeout: 5))
        }
    }

    func testTrainingMultiSelectionIsAnnouncedAndCancelDiscardsDraftPeople() throws {
        completeOnboarding()
        openDestination("Settings")
        app.buttons["tennisSetupLink"].tap()
        app.buttons["Coaches"].tap()
        for name in ["Chris", "Sarah"] {
            app.buttons["Add Coach"].tap()
            let field = app.textFields["Name"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(name)
            app.buttons["Save"].tap()
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 5))
        }
        openDestination("Training")
        app.buttons["addTrainingButton"].tap()
        tapPossiblyScrolledButton("trainingEntryDetails")
        tapPossiblyScrolledButton("Coaches")
        XCTAssertFalse(app.textFields["New coach name"].exists)
        XCTAssertFalse(app.textFields["otherCoachName"].exists)
        for name in ["Chris", "Sarah"] {
            let selected = app.buttons[name]
            XCTAssertTrue(selected.waitForExistence(timeout: 5))
            selected.tap()
            XCTAssertTrue(selected.isSelected)
        }
        app.buttons["Chris"].tap()
        let deselected = NSPredicate { object, _ in (object as? XCUIElement)?.isSelected == false }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: deselected, evaluatedWith: app.buttons["Chris"])], timeout: 3), .completed)
        XCTAssertEqual(app.buttons["Chris"].value as? String, "Not selected")
        app.buttons["Chris"].tap()
        XCTAssertTrue(app.buttons["Chris"].isSelected)
        app.navigationBars["Coaches"].buttons.firstMatch.tap()
        tapPossiblyScrolledButton("Players Present")
        for name in ["Ben", "Lucy"] {
            let field = app.textFields["Other player name"]
            field.tap(); field.typeText(name)
            app.buttons["Add Player"].tap()
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons[name].isSelected)
        }
        app.navigationBars["Players Present"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["saveTrainingButton"].exists)
        app.buttons["Cancel"].tap()
        app.buttons["addTrainingButton"].tap()
        tapPossiblyScrolledButton("trainingEntryDetails")
        tapPossiblyScrolledButton("Coaches")
        XCTAssertTrue(app.buttons["Chris"].exists)
        XCTAssertTrue(app.buttons["Sarah"].exists)
        XCTAssertFalse(app.buttons["Chris"].isSelected)
        XCTAssertFalse(app.buttons["Sarah"].isSelected)
        app.navigationBars["Coaches"].buttons.firstMatch.tap()
        tapPossiblyScrolledButton("Players Present")
        XCTAssertFalse(app.buttons["Ben"].exists)
        XCTAssertFalse(app.buttons["Lucy"].exists)
    }

    func testHistoricalVenueAndSeparateOtherTournamentChoices() {
        launchRegressionData()
        openDestination("Matches")
        app.buttons["addMatchButton"].tap()
        tapPossiblyScrolledButton("matchEntryDetails")
        tapPossiblyScrolledButton("activityVenuePicker")
        XCTAssertTrue(app.buttons["Training Court, Town"].exists)
        XCTAssertTrue(app.buttons["History Court, City"].exists)
        app.buttons["History Court, City"].tap()
        XCTAssertEqual(app.buttons["activityVenuePicker"].value as? String, "History Court, City")
        XCTAssertFalse(app.textFields["otherVenueName"].exists)
        tapPossiblyScrolledButton("activityTournamentPicker")
        XCTAssertTrue(app.buttons["No tournament"].isSelected)
        XCTAssertTrue(app.buttons["Club Open"].exists)
        app.buttons["Other"].tap()
        XCTAssertTrue(app.textFields["otherTournamentName"].exists)
        tapPossiblyScrolledButton("activityTournamentPicker")
        app.buttons["Club Open"].tap()
        XCTAssertEqual(app.buttons["activityTournamentPicker"].value as? String, "Club Open")
        XCTAssertFalse(app.textFields["otherTournamentName"].exists)
        tapPossiblyScrolledButton("activityTournamentPicker")
        app.buttons["No tournament"].tap()
        XCTAssertEqual(app.buttons["activityTournamentPicker"].value as? String, "No tournament")
        XCTAssertFalse(app.textFields["otherTournamentName"].exists)
    }

    func testDashboardCountsTrainingDoublesOnceAndShowsCoach() {
        launchRegressionData()
        let doubles = resultSummary("Doubles matches")
        for _ in 0..<6 { if doubles.exists && doubles.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(doubles.waitForExistence(timeout: 5))
        XCTAssertTrue((doubles.value as? String)?.contains("3 matches. 1 win, 2 losses, 0 draws") == true)
        XCTAssertTrue((doubles.value as? String)?.contains("Includes 3 matches played during training") == true)
        XCTAssertFalse(app.staticTexts["Current activity"].exists)
        XCTAssertFalse(app.staticTexts["Training practice results, all time"].exists)
        tapPossiblyScrolledButton("dashboardInsights")
        let coaching = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ AND value != nil", "One-to-one coaching, coaches: Chris")).firstMatch
        for _ in 0..<6 {
            if coaching.exists && coaching.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(coaching.exists)
        XCTAssertEqual(coaching.value as? String, "1 session, 1 hour.")
        XCTAssertFalse(app.staticTexts["Training types, last 30 days"].exists)
    }

    func testAllThemesAndLargeTextVisualReview() {
        for theme in ["tennis", "classic", "contrast", "large-tennis"] {
            launchRegressionData(theme: theme)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Dashboard \(theme) theme build 26"
            attachment.lifetime = .keepAlways
            add(attachment)
            let doubles = resultSummary("Doubles matches")
            for _ in 0..<6 { if doubles.exists && doubles.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(doubles.exists)
            XCTAssertTrue((doubles.value as? String)?.contains("3 matches. 1 win, 2 losses, 0 draws") == true)
            let detail = XCTAttachment(screenshot: app.screenshot())
            detail.name = "Doubles results \(theme) build 26"
            detail.lifetime = .keepAlways
            add(detail)
        }
    }

    private func resultSummary(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "resultSummary." + title)
            .matching(NSPredicate(format: "value != nil")).firstMatch
    }

    func testSavedVenueAndLocationAreAvailableForTrainingAndTournaments() {
        launchRegressionData()
        for (tab, add) in [("Training", "addTrainingButton"), ("Tournaments", "addTournamentButton")] {
            openDestination(tab); app.buttons[add].tap()
            if tab == "Training" { tapPossiblyScrolledButton("trainingEntryDetails") }
            tapPossiblyScrolledButton("activityVenuePicker")
            app.buttons["Training Court, Town"].tap()
            XCTAssertEqual(app.buttons["activityVenuePicker"].value as? String, "Training Court, Town")
            tapPossiblyScrolledButton("activityLocationPicker")
            app.buttons["Saved Town"].tap()
            XCTAssertEqual(app.buttons["activityLocationPicker"].value as? String, "Saved Town")
            app.buttons["Cancel"].tap()
        }
    }

    func testWeatherKeepsMultipleSelectedConditions() {
        launchRegressionData(); openDestination("Matches")
        app.buttons["addMatchButton"].tap()
        tapPossiblyScrolledButton("matchEntryDetails")
        tapPossiblyScrolledButton("matchCourtSetting"); app.buttons["Outdoors"].tap()
        tapPossiblyScrolledButton("matchWeather")
        for condition in ["Sunny", "Light showers", "Windy"] {
            tapPossiblyScrolledButton(condition)
            XCTAssertTrue(app.buttons[condition].isSelected)
        }
        app.navigationBars["Weather"].buttons.firstMatch.tap()
        XCTAssertEqual(app.buttons["matchWeather"].value as? String, "Sunny, Light showers and Windy")
        app.buttons["matchWeather"].tap()
        for condition in ["Sunny", "Light showers", "Windy"] {
            XCTAssertTrue(revealButton(condition).isSelected)
        }
        tapPossiblyScrolledButton("Windy")
        XCTAssertFalse(app.buttons["Windy"].isSelected)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "iPhone multi-select weather"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testBothHandsPersistsThroughTheSinglePlayerSettingsRoute() {
        completeOnboarding(); openDestination("Settings")
        XCTAssertFalse(app.buttons["Player Defaults"].exists)
        XCTAssertFalse(app.buttons["Players"].exists)
        app.buttons["tennisSetupLink"].tap(); app.buttons["Players"].tap()
        tapPossiblyScrolledButton("editCurrentPlayerButton")
        tapPossiblyScrolledButton("playerHandednessPicker"); app.buttons["Both hands"].tap()
        app.buttons["savePlayerButton"].tap()
        tapPossiblyScrolledButton("editCurrentPlayerButton")
        XCTAssertTrue(app.buttons["playerHandednessPicker"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["playerHandednessPicker"].value as? String, "Both hands")
    }


    func testRecordedTiebreakAndTrainingLinkCanBeEnteredWithPickers() {
        launchMatchUpdateData()
        openDestination("Matches")
        app.buttons["addMatchButton"].tap()
        app.buttons["activityPersonPicker.Opponent name"].tap()
        app.buttons["Sam"].tap()
        tapPossiblyScrolledButton("matchFormatPicker"); app.buttons["One set"].tap()
        tapPossiblyScrolledButton("matchEntryDetails")
        tapPossiblyScrolledButton("matchTrainingPicker")
        let session = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Coaches: Chris")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5)); session.tap()
        XCTAssertNotEqual(app.buttons["matchTrainingPicker"].value as? String, "No training session")
        tapPossiblyScrolledButton("set1YourGames"); app.buttons["6 games"].tap()
        tapPossiblyScrolledButton("set1OpponentGames"); app.buttons["6 games"].tap()
        tapPossiblyScrolledButton("set1YourTiebreak"); app.buttons["7 points"].tap()
        tapPossiblyScrolledButton("set1OpponentTiebreak"); app.buttons["5 points"].tap()
        XCTAssertTrue(app.staticTexts["recordedScoreSummary"].label.contains("Win"))
        app.buttons["saveMatchButton"].tap()
        let score = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "tie-break: your 7 points", "tie-break: your 7 points")).firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 5))
    }

    func testDashboardFocusRepairOpensChoicesAndGoalsCanBeSaved() {
        launchMatchUpdateData()
        tapPossiblyScrolledButton("dashboardInsights")
        tapPossiblyScrolledButton("dashboardChooseFocus")
        XCTAssertTrue(app.buttons["trainingFocusOption.Serves"].waitForExistence(timeout: 5))
        app.buttons["trainingFocusOption.Serves"].tap()
        app.buttons["trainingFocusOption.Returns"].tap()
        XCTAssertTrue(app.buttons["trainingFocusOption.Serves"].isSelected)
        XCTAssertTrue(app.buttons["trainingFocusOption.Returns"].isSelected)
        app.buttons["saveDashboardFocus"].tap()
        XCTAssertFalse(app.buttons["dashboardChooseFocus"].exists)
        tapPossiblyScrolledButton("dashboardEditGoals")
        let goal = app.descendants(matching: .any).matching(identifier: "personalGoalField").firstMatch
        XCTAssertTrue(goal.waitForExistence(timeout: 5)); goal.tap(); goal.typeText("Improve second serve")
        app.buttons["savePlayerGoals"].tap()
        XCTAssertTrue(textContaining("Improve second serve").waitForExistence(timeout: 5))
        tapPossiblyScrolledButton("dashboardReviewMatch")
        let match = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sam")).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 5)); match.tap()
        let priority = app.descendants(matching: .any).matching(identifier: "matchReviewPriorityField").firstMatch
        XCTAssertTrue(priority.waitForExistence(timeout: 5)); priority.tap(); priority.typeText("Return depth")
        app.buttons["saveMatchReview"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(textContaining("Return depth").waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "iPhone actionable goals and focus dashboard"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    private func launchMatchUpdateData() {
        app.terminate()
        app.launchArguments = ["-ui-testing-reset-store", "-ui-testing-venue-dashboard", "-ui-testing-match-update"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 10))
    }

    private func launchRegressionData(theme: String = "tennis") {
        app.terminate()
        app.launchArguments = ["-ui-testing-reset-store", "-ui-testing-venue-dashboard", "-ui-theme-\(theme)"]
        if theme == "large-tennis" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 10))
    }

    private func completeOnboarding() {
        XCTAssertTrue(app.buttons["setupProfileButton"].waitForExistence(timeout: 15))
        app.buttons["setupProfileButton"].tap()
        let nameField = app.textFields["playerNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Sidney")
        continueOnboarding(to: "Choose Tennis Details")
        continueOnboarding(to: "Choose Preferences")
        finishOnboarding()
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 15))
    }

    private func openDestination(_ name: String) {
        if name == "Player" {
            app.tabBars.buttons["Settings"].tap()
            app.buttons["tennisSetupLink"].tap()
            app.buttons["Players"].tap()
            return
        }
        let visibleTab = app.tabBars.buttons[name]
        if visibleTab.waitForExistence(timeout: 2) {
            visibleTab.tap()
            return
        }
        XCTFail("Missing tab for \(name)")
    }

    private func tapPossiblyScrolledButton(_ identifier: String) {
        revealButton(identifier).tap()
    }

    private func revealButton(_ identifier: String) -> XCUIElement {
        let button = app.buttons[identifier]
        for _ in 0..<8 { if button.isHittable { break }; app.swipeUp() }
        if !button.isHittable {
            for _ in 0..<16 { if button.isHittable { break }; app.swipeDown() }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing button \(identifier)")
        XCTAssertTrue(button.isHittable, "Button \(identifier) is not available for interaction")
        return button
    }

    private func textContaining(_ text: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func continueOnboarding(to heading: String) {
        tapPossiblyScrolledButton("onboardingContinueButton")
        XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 15))
    }

    private func finishOnboarding() {
        for heading in ["People and Places", "Your Apple Watch", "Activity Reminders", "Optional Health Workouts", "Ready for Tennis"] {
            continueOnboarding(to: heading)
        }
        tapPossiblyScrolledButton("onboardingFinishButton")
    }
}
