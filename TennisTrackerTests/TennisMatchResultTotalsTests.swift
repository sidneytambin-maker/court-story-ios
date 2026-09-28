import XCTest
@testable import TennisTracker

final class TennisMatchResultTotalsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFortyOldResultsSurviveEmptyEditableCacheAndWireRoundTrip() throws {
        let data = resultLibrary(future: false)
        let snapshot = TennisWatchSnapshot(data: data, now: now)
        XCTAssertTrue(snapshot.matches.isEmpty)
        let totals = assertParity(data, snapshot)
        assertFiveOfEachOutcome(totals.singles)
        assertFiveOfEachOutcome(totals.doubles)
        assertParity(data, try roundTrip(snapshot))
    }

    func testFortyFutureCompletedResultsSurviveThirtyRecordLimitWithoutAwardingAchievements() throws {
        let data = resultLibrary(future: true)
        let snapshot = TennisWatchSnapshot(data: data, now: now)
        XCTAssertEqual(snapshot.matches.count, 30)
        XCTAssertEqual(snapshot.achievementHistory.count, 40)
        let totals = assertParity(data, snapshot)
        assertFiveOfEachOutcome(totals.singles)
        assertFiveOfEachOutcome(totals.doubles)
        let records = snapshot.achievementRecords(at: now)
        XCTAssertTrue(records.allSatisfy { $0.metrics.count == 1 })
        XCTAssertTrue(TennisAchievement.build(records: records, playerID: data.selectedPlayerID)
            .allSatisfy { $0.progress == 0 && !$0.earned })
        assertParity(data, try roundTrip(snapshot))
    }

    func testOfflineResultAndKindEditReopenAndDeletionReplaceCompactHistory() {
        var data = library()
        var match = record(playerID: data.selectedPlayerID!, kind: .singles, result: .win, days: -100)
        data.matches = [match]
        var snapshot = TennisWatchSnapshot(data: data, now: now)
        XCTAssertTrue(snapshot.matches.isEmpty)
        XCTAssertEqual(assertParity(data, snapshot).singles.wins, 1)
        match.matchType = .doubles
        match.result = .loss
        data.matches = [match]
        snapshot.matches = [match]
        let edited = assertParity(data, snapshot)
        XCTAssertEqual(edited.singles.count, 0)
        XCTAssertEqual(edited.doubles.losses, 1)
        for status in [MatchStatus.scheduled, .inProgress] {
            match.status = status
            data.matches = [match]
            snapshot.matches = [match]
            XCTAssertEqual(assertParity(data, snapshot), TennisMatchResultTotals())
        }
        match.status = .completed
        data.matches = [match]
        snapshot.matches = [match]
        XCTAssertEqual(assertParity(data, snapshot).doubles.losses, 1)
        snapshot.deletedRecordIDs.insert(match.id)
        data.matches = []
        XCTAssertEqual(assertParity(data, snapshot), TennisMatchResultTotals())
    }

    func testOldLegacyPracticeResultsCoverEveryKindAndOutcome() {
        var data = library()
        for kind in MatchKind.allCases {
            for result in MatchResult.allCases {
                data.trainingSessions.append(practice(playerID: data.selectedPlayerID!, kind: kind, result: result))
            }
        }
        let snapshot = TennisWatchSnapshot(data: data, now: now)
        XCTAssertTrue(snapshot.trainingSessions.isEmpty)
        let totals = assertParity(data, snapshot)
        XCTAssertEqual(totals.singles, TennisResultTotals(wins: 1, losses: 1, draws: 1, retired: 1))
        XCTAssertEqual(totals.doubles, totals.singles)
    }

    func testLinkedPracticeIsDeduplicatedAcrossCacheBoundaryAndRestoredAfterDeletion() {
        var data = library()
        let session = practice(playerID: data.selectedPlayerID!, kind: .doubles, result: .win)
        data.trainingSessions = [session]
        var snapshot = TennisWatchSnapshot(data: data, now: now)
        var match = record(playerID: session.playerID, kind: .doubles, result: .loss, days: 100)
        match.trainingSessionID = session.id
        data.matches = [match]
        snapshot.matches = [match]
        let totals = assertParity(data, snapshot)
        XCTAssertEqual(totals.doubles.wins, 0)
        XCTAssertEqual(totals.doubles.losses, 1)
        XCTAssertFalse(snapshot.achievementRecords(at: now).first { $0.id == session.id }!.metrics
            .contains { $0.hasPrefix("doubles") })
        for status in [MatchStatus.scheduled, .inProgress] {
            match.status = status
            data.matches = [match]
            snapshot.matches = [match]
            XCTAssertEqual(assertParity(data, snapshot), TennisMatchResultTotals())
        }
        snapshot.deletedRecordIDs.insert(match.id)
        data.matches = []
        XCTAssertEqual(assertParity(data, snapshot).doubles.wins, 1)
        match.status = .completed
        match.date = session.date
        data.matches = [match]
        let bothArchived = TennisWatchSnapshot(data: data, now: now)
        XCTAssertTrue(bothArchived.matches.isEmpty)
        XCTAssertTrue(bothArchived.trainingSessions.isEmpty)
        XCTAssertEqual(assertParity(data, bothArchived).doubles.losses, 1)
    }

    func testScheduledActiveOtherPlayersAndUnrecordedPracticeNeverCount() {
        var data = library()
        for status in [MatchStatus.scheduled, .inProgress] {
            for days in [-100, 100] {
                var match = record(playerID: data.selectedPlayerID!, kind: .singles, result: .win, days: days)
                match.status = status
                data.matches.append(match)
            }
        }
        data.matches.append(record(playerID: UUID(), kind: .singles, result: .win, days: -100))
        var future = practice(playerID: data.selectedPlayerID!, kind: .singles, result: .win)
        future.date = now.addingTimeInterval(100 * 86_400)
        var active = practice(playerID: data.selectedPlayerID!, kind: .singles, result: .win)
        active.actualStart = active.date
        data.trainingSessions = [future, active]
        XCTAssertEqual(assertParity(data, TennisWatchSnapshot(data: data, now: now)), TennisMatchResultTotals())
    }

    func testLegacyWireFallbackAndCurrentRecordOverride() throws {
        var data = resultLibrary(future: false)
        var snapshot = TennisWatchSnapshot(data: data, now: now)
        snapshot.achievementHistory = legacyMetrics(snapshot.achievementHistory)
        snapshot = try roundTrip(snapshot)
        assertParity(data, snapshot)
        data.matches[0].status = .scheduled
        snapshot.matches = [data.matches[0]]
        assertParity(data, snapshot)

        var futureData = library()
        let future = record(playerID: futureData.selectedPlayerID!, kind: .doubles, result: .retired, days: 100)
        futureData.matches = [future]
        var legacyFuture = TennisWatchSnapshot(data: futureData, now: now)
        legacyFuture.achievementHistory = legacyMetrics(legacyFuture.achievementHistory)
        XCTAssertTrue(legacyFuture.achievementHistory[0].metrics.isEmpty)
        XCTAssertEqual(assertParity(futureData, try roundTrip(legacyFuture)).doubles.retired, 1)
    }

    func testNewMetricsTakePrecedenceWithoutDoubleCountingIDsOrOtherPlayers() {
        let playerID = UUID()
        let current = TennisAchievementRecord(id: UUID(), playerID: playerID, date: now,
            metrics: ["match", "singles", "singlesWin", "doublesResultLoss"])
        var other = current
        other.id = UUID()
        other.playerID = UUID()
        let totals = TennisMatchResultTotals.build(records: [current, current, other], playerID: playerID)
        XCTAssertEqual(totals.singles.count, 0)
        XCTAssertEqual(totals.doubles.losses, 1)
        XCTAssertEqual(TennisMatchResultTotals.build(records: [current], playerID: nil), TennisMatchResultTotals())
    }

    func testNewResultMetricsDoNotChangeExistingAchievementProgress() {
        var data = resultLibrary(future: false)
        var future = resultLibrary(future: true).matches
        for index in future.indices { future[index].playerID = data.selectedPlayerID! }
        data.matches += future
        data.trainingSessions = [practice(playerID: data.selectedPlayerID!, kind: .doubles, result: .win)]
        let records = TennisWatchSnapshot(data: data, now: now).achievementRecords(at: now)
        XCTAssertEqual(TennisAchievement.build(records: records, playerID: data.selectedPlayerID),
            TennisAchievement.build(records: legacyMetrics(records), playerID: data.selectedPlayerID))
    }

    @discardableResult
    private func assertParity(_ data: AppData, _ snapshot: TennisWatchSnapshot,
                              file: StaticString = #filePath, line: UInt = #line) -> TennisMatchResultTotals {
        let phone = TennisPlayerProgress.build(player: data.players.first { $0.id == data.selectedPlayerID },
            matches: data.matches, training: data.trainingSessions, now: now)
        let watch = TennisMatchResultTotals.build(records: snapshot.achievementRecords(at: now), playerID: data.selectedPlayerID)
        XCTAssertEqual(watch.singles, phone.singles, file: file, line: line)
        XCTAssertEqual(watch.doubles, phone.doubles, file: file, line: line)
        return watch
    }

    private func library() -> AppData {
        var data = AppData()
        var player = PlayerProfile()
        player.name = "Results Example"
        data.players = [player]
        data.selectedPlayerID = player.id
        return data
    }

    private func resultLibrary(future: Bool) -> AppData {
        var data = library()
        for _ in 0..<5 {
            for kind in MatchKind.allCases {
                for result in MatchResult.allCases {
                    let days = (100 + data.matches.count) * (future ? 1 : -1)
                    data.matches.append(record(playerID: data.selectedPlayerID!, kind: kind, result: result, days: days))
                }
            }
        }
        return data
    }

    private func record(playerID: UUID, kind: MatchKind, result: MatchResult, days: Int) -> MatchRecord {
        var match = MatchRecord(playerID: playerID)
        match.status = .completed
        match.matchType = kind
        match.result = result
        match.date = now.addingTimeInterval(Double(days) * 86_400)
        return match
    }

    private func practice(playerID: UUID, kind: MatchKind, result: MatchResult) -> TrainingSession {
        var session = TrainingSession(playerID: playerID)
        session.date = now.addingTimeInterval(-100 * 86_400)
        session.practiceResult = TennisPracticeResult(kind: kind, result: result)
        return session
    }

    private func legacyMetrics(_ records: [TennisAchievementRecord]) -> [TennisAchievementRecord] {
        records.map { record in
            var legacy = record
            legacy.metrics.removeAll { $0.hasPrefix("singlesResult") || $0.hasPrefix("doublesResult") }
            return legacy
        }
    }

    private func roundTrip(_ snapshot: TennisWatchSnapshot) throws -> TennisWatchSnapshot {
        try JSONDecoder.tennisTracker.decode(TennisWatchSnapshot.self, from: JSONEncoder.tennisTracker.encode(snapshot))
    }

    private func assertFiveOfEachOutcome(_ totals: TennisResultTotals,
                                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(totals, TennisResultTotals(wins: 5, losses: 5, draws: 5, retired: 5), file: file, line: line)
    }
}
