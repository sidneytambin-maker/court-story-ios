import XCTest
@testable import TennisTracker

final class TennisDashboardVenueRegressionTests: XCTestCase {
    func testTrainingLinkedDoublesCountOnceInBothDashboardTotals() {
        let player = PlayerProfile()
        var training = TrainingSession(playerID: player.id)
        training.date = Date().addingTimeInterval(-7200)
        training.practiceResult = TennisPracticeResult(kind: .doubles, result: .win)
        var matches: [MatchRecord] = []
        for result in [MatchResult.win, .loss, .loss] {
            var match = MatchRecord(playerID: player.id)
            match.matchType = .doubles; match.result = result; match.trainingSessionID = training.id
            matches.append(match)
        }
        let progress = TennisPlayerProgress.build(player: player, matches: matches, training: [training])
        XCTAssertEqual(progress.doubles.count, 3)
        XCTAssertEqual(progress.doubles.wins, 1)
        XCTAssertEqual(progress.doubles.losses, 2)
        XCTAssertEqual(progress.singles.count, 0)
        XCTAssertEqual(progress.doublesPractice.count, 3)
        let stats = TennisStatistics.build(matches: matches, training: [training], tournaments: [])
        XCTAssertEqual(stats.matchCount, 3)
        XCTAssertEqual(stats.winCount, 1)
        XCTAssertEqual(stats.lossCount, 2)
    }

    func testNoTournamentIsValidAndNotAnAttentionWarning() {
        let match = MatchRecord(playerID: UUID())
        XCTAssertTrue(TennisStatistics.build(matches: [match], training: [], tournaments: []).needsAttention.isEmpty)
    }

    func testSpecificFocusDoesNotUseLegacyTypeAndCoachingNamesAreIncluded() {
        let player = PlayerProfile()
        let coach = TennisCoach(name: "Chris")
        var session = TrainingSession(playerID: player.id)
        session.date = Date().addingTimeInterval(-7200)
        session.trainingType = .oneToOneCoaching
        session.focus = TrainingType.oneToOneCoaching.rawValue
        session.context.coachIDs = [coach.id]
        let progress = TennisPlayerProgress.build(player: player, matches: [], training: [session], coaches: [coach])
        XCTAssertEqual(progress.focus.first?.focus, "Specific focus not recorded")
        XCTAssertEqual(progress.trainingTypes.first?.focus, "One-to-one coaching, coaches: Chris")
        XCTAssertEqual(session.focus, TrainingType.oneToOneCoaching.rawValue)
    }

    func testSavedAndHistoricalVenuesAreAvailableRegardlessOfUsageFlags() throws {
        var data = AppData()
        data.setup.venues = [TennisVenue(name: "Training Court", town: "Town", usedForTraining: true, usedForMatches: false)]
        var session = TrainingSession(playerID: UUID())
        session.venue = "History Court"; session.location = "City"
        session.date = Date().addingTimeInterval(-100 * 86400)
        data.trainingSessions = [session]
        var match = MatchRecord(playerID: session.playerID)
        match.venue = "training court"; match.location = "Town"
        data.matches = [match]
        let choices = TennisVenueChoice.build(setup: data.setup, matches: data.matches, training: data.trainingSessions, tournaments: [])
        XCTAssertEqual(choices.count, 2)
        XCTAssertEqual(choices.first { $0.name == "Training Court" }?.venueID, data.setup.venues[0].id)
        let snapshot = try JSONDecoder().decode(TennisWatchSnapshot.self, from: JSONEncoder().encode(TennisWatchSnapshot(data: data)))
        XCTAssertFalse(snapshot.trainingSessions.contains { $0.id == session.id })
        XCTAssertEqual(snapshot.availableVenueChoices, choices)
        XCTAssertEqual(choices.map(\.id), TennisVenueChoice.build(setup: data.setup, matches: data.matches, training: data.trainingSessions, tournaments: []).map(\.id))
    }

    func testOtherTournamentRoundTripsAndSurvivesWatchEditing() throws {
        var match = MatchRecord(playerID: UUID())
        XCTAssertNil(match.customTournamentName)
        let current = match
        match.customTournamentName = "Local friendly event"
        let edited = TennisWatchRecordEdits.match(match, current: current)
        let decoded = try JSONDecoder().decode(MatchRecord.self, from: JSONEncoder().encode(edited))
        XCTAssertNil(decoded.tournamentID)
        XCTAssertEqual(decoded.id, current.id)
        XCTAssertEqual(decoded.customTournamentName, "Local friendly event")
        XCTAssertTrue(TennisSummaryFormatter.match(decoded).contains("Local friendly event"))
        var context = TennisActivityContext()
        context.customTournamentName = ""
        XCTAssertEqual(try JSONDecoder().decode(TennisActivityContext.self, from: JSONEncoder().encode(context)).customTournamentName, "")
        context.customTournamentName = nil
        XCTAssertNil(try JSONDecoder().decode(TennisActivityContext.self, from: JSONEncoder().encode(context)).customTournamentName)
    }
}
