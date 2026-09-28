import XCTest

final class TennisTrackerWatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(page: String, completedTraining: Bool = false, accessibleNavigation: Bool = false, scheduledTraining: Bool = false, activeMatch: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-watch", "-watch-page=\(page)"]
        if completedTraining { app.launchArguments.append("-watch-completed-training") }
        if accessibleNavigation { app.launchArguments.append("-watch-accessibility-navigation") }
        if scheduledTraining { app.launchArguments.append("-watch-scheduled-training") }
        if activeMatch { app.launchArguments.append("-watch-active-match") }
        app.launch()
        return app
    }

    func testFivePagesHaveDistinctHeadings() {
        for page in ["Overview", "Track", "Live", "Recent", "Score"] {
            let app = launch(page: page)
            XCTAssertTrue(app.staticTexts[page].waitForExistence(timeout: 10) || app.navigationBars[page].exists)
            if page == "Track" {
                XCTAssertTrue(app.buttons["Track Training Session"].exists)
                XCTAssertFalse(app.buttons["Record Point for Alex"].exists)
            }
            if page == "Live" { XCTAssertTrue(app.staticTexts["No tennis activity in progress."].exists) }
            app.terminate()
        }
    }

    func testMenuPrivacyPolicyReadsOfflineAndReturns() {
        let app = launch(page: "Overview", accessibleNavigation: true)
        let menu = app.buttons.matching(identifier: "watchScreenMenu")
            .matching(NSPredicate(format: "value BEGINSWITH %@", "Current screen:")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let policy = app.buttons["watchPrivacyPolicyLink"]
        reveal(policy, in: app)
        policy.tap()
        XCTAssertTrue(app.staticTexts["privacyPolicySummary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Privacy Policy"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Menu"].waitForExistence(timeout: 5))
    }

    func testTrainingDrillDownSupportsMultiSelectionWithoutExtraCancel() {
        let app = launch(page: "Track")
        app.buttons["Track Training Session"].tap()
        XCTAssertFalse(app.buttons["Cancel"].exists)
        reveal(app.buttons["Coaches"], in: app)
        let navigationStart = Date()
        app.buttons["Coaches"].tap()
        for name in ["Chris", "Sarah"] {
            let toggle = app.buttons[name]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            toggle.tap()
            XCTAssertTrue(toggle.isSelected)
        }
        XCTAssertLessThan(Date().timeIntervalSince(navigationStart), 20, "Coach selection must not stall during navigation")
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertLessThanOrEqual(app.buttons.matching(identifier: "Back").count, 1)
        capture(app, name: "Watch selected coaches");
        app.navigationBars["Coaches"].buttons.firstMatch.tap()
        app.buttons["Coaches"].tap()
        XCTAssertTrue(app.buttons["Chris"].isSelected)
        XCTAssertTrue(app.buttons["Sarah"].isSelected)
    }

    func testCompletedWorkoutHasOnePreciseFitnessSummaryAndEditorCancel() {
        let app = launch(page: "Live", completedTraining: true)
        let summary = app.buttons["Completed training summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.label.contains("2 minutes 39 seconds"))
        XCTAssertTrue(summary.label.contains("72 beats per minute"))
        XCTAssertTrue(summary.label.contains("201 steps"))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Average heart rate")).count, 1)
        reveal(app.buttons["Edit Training and Focus"], in: app)
        app.buttons["Edit Training and Focus"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("2 minutes 39 seconds"))
    }

    func testNewWatchTrainingAsksForFocusAndKeepsTheSelection() {
        let app = launch(page: "Track", accessibleNavigation: true)
        app.buttons["Track Training Session"].tap()
        let focus = app.buttons["trainingFocusPicker"]
        reveal(focus, in: app)
        XCTAssertEqual(focus.value as? String, "No focus selected")
        focus.tap()
        app.buttons["trainingFocusOption.Returns"].tap()
        app.buttons["trainingFocusOption.Serves"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(focus.value as? String, "Returns and Serves")
        capture(app, name: "Watch explicit training focus")
    }

    func testCompletedWorkoutCanBeMarkedCompleteOnWatch() {
        let app = launch(page: "Live", completedTraining: true)
        let complete = app.buttons["Review and Complete Training"]
        reveal(complete, in: app)
        complete.tap()
        XCTAssertTrue(app.buttons["trainingFocusPicker"].waitForExistence(timeout: 5))
        app.buttons["trainingFocusPicker"].tap()
        app.buttons["trainingFocusOption.Serves"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(complete.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Completed training summary"].label.contains("72 beats per minute"))
        XCTAssertTrue(app.buttons["Completed training summary"].label.contains("Focus: Serves"))
    }

    func testWatchDurationCorrectionKeepsOriginalHealthWindow() {
        let app = launch(page: "Live", completedTraining: true)
        reveal(app.buttons["Edit Training and Focus"], in: app)
        app.buttons["Edit Training and Focus"].tap()
        let hours = app.buttons["durationHours"]
        reveal(hours, in: app); hours.tap()
        let twoHours = app.buttons["2 hours"]
        reveal(twoHours, in: app); twoHours.tap()
        let minutes = app.buttons["durationMinutes"]
        reveal(minutes, in: app); minutes.tap()
        let zeroMinutes = app.buttons["0 minutes"]
        reveal(zeroMinutes, in: app); zeroMinutes.tap()
        app.buttons["Save"].tap()
        let summary = app.buttons["Completed training summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("2 hours"))
        XCTAssertTrue(summary.label.contains("original 2 minutes 39 seconds recording"))
        XCTAssertTrue(summary.label.contains("72 beats per minute"))
        XCTAssertTrue(summary.label.contains("201 steps"))
        capture(app, name: "Watch edited duration with original Health measurements")
    }

    func testActiveWatchEditorDoesNotOfferDurationOverride() {
        let app = launch(page: "Track", scheduledTraining: true)
        app.buttons["Track Training Session"].tap()
        reveal(app.buttons["Start Session"], in: app)
        app.buttons["Start Session"].tap()
        XCTAssertTrue(app.buttons["Active training summary"].waitForExistence(timeout: 10))
        reveal(app.buttons["Edit Training and Focus"], in: app)
        app.buttons["Edit Training and Focus"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["durationHours"].exists)
        XCTAssertFalse(app.buttons["durationMinutes"].exists)
        app.buttons["Save"].tap()
        let summary = app.buttons["Active training summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("elapsed"))
        XCTAssertFalse(app.buttons["Completed training summary"].exists)
    }

    func testWatchDeleteCancelKeepsTrainingAndConfirmationRemovesIt() {
        let app = launch(page: "Live", completedTraining: true)
        reveal(app.buttons["Delete"], in: app)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Completed training summary"].exists)
        reveal(app.buttons["Delete"], in: app)
        app.buttons["Delete"].tap()
        reveal(app.buttons["Confirm activity deletion"], in: app)
        app.buttons["Confirm activity deletion"].tap()
        XCTAssertTrue(app.staticTexts["No tennis activity in progress."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Completed training summary"].exists)
    }

    func testAccessibleNavigationHasOnePageAndNoDuplicateActionButtons() {
        let app = launch(page: "Live", completedTraining: true, accessibleNavigation: true)
        XCTAssertTrue(app.buttons["Completed training summary"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Edit Training and Focus"].exists)
        XCTAssertFalse(app.buttons["Review and Complete Training"].exists)
        XCTAssertFalse(app.buttons["Delete"].exists)
        XCTAssertFalse(app.buttons["View Details"].exists)
        XCTAssertFalse(app.buttons["Track Training Session"].exists)
        app.buttons["Completed training summary"].tap()
        XCTAssertTrue(app.navigationBars["Summary"].waitForExistence(timeout: 5))
        let details = app.staticTexts["watchActivityDetailsSummary"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(details.label.contains("72 beats per minute"))
        capture(app, name: "Watch activated activity summary")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Completed training summary"].waitForExistence(timeout: 5))
    }

    func testEmptyAccessibleLivePageDoesNotExposeAdjacentPages() {
        let app = launch(page: "Live", accessibleNavigation: true)
        for _ in 0..<3 {
            app.swipeDown()
            XCTAssertTrue(app.staticTexts["No tennis activity in progress."].exists)
            XCTAssertFalse(app.buttons["Track Training Session"].exists)
        }
        XCTAssertTrue(app.buttons["Menu"].exists)
        capture(app, name: "Watch empty Live with accessible navigation")
    }

    func testLiveScoreKeepsPointButtonsAndHidesDuplicateRotorActions() {
        let app = launch(page: "Score", accessibleNavigation: true, activeMatch: true)
        let score = app.buttons["Current match score"]
        XCTAssertTrue(score.waitForExistence(timeout: 10))
        XCTAssertTrue((score.value as? String)?.contains("Alex against Sam") == true)
        capture(app, name: "Watch live score ready")
        for name in ["Alex", "Sam"] {
            reveal(app.buttons["Record Point for \(name)"], in: app)
            XCTAssertTrue(app.buttons["Record Point for \(name)"].isHittable)
        }
        for _ in 0..<6 {
            for title in ["Edit Match", "Delete", "Finish Match", "Save Match Progress", "Undo Last Point", "Start Tie-break"] {
                XCTAssertFalse(app.buttons[title].exists)
            }
            scrollUp(in: app)
        }
        capture(app, name: "Watch live score with rotor actions")
    }

    func testScheduledQuickStartShowsSavedDetailsWithoutStartingOnOpen() {
        let app = launch(page: "Track", scheduledTraining: true)
        app.buttons["Track Training Session"].tap()
        XCTAssertTrue(app.staticTexts["Scheduled training preview"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Scheduled training preview"].label.contains("Coaches: Chris"))
        XCTAssertFalse(app.buttons["Active training summary"].exists)
        reveal(app.buttons["Start Session"], in: app)
        capture(app, name: "Watch scheduled training ready to start")
        app.buttons["Start Session"].tap()
        XCTAssertTrue(app.buttons["Active training summary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Active training summary"].label.contains("Coaches: Chris"))
    }

    func testEndWorkoutIsAVisibleAccessibleButtonOnLiveAndCancelKeepsItRunning() {
        let app = launch(page: "Track", accessibleNavigation: true, scheduledTraining: true)
        app.buttons["Track Training Session"].tap()
        reveal(app.buttons["Start Session"], in: app)
        app.buttons["Start Session"].tap()
        let end = app.buttons["endTrainingWorkout"]
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        reveal(end, in: app)
        end.tap()
        let close = app.buttons["AX_ActionContentControllerCancelButton"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        XCTAssertTrue(app.buttons["Active training summary"].exists)
        end.tap()
        let confirm = app.buttons["End Workout and Save"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["Completed training summary"].waitForExistence(timeout: 10))
        XCTAssertFalse(end.exists)
        XCTAssertFalse(app.buttons["Active training summary"].exists)
        capture(app, name: "Watch workout ended through accessible button")
    }

    func testEditingTrainingListsSavedCoachesAndOtherDoesNotOpenByDefault() {
        let app = launch(page: "Live", completedTraining: true)
        reveal(app.buttons["Edit Training and Focus"], in: app)
        app.buttons["Edit Training and Focus"].tap()
        reveal(app.buttons["trainingCoachPicker"], in: app)
        app.buttons["trainingCoachPicker"].tap()
        XCTAssertFalse(app.textFields["otherCoachName"].exists)
        for name in ["Chris", "Sarah"] {
            reveal(app.buttons[name], in: app)
            app.buttons[name].tap()
            XCTAssertTrue(app.buttons[name].isSelected)
        }
        let other = app.switches["otherCoachToggle"]
        reveal(other, in: app); other.tap()
        reveal(app.textFields["otherCoachName"], in: app)
        XCTAssertTrue(app.textFields["otherCoachName"].exists)
        capture(app, name: "Watch saved and one-off coach choices")
    }

    func testRecentDoesNotExposeEmptySectionHeadings() {
        let app = launch(page: "Recent", accessibleNavigation: true)
        XCTAssertTrue(app.staticTexts["No recent activity"].waitForExistence(timeout: 5))
        for header in ["Matches", "Training", "Tournaments", "Needs Details"] {
            XCTAssertFalse(app.staticTexts[header].exists)
        }
    }

    func testTrackSeparatesRecordingResultsAndManagingTournaments() {
        let app = launch(page: "Track")
        reveal(app.buttons["Record Match Result"], in: app)
        app.buttons["Record Match Result"].tap()
        XCTAssertTrue(app.navigationBars["Record Match Result"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Record Point for Alex"].exists)
        app.navigationBars["Record Match Result"].buttons.firstMatch.tap()
        reveal(app.buttons["Manage Tournaments"], in: app)
        app.buttons["Manage Tournaments"].tap()
        XCTAssertTrue(app.buttons["Add Tournament"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Track Tournament"].exists)
        capture(app, name: "Watch tournament management")
    }

    func testSportingLayoutsForVisualReview() {
        for page in ["Track", "Score", "Live"] {
            let app = launch(page: page, completedTraining: page == "Live")
            capture(app, name: "Watch \(page)")
            app.terminate()
        }
    }

    func testMenuIsAButtonAndChangesScreensWithoutASlider() {
        let app = launch(page: "Live", accessibleNavigation: true)
        let menu = app.buttons.matching(identifier: "watchScreenMenu").matching(NSPredicate(format: "value BEGINSWITH %@", "Current screen:")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertEqual(app.sliders.count, 0)
        menu.tap()
        app.buttons["Track"].tap()
        XCTAssertTrue(app.buttons["Track Training Session"].waitForExistence(timeout: 5))
        XCTAssertEqual(menu.value as? String, "Current screen: Track")
        capture(app, name: "Watch Menu destination")
    }

    func testLiveMatchVenueAndSeparateTournamentChoices() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-watch", "-watch-page=Track", "-watch-venue-regression"]
        app.launch()
        app.buttons["Live Score a Match"].tap()
        let venue = app.buttons["activityVenuePicker"]
        reveal(venue, in: app); venue.tap()
        XCTAssertTrue(app.buttons["Training Court, Town"].exists)
        XCTAssertTrue(app.buttons["History Court, City"].exists)
        app.buttons["History Court, City"].tap()
        XCTAssertEqual(venue.value as? String, "History Court, City")
        XCTAssertFalse(app.textFields["otherVenueName"].exists)
        let tournament = app.buttons["activityTournamentPicker"]
        reveal(tournament, in: app); tournament.tap()
        XCTAssertTrue(app.buttons["No tournament"].isSelected)
        XCTAssertTrue(app.buttons["Club Open"].exists)
        reveal(app.buttons["Other"], in: app); app.buttons["Other"].tap()
        reveal(app.textFields["otherTournamentName"], in: app)
        XCTAssertTrue(app.textFields["otherTournamentName"].exists)
        capture(app, name: "Watch Other tournament entry")
        reveal(tournament, in: app); tournament.tap()
        app.buttons["Club Open"].tap()
        XCTAssertEqual(tournament.value as? String, "Club Open")
        XCTAssertFalse(app.textFields["otherTournamentName"].exists)
        reveal(tournament, in: app); tournament.tap()
        app.buttons["No tournament"].tap()
        XCTAssertEqual(tournament.value as? String, "No tournament")
        XCTAssertFalse(app.textFields["otherTournamentName"].exists)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSavedVenuesAndLocationsAreAvailableInTrainingAndTournamentEditors() {
        for route in ["Track Training Session", "Manage Tournaments"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing-watch", "-watch-page=Track", "-watch-venue-regression"]
            app.launch()
            reveal(app.buttons[route], in: app); app.buttons[route].tap()
            if route == "Manage Tournaments" { app.buttons["Add Tournament"].tap() }
            let venue = app.buttons["activityVenuePicker"]
            reveal(venue, in: app); venue.tap()
            app.buttons["Training Court, Town"].tap()
            XCTAssertEqual(venue.value as? String, "Training Court, Town")
            let location = app.buttons["activityLocationPicker"]
            reveal(location, in: app); location.tap()
            app.buttons["Saved Town"].tap()
            XCTAssertEqual(location.value as? String, "Saved Town")
            capture(app, name: "Watch saved venue in \(route)")
            app.terminate()
        }
    }

    func testManualMatchResultSavesWithoutStartingLiveScoringAndWeatherAllowsMultipleChoices() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-watch", "-watch-page=Track", "-watch-manual-match"]
        app.launch()
        reveal(app.buttons["Record Match Result"], in: app); app.buttons["Record Match Result"].tap()
        reveal(app.buttons["activityPersonPicker.Opponent"], in: app); app.buttons["activityPersonPicker.Opponent"].tap()
        app.buttons["Sam"].tap()
        reveal(app.buttons["matchCourtSetting"], in: app); app.buttons["matchCourtSetting"].tap()
        app.buttons["Outdoors"].tap()
        reveal(app.buttons["matchWeather"], in: app); app.buttons["matchWeather"].tap()
        for condition in ["Sunny", "Light showers", "Windy"] {
            reveal(app.buttons[condition], in: app); app.buttons[condition].tap()
            XCTAssertTrue(app.buttons[condition].isSelected)
        }
        capture(app, name: "Watch multiple weather selections")
        app.navigationBars["Weather"].buttons.firstMatch.tap()
        XCTAssertEqual(app.buttons["matchWeather"].value as? String, "Sunny, Light showers and Windy")
        reveal(app.buttons["saveRecordedMatch"], in: app); app.buttons["saveRecordedMatch"].tap()
        let menu = app.buttons.matching(identifier: "watchScreenMenu")
            .matching(NSPredicate(format: "value BEGINSWITH %@", "Current screen:")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap(); reveal(app.buttons["Recent"], in: app); app.buttons["Recent"].tap()
        let summary = app.buttons["Match summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("Sam"))
        XCTAssertTrue(summary.label.contains("Weather: Sunny, Light showers and Windy"))
        XCTAssertFalse(app.buttons["Current match score"].exists)
        capture(app, name: "Watch manually recorded completed match")
    }


    func testRecordedWatchTiebreakAndTrainingLinkPersist() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-watch", "-watch-page=Track", "-watch-manual-match", "-watch-scheduled-training"]
        app.launch()
        app.buttons["Record Match Result"].tap()
        app.buttons["activityPersonPicker.Opponent"].tap(); app.buttons["Sam"].tap()
        reveal(app.buttons["matchTrainingPicker"], in: app)
        XCTAssertEqual(app.buttons["matchTrainingPicker"].value as? String, "No training session")
        app.buttons["matchTrainingPicker"].tap()
        let session = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Coaches: Chris")).firstMatch
        reveal(session, in: app); session.tap()
        let format = app.descendants(matching: .any).matching(identifier: "matchFormatPicker").firstMatch
        reveal(format, in: app); format.tap()
        app.buttons["One set"].tap()
        closeNativePicker(in: app)
        chooseRecordedScore("set1YourGames", value: "6 games", in: app)
        chooseRecordedScore("set1OpponentGames", value: "6 games", in: app)
        chooseRecordedScore("set1YourTiebreak", value: "7 points", in: app)
        chooseRecordedScore("set1OpponentTiebreak", value: "5 points", in: app)
        reveal(app.buttons["saveRecordedMatch"], in: app); app.buttons["saveRecordedMatch"].tap()
        let menu = app.buttons.matching(identifier: "watchScreenMenu")
            .matching(NSPredicate(format: "value BEGINSWITH %@", "Current screen:")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5)); menu.tap()
        reveal(app.buttons["Recent"], in: app); app.buttons["Recent"].tap()
        let summary = app.buttons["Match summary"]
        reveal(summary, in: app)
        XCTAssertTrue(summary.label.contains("tie-break: your 7 points, opponent 5 points"))
        capture(app, name: "Watch recorded tie-break result")
    }

    func testNotificationReflectionOpensExactCompletedSessionOnWatch() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-watch", "-watch-completed-training", "-test-notification=reflection"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Training Reflection"].waitForExistence(timeout: 8))
        let focus = app.buttons["trainingFocusPicker"]
        reveal(focus, in: app); XCTAssertTrue(focus.isHittable)
        let save = app.buttons["saveTrainingReflection"]
        reveal(save, in: app); save.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "watchScreenMenu").matching(NSPredicate(format: "value BEGINSWITH %@", "Current screen:")).firstMatch.waitForExistence(timeout: 8))
        capture(app, name: "Watch notification reflection saved")
    }

    func testNotificationResultOpensScorePickersOnWatch() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-watch", "-watch-venue-regression", "-test-notification=result"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Match Result"].waitForExistence(timeout: 8))
        let score = app.descendants(matching: .any).matching(identifier: "set1YourGames").firstMatch
        reveal(score, in: app); XCTAssertTrue(score.isHittable)
        capture(app, name: "Watch exact match result reminder")
    }

    func testMissingWatchNotificationRequestsExactActivityWithoutOpeningAnother() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-watch", "-test-notification=missing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["notificationActivityUnavailable"].waitForExistence(timeout: 8))
        let retry = app.buttons["Request Activity Again"]
        reveal(retry, in: app); retry.tap()
        XCTAssertFalse(app.buttons["saveTrainingReflection"].exists)
    }

    func testWatchMenuSoundPreviewAndAchievementCollection() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-watch", "-watch-completed-training"]
        app.launch()
        let menu = app.buttons.matching(identifier: "watchScreenMenu").matching(NSPredicate(format: "value BEGINSWITH %@", "Current screen:")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 8)); menu.tap()
        let preview = app.buttons["watchPreviewTennisSound"]
        reveal(preview, in: app); preview.tap()
        XCTAssertEqual(preview.value as? String, "Tennis bounce")
        XCTAssertFalse(app.staticTexts["watchSoundPreviewFailed"].exists)
        let achievements = app.buttons["watchMenuAchievements"]
        reveal(achievements, in: app); achievements.tap()
        XCTAssertTrue(app.staticTexts["achievementCollectionSummary"].waitForExistence(timeout: 8))
        capture(app, name: "Watch achievements collection")
    }

    private func chooseRecordedScore(_ identifier: String, value: String, in app: XCUIApplication) {
        let control = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        reveal(control, in: app); control.tap()
        reveal(app.buttons[value], in: app); app.buttons[value].tap()
        closeNativePicker(in: app)
    }

    private func closeNativePicker(in app: XCUIApplication) {
        // watchOS keeps native Picker sheets open after a value is selected.
        let close = app.buttons.matching(identifier: "close-sheet").firstMatch
        if close.waitForExistence(timeout: 1) {
            close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        }
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var upward = true
        var previousVisibleRows = ""
        for _ in 0..<60 {
            let upperEdge = max(app.frame.minY + 40, app.navigationBars.firstMatch.frame.maxY) + 8
            let lowerEdge = app.frame.maxY - 32
            if element.exists {
                let center = element.frame.midY
                if element.isHittable && center > upperEdge && center < lowerEdge { return }
                upward = center >= (upperEdge + lowerEdge) / 2
            } else {
                let rows = app.cells.allElementsBoundByIndex.filter { $0.frame.intersects(app.frame) }
                    .map { "\($0.label):\(Int($0.frame.minY))" }.joined(separator: "|")
                if !rows.isEmpty && rows == previousVisibleRows { upward.toggle() }
                previousVisibleRows = rows
            }
            scroll(in: app, upward: upward)
        }
        print(app.debugDescription)
        XCTFail("Could not reveal \(element) after searching both directions")
    }

    private func scrollUp(in app: XCUIApplication) {
        scroll(in: app, upward: true)
    }

    private func scroll(in app: XCUIApplication, upward: Bool) {
        if let list = app.scrollViews.allElementsBoundByIndex.last(where: { $0.isHittable })
            ?? app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable }) {
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.8 : 0.45))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.45 : 0.8))
            // Holding at the end prevents inertial flings from skipping short Watch rows.
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        } else {
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
    }
}
