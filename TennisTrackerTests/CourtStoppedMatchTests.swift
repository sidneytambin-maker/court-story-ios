import XCTest
@testable import TennisTracker

final class CourtStoppedMatchTests: XCTestCase {
    func testStoppedMatchIsNotDrawInPhoneWatchHistoryOrTournament() throws {
        var player = PlayerProfile(); player.name = "Demo Player"
        var tournament = TournamentRecord(playerID: player.id); tournament.name = "Demo Cup"
        var record = MatchRecord(playerID: player.id)
        record.playerName = player.name; record.opponentName = "Demo Opponent"
        record.date = Date().addingTimeInterval(-3600); record.tournamentID = tournament.id
        record.matchType = .doubles
        record.court.sport = CourtSportSelection(sport: .badminton)
        var score = record.makeCourtScore()
        score.awardRally(to: 0)
        let playing = score.frame
        XCTAssertTrue(score.stopWithoutWinner())
        XCTAssertNil(score.frame.winningSide)
        XCTAssertEqual(score.frame.rounds.last?.points, [1, 0])
        XCTAssertTrue(score.undo())
        XCTAssertEqual(score.frame, playing)
        XCTAssertTrue(score.stopWithoutWinner())
        record.applyCourtScore(score)
        XCTAssertTrue(record.stoppedWithoutWinner)
        let copy = try JSONDecoder.tennisTracker.decode(MatchRecord.self, from: JSONEncoder.tennisTracker.encode(record))
        XCTAssertTrue(copy.stoppedWithoutWinner)
        let history = TennisAchievementRecord.collect(matches: [record], training: [], tournaments: [])
        XCTAssertFalse(history[0].metrics.contains("doublesDraw"))
        let totals = TennisMatchResultTotals.build(records: history, playerID: player.id).doubles
        XCTAssertEqual(totals.count, 1); XCTAssertEqual(totals.draws, 0); XCTAssertEqual(totals.stopped, 1)
        let progress = TennisPlayerProgress.build(player: player, matches: [record], training: [])
        XCTAssertEqual(progress.doubles, totals)
        let stats = TennisStatistics.build(matches: [record], training: [], tournaments: [])
        XCTAssertEqual(stats.drawCount, 0); XCTAssertEqual(stats.stoppedCount, 1)
        XCTAssertTrue(stats.spokenSummary.contains("stopped without a winner"))
        XCTAssertFalse(TennisSummaryFormatter.match(record).contains("drew with"))
        let tournamentSummary = TennisSummaryFormatter.tournament(tournament, matches: [record])
        XCTAssertTrue(tournamentSummary.contains("1 stopped without a winner"))
        XCTAssertFalse(tournamentSummary.contains("1 draw"))
    }

    func testLegacyDrawRemainsDrawAndNewStoppedMetricDeduplicates() {
        let player = PlayerProfile()
        var legacy = MatchRecord(playerID: player.id); legacy.result = .draw; legacy.status = .completed
        let history = TennisAchievementRecord.collect(matches: [legacy], training: [], tournaments: [])
        XCTAssertFalse(legacy.stoppedWithoutWinner)
        let totals = TennisMatchResultTotals.build(records: history + history, playerID: player.id)
        XCTAssertEqual(totals.singles.draws, 1); XCTAssertEqual(totals.singles.stopped, 0)
        XCTAssertTrue(TennisSummaryFormatter.match(legacy).contains("drew with"))
    }

    func testStoppingEachOfficialSportRetainsPointsAndUndo() throws {
        for sport in CourtSport.allCases where sport != .custom {
            var score = CourtScoreSession(sport: CourtSportSelection(sport: sport), rules: .standard(for: sport),
                sides: [CourtScoreSide(name: "Demo A"), CourtScoreSide(name: "Demo B")])
            score.awardRally(to: 0)
            let before = score.frame
            XCTAssertTrue(score.stopWithoutWinner(), sport.rawValue)
            XCTAssertNil(score.validationMessage)
            XCTAssertEqual(score.frame.points, before.points)
            XCTAssertTrue(score.summary.contains("Play stopped before a winner"))
            XCTAssertFalse(score.awardRally(to: 1))
            XCTAssertFalse(score.stopWithoutWinner())
            let persisted = try JSONDecoder().decode(CourtScoreSession.self, from: JSONEncoder().encode(score))
            XCTAssertEqual(persisted.frame, score.frame)
            XCTAssertTrue(score.undo()); XCTAssertEqual(score.frame, before)
        }
    }
}
