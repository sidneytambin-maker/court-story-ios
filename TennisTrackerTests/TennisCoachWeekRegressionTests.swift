import XCTest
@testable import TennisTracker

final class TennisCoachWeekRegressionTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var sundayFirstCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.firstWeekday = 1
        return calendar
    }

    func testSavedCoachesContextAndBothHandsSurvivePhoneAndWatchRoundTrips() throws {
        var data = AppData()
        var player = PlayerProfile(); player.name = "Alex"; player.playingHand = "Both hands"
        data.players = [player]; data.selectedPlayerID = player.id
        data.setup.coaches = (1...6).map { TennisCoach(name: "Coach \($0)") }
        data.setup.venues = (1...12).map { TennisVenue(name: "Court \($0)", town: "Town \($0)") }
        data.setup.locations = [TennisLocation(name: "Test location")]
        var session = TrainingSession(playerID: player.id)
        session.context.coachIDs = [data.setup.coaches[0].id, data.setup.coaches[5].id]
        session.context.otherCoachName = "Visiting coach"
        session.context.captureLegacyNames(coaches: data.setup.coaches, players: data.players)
        data.trainingSessions = [session]
        data.deletedRecordIDs = [UUID()]
        let reloaded = try JSONDecoder.tennisTracker.decode(AppData.self, from: JSONEncoder.tennisTracker.encode(data))
        let snapshot = TennisWatchSnapshot(data: reloaded)
        let wire = try JSONDecoder.tennisTracker.decode(TennisWatchSnapshot.self, from: JSONEncoder.tennisTracker.encode(snapshot))
        XCTAssertEqual(wire.setup.coaches, data.setup.coaches)
        XCTAssertEqual(wire.setup.venues, data.setup.venues)
        XCTAssertEqual(wire.setup.locations, data.setup.locations)
        XCTAssertEqual(wire.availableVenueChoices.count, 12)
        XCTAssertEqual(wire.trainingSessions[0].context, session.context)
        XCTAssertEqual(wire.deletedRecordIDs, data.deletedRecordIDs)
        XCTAssertEqual(wire.players[0].playingHand, "Both hands")
        XCTAssertEqual(session.context.coachSummary(in: data.setup.coaches), "Coach 1, Coach 6 and Visiting coach")
    }

    @MainActor func testSavingAndReloadingTrainingDoesNotEraseSavedCoachCatalogue() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TennisStore(storeURL: url)
        var setup = TennisSetup(); setup.coaches = (1...6).map { TennisCoach(name: "Coach \($0)") }
        store.updateSetup(setup)
        var session = TrainingSession(playerID: UUID())
        session.context.coachIDs = [setup.coaches[0].id, setup.coaches[5].id]
        session.context.otherCoachName = "Guest coach"
        store.upsertTraining(session)
        let reloaded = TennisStore(storeURL: url)
        XCTAssertEqual(reloaded.data.setup.coaches, setup.coaches)
        XCTAssertEqual(reloaded.data.trainingSessions[0].context.coachIDs, session.context.coachIDs)
        XCTAssertEqual(reloaded.data.trainingSessions[0].context.otherCoachName, "Guest coach")
        XCTAssertEqual(reloaded.data.setup.coaches.count, 6, "One-off names must not become saved coaches")
    }

    func testNoneClearsSavedAndOtherCoachSelection() {
        var context = TennisActivityContext()
        context.coachIDs = [UUID()]; context.coachName = "Former coach"
        context.otherCoachName = "Guest"; context.coachesNeedDetails = true
        context.clearCoaches()
        XCTAssertEqual(context.coachSummary(in: []), "")
        XCTAssertTrue(context.coachIDs.isEmpty)
        XCTAssertNil(context.otherCoachName)
        XCTAssertEqual(context.coachesNeedDetails, false)
    }

    func testLegacyCoachNameStillDecodesWithoutInventingASelection() throws {
        let raw = Data(#"{"coachName":"Previous coach"}"#.utf8)
        let context = try JSONDecoder().decode(TennisActivityContext.self, from: raw)
        XCTAssertEqual(context.coachSummary(in: []), "Previous coach")
        XCTAssertTrue(context.coachIDs.isEmpty)
        XCTAssertNil(context.otherCoachName)
    }

    func testThisWeekStartsOnMondayEvenInASundayFirstLocale() {
        let now = date("2026-09-08T12:00:00Z")
        let week = TennisReportingWeek.interval(containing: now, calendar: sundayFirstCalendar)
        XCTAssertEqual(week.start, date("2026-09-06T23:00:00Z"))
        XCTAssertEqual(week.end, date("2026-09-13T23:00:00Z"))
        var snapshot = TennisWatchSnapshot(); let playerID = UUID(); snapshot.selectedPlayerID = playerID
        for day in ["2026-09-05T12:00:00Z", "2026-09-06T09:00:00Z", "2026-09-06T15:00:00Z", "2026-09-07T12:00:00Z", "2026-09-09T12:00:00Z"] {
            var match = MatchRecord(playerID: playerID); match.date = date(day); match.status = .completed
            snapshot.matches.append(match)
        }
        var another = MatchRecord(playerID: UUID()); another.date = now; snapshot.matches.append(another)
        let summary = TennisGlance.make(kind: .week, snapshot: snapshot, now: now, calendar: sundayFirstCalendar).accessibilitySummary
        XCTAssertTrue(summary.contains("1 completed match, 1 win"))
        XCTAssertTrue(summary.contains("Monday")); XCTAssertTrue(summary.contains("Sunday"))
        XCTAssertFalse(summary.contains("3 completed matches"))
    }

    func testMondayBoundaryResetsAStaleWeeklySnapshotWithoutNewData() {
        let sunday = date("2026-09-06T22:59:30Z"), monday = date("2026-09-06T23:00:00Z")
        var snapshot = TennisWatchSnapshot()
        var match = MatchRecord(playerID: UUID()); match.date = sunday; snapshot.matches = [match]
        let before = TennisGlance.make(kind: .week, snapshot: snapshot, now: sunday, calendar: sundayFirstCalendar)
        let after = TennisGlance.make(kind: .week, snapshot: snapshot, now: monday, calendar: sundayFirstCalendar)
        XCTAssertTrue(before.accessibilitySummary.contains("1 completed match"))
        XCTAssertTrue(after.accessibilitySummary.contains("0 completed matches"))
        XCTAssertTrue(TennisReportingWeek.timelineDates(from: sunday, calendar: sundayFirstCalendar).contains(monday))
    }

    func testReportingWeekUsesLocalMidnightAcrossDaylightSaving() {
        let now = date("2026-03-29T12:00:00Z")
        let interval = TennisReportingWeek.interval(containing: now, calendar: sundayFirstCalendar)
        XCTAssertEqual(interval.duration, 7 * 86400 - 3600)
        XCTAssertEqual(sundayFirstCalendar.component(.hour, from: interval.start), 0)
        XCTAssertEqual(sundayFirstCalendar.component(.hour, from: interval.end), 0)
    }

    func testMatchConditionsRoundTripAndWatchEditsKeepLiveScoreAndIDs() throws {
        var current = MatchRecord(playerID: UUID()); current.status = .inProgress
        current.liveScore = TennisScoreState().snapshot; current.actualStart = date("2026-09-08T10:00:00Z")
        var draft = current
        draft.environment = TennisMatchEnvironment(noise: .veryLoud, setting: .outdoors, weather: [.sunny, .windy, .lightRain])
        draft.courtSurface = .artificialClay
        draft.result = .loss; draft.yourSetsWon = 4
        let edited = TennisWatchRecordEdits.match(draft, current: current)
        let wire = try JSONDecoder.tennisTracker.decode(MatchRecord.self, from: JSONEncoder.tennisTracker.encode(edited))
        XCTAssertEqual(wire.id, current.id); XCTAssertEqual(wire.stableShareID, current.stableShareID)
        XCTAssertEqual(wire.liveScore, current.liveScore); XCTAssertEqual(wire.actualStart, current.actualStart)
        XCTAssertEqual(wire.result, current.result); XCTAssertEqual(wire.yourSetsWon, current.yourSetsWon)
        XCTAssertEqual(wire.environment, draft.environment)
        XCTAssertTrue(wire.conditionsSummary.contains("Sound: Very loud"))
        XCTAssertTrue(wire.conditionsSummary.contains("Weather: Sunny, Windy and Light showers"))
        XCTAssertEqual(TennisNoiseLevel.allCases.filter { $0 != .notRecorded }.count, 5)
    }

    func testIndoorLegacySurfaceAndOutdoorWeatherAreSeparate() {
        var match = MatchRecord(playerID: UUID()); match.courtSurface = .indoor
        match.environment.weather = [.rain]
        XCTAssertEqual(match.effectiveCourtSetting, .indoors)
        XCTAssertFalse(match.conditionsSummary.contains("Weather"))
        match.environment.setting = .outdoors; match.courtSurface = .hard
        XCTAssertTrue(match.conditionsSummary.contains("Outdoors"))
        XCTAssertTrue(match.conditionsSummary.contains("Hard court"))
        XCTAssertTrue(match.conditionsSummary.contains("Rain"))
    }

    func testManualMatchValidationPreservesOneSetRuleAndAllowsUnrecordedScore() {
        var match = MatchRecord(playerID: UUID()); match.opponentName = "Sam"; match.matchFormat = .oneSet
        XCTAssertNil(TennisManualMatchEntry.validationMessage(for: match))
        match.yourSetsWon = 1
        XCTAssertNil(TennisManualMatchEntry.validationMessage(for: match))
        match.opponentSetsWon = 1
        XCTAssertNotNil(TennisManualMatchEntry.validationMessage(for: match))
        match.opponentSetsWon = 0; match.result = .loss
        XCTAssertNotNil(TennisManualMatchEntry.validationMessage(for: match))
    }

    func testOverviewKeepsExistingComplicationLinksWorking() {
        XCTAssertEqual(TennisWatchPage.today.rawValue, "Overview")
        XCTAssertEqual(TennisWatchPage.destination(for: URL(string: "tennistracker://watch/today")!), .today)
        XCTAssertEqual(TennisWatchPage.destination(for: URL(string: "tennistracker://watch/overview")!), .today)
    }

    func testCompletedWatchMatchCanChangeResultWithoutChangingTimingOrIdentity() {
        var current = MatchRecord(playerID: UUID()); current.opponentName = "Sam"
        current.actualStart = Date(timeIntervalSince1970: 1000)
        current.actualFinish = Date(timeIntervalSince1970: 1800)
        var draft = current; draft.result = .loss; draft.opponentSetsWon = 1
        draft.setScores = "4-6"; draft.environment.weather = [.sunny, .windy]
        let edited = TennisWatchRecordEdits.match(draft, current: current)
        XCTAssertEqual(edited.result, .loss); XCTAssertEqual(edited.opponentSetsWon, 1)
        XCTAssertEqual(edited.setScores, "4-6"); XCTAssertEqual(edited.id, current.id)
        XCTAssertEqual(edited.actualStart, current.actualStart); XCTAssertEqual(edited.actualFinish, current.actualFinish)
        XCTAssertEqual(edited.environment.weather, [.sunny, .windy])
    }

    func testBestOfThreeCannotBeRecordedAsThreeSetsToZero() {
        var match = MatchRecord(playerID: UUID()); match.opponentName = "Sam"
        match.matchFormat = .bestOfThree; match.yourSetsWon = 3
        XCTAssertNotNil(TennisManualMatchEntry.validationMessage(for: match))
        match.yourSetsWon = 2; match.opponentSetsWon = 1
        XCTAssertNil(TennisManualMatchEntry.validationMessage(for: match))
    }
}
