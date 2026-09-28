import XCTest
@testable import TennisTracker

final class TennisWatchSyncTests: XCTestCase {
    func testWatchTrainingStartAndFinishKeepsRecordIDAndNeedsDetails() {
        let playerID = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let finish = start.addingTimeInterval(37 * 60)

        let session = TennisWatchActivityFactory.trainingSession(playerID: playerID, type: .serveAndReturn, startDate: start)
        let finished = TennisWatchActivityFactory.finishTrainingSession(session, finishDate: finish)

        XCTAssertEqual(finished.id, session.id)
        XCTAssertEqual(finished.playerID, playerID)
        XCTAssertEqual(finished.trainingType, .serveAndReturn)
        XCTAssertEqual(finished.durationMinutes, 37)
        XCTAssertTrue(finished.needsDetails)
        XCTAssertFalse(finished.hasSessionDetails)
        XCTAssertGreaterThan(finished.revision, session.revision)
    }

    func testTrainingTypesAreStructuredTennisOptionsForIPhoneAndWatch() {
        XCTAssertGreaterThanOrEqual(TrainingType.allCases.count, 8)
        XCTAssertTrue(TrainingType.allCases.contains(.oneToOneCoaching))
        XCTAssertTrue(TrainingType.allCases.contains(.singlesPractice))
        XCTAssertTrue(TrainingType.allCases.contains(.doublesPractice))
        XCTAssertTrue(TrainingType.allCases.contains(.tournamentPreparation))

        let playerID = UUID()
        let session = TennisWatchActivityFactory.trainingSession(playerID: playerID, type: .doublesPractice)

        XCTAssertEqual(session.trainingType, .doublesPractice)
        XCTAssertEqual(session.focus, "")
        XCTAssertTrue(TennisSummaryFormatter.training(session, style: .accessibility).contains("Doubles practice"))
    }

    func testLegacyTrainingTypeNamesDecodeToCurrentStructuredTypes() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(try decoder.decode(TrainingType.self, from: Data(#""General practice""#.utf8)), .rallyConsistency)
        XCTAssertEqual(try decoder.decode(TrainingType.self, from: Data(#""Match practice""#.utf8)), .matchPlay)
        XCTAssertEqual(try decoder.decode(TrainingType.self, from: Data(#""Coaching""#.utf8)), .oneToOneCoaching)
    }

    func testWatchCreatedMatchHasStableIDLiveScoreAndNeedsDetails() {
        var player = PlayerProfile()
        player.name = "Example Player"
        player.sightLevel = .b2

        let match = TennisWatchActivityFactory.match(player: player, kind: .singles)

        XCTAssertEqual(match.playerID, player.id)
        XCTAssertEqual(match.playerName, "Example Player")
        XCTAssertEqual(match.status, .inProgress)
        XCTAssertEqual(match.allowedBounces, 3)
        XCTAssertNotNil(match.liveScore)
        XCTAssertTrue(match.needsDetails)
    }

    func testWatchMatchCanLinkToTournamentWithoutChangingTournamentID() {
        var player = PlayerProfile()
        player.name = "Example Player"
        var tournament = TournamentRecord(playerID: player.id)
        tournament.name = "Fictional Test Open"
        tournament.location = "Fictional Test Town"
        tournament.date = Date(timeIntervalSince1970: 1_800_100_000)

        let now = tournament.date.addingTimeInterval(3600)
        let match = TennisWatchActivityFactory.match(player: player, kind: .doubles, tournament: tournament, startDate: now)

        XCTAssertEqual(match.tournamentID, tournament.id)
        XCTAssertEqual(match.date, now)
        XCTAssertEqual(match.location, "Fictional Test Town")
        XCTAssertEqual(match.matchType, .doubles)
    }

    func testConflictResolverUsesRevisionThenModifiedDate() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)

        XCTAssertTrue(TennisRecordConflictResolver.shouldReplace(incomingRevision: 2, incomingModifiedAt: older, existingRevision: 1, existingModifiedAt: newer))
        XCTAssertFalse(TennisRecordConflictResolver.shouldReplace(incomingRevision: 1, incomingModifiedAt: newer, existingRevision: 2, existingModifiedAt: older))
        XCTAssertTrue(TennisRecordConflictResolver.shouldReplace(incomingRevision: 2, incomingModifiedAt: newer, existingRevision: 2, existingModifiedAt: older))
    }

    func testWatchSnapshotIncludesActiveAndNeedsDetailsRecords() {
        let playerID = UUID()
        var data = AppData()
        data.selectedPlayerID = playerID
        data.players = [PlayerProfile()]
        data.players[0].id = playerID
        data.matches = [TennisWatchActivityFactory.match(player: data.players[0], kind: .singles)]
        data.trainingSessions = [TennisWatchActivityFactory.trainingSession(playerID: playerID)]

        let snapshot = TennisWatchSnapshot(data: data)

        XCTAssertEqual(snapshot.matches.count, 1)
        XCTAssertEqual(snapshot.trainingSessions.count, 1)
        XCTAssertTrue(snapshot.matches[0].needsDetails)
        XCTAssertTrue(snapshot.trainingSessions[0].needsDetails)
    }

    func testOneSetMatchSummaryUsesActualScoreAcrossSurfaces() {
        var player = PlayerProfile()
        player.name = "Example Player"
        var tournament = TournamentRecord(playerID: player.id)
        tournament.name = "Fictional Test Open"
        var match = MatchRecord(playerID: player.id)
        match.playerName = "Example Player"
        match.opponentName = "Fictional Opponent"
        match.matchFormat = .oneSet
        match.status = .completed
        match.result = .win
        match.yourSetsWon = 1
        match.opponentSetsWon = 0
        match.setScores = "6-4"
        match.tournamentID = tournament.id
        match.date = date(day: 21, month: 8, year: 2026)

        XCTAssertEqual(
            TennisSummaryFormatter.match(match, tournaments: [tournament], style: .long),
            "Completed singles match. Example Player beat Fictional Opponent, 6-4, Fictional Test Open, 21 August 2026."
        )
        XCTAssertEqual(
            TennisSummaryFormatter.match(match, tournaments: [tournament], style: .short),
            "Completed singles match. Win against Fictional Opponent, 6-4, Fictional Test Open."
        )
    }

    private func date(day: Int, month: Int, year: Int) -> Date {
        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}
