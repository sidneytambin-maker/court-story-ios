import XCTest
@testable import TennisTracker

final class TennisScoringTests: XCTestCase {
    func testInitialScoreUsesTennisTerms() {
        let scorer = TennisScoringEngine()

        XCTAssertEqual(scorer.state.pointScore, "Love-Love")
        XCTAssertEqual(scorer.state.spokenScore, "Love-Love, games 0-0, sets 0-0, Player against Opponent")
    }

    func testDeuceAndAdvantage() {
        var scorer = TennisScoringEngine()

        for winner in [PointWinner.player, .player, .player, .opponent, .opponent, .opponent] {
            _ = scorer.awardPoint(to: winner)
        }

        XCTAssertEqual(scorer.state.pointScore, "Deuce")

        _ = scorer.awardPoint(to: .player)
        XCTAssertEqual(scorer.state.pointScore, "Advantage Player")

        _ = scorer.awardPoint(to: .opponent)
        XCTAssertEqual(scorer.state.pointScore, "Deuce")
    }

    func testGameAfterFourStraightPoints() {
        var scorer = TennisScoringEngine()

        for _ in 0..<4 {
            _ = scorer.awardPoint(to: .player)
        }

        XCTAssertEqual(scorer.state.playerGames, 1)
        XCTAssertEqual(scorer.state.opponentGames, 0)
        XCTAssertEqual(scorer.state.pointScore, "Love-Love")
    }

    func testSetCompletesAtSixLove() {
        var scorer = TennisScoringEngine()

        winGames(6, for: .player, scorer: &scorer)

        XCTAssertEqual(scorer.state.playerSets, 1)
        XCTAssertEqual(scorer.state.opponentSets, 0)
        XCTAssertEqual(scorer.state.completedSetScores, ["6-0"])
        XCTAssertEqual(scorer.state.playerGames, 0)
        XCTAssertEqual(scorer.state.opponentGames, 0)
    }

    func testTiebreakCompletesAtSevenFive() {
        var scorer = TennisScoringEngine()

        winGames(5, for: .player, scorer: &scorer)
        winGames(5, for: .opponent, scorer: &scorer)
        winGames(1, for: .player, scorer: &scorer)
        winGames(1, for: .opponent, scorer: &scorer)
        for _ in 0..<6 { _ = scorer.awardPoint(to: .player) }
        for _ in 0..<5 { _ = scorer.awardPoint(to: .opponent) }
        _ = scorer.awardPoint(to: .player)

        XCTAssertEqual(scorer.state.playerSets, 1)
        XCTAssertEqual(scorer.state.completedSetScores, ["7-6"])
    }

    func testBestOfThreeMatchCompletes() {
        var scorer = TennisScoringEngine()

        winGames(6, for: .player, scorer: &scorer)
        winGames(6, for: .player, scorer: &scorer)

        XCTAssertTrue(scorer.state.isMatchComplete)
        XCTAssertEqual(scorer.awardPoint(to: .opponent), "Match is already complete. Match complete. Player wins. Final score, 6-0, 6-0.")
    }

    func testOneSetMatchCompletesAfterOneSet() {
        var scorer = TennisScoringEngine(setsNeededToWin: 1)

        winGames(6, for: .player, scorer: &scorer)

        XCTAssertTrue(scorer.state.isMatchComplete)
        XCTAssertEqual(scorer.state.completedSetScores, ["6-0"])
    }

    func testNoAutomaticTieBreakDoesNotStartAtSixAll() {
        var scorer = TennisScoringEngine(tieBreakRule: .noAutomatic)

        winGames(6, for: .player, scorer: &scorer)
        winGames(6, for: .opponent, scorer: &scorer)
        _ = scorer.awardPoint(to: .player)

        XCTAssertFalse(scorer.state.isTiebreak)
        XCTAssertEqual(scorer.state.pointScore, "15-Love")
    }

    func testUndoRestoresPreviousState() {
        var scorer = TennisScoringEngine()

        _ = scorer.awardPoint(to: .player)
        XCTAssertEqual(scorer.state.pointScore, "15-Love")
        XCTAssertEqual(scorer.undo(), "Undone. Player and Opponent are level. Current game, Love-Love. Games 0-0. Sets 0-0.")
    }

    func testSuddenDeathDeuceWinsGameOnNextPoint() {
        var scorer = TennisScoringEngine(playerName: "Sidney", opponentName: "Klaudia", suddenDeathDeuce: true)

        for winner in [PointWinner.player, .player, .player, .opponent, .opponent, .opponent] {
            _ = scorer.awardPoint(to: winner)
        }

        XCTAssertEqual(scorer.state.pointScore(suddenDeathDeuce: true), "Sudden-death deuce")
        _ = scorer.awardPoint(to: .player)
        XCTAssertEqual(scorer.state.playerGames, 1)
        XCTAssertEqual(scorer.state.pointScore, "Love-Love")
    }

    func testNamedScoreAnnouncementMentionsPointWinner() {
        var scorer = TennisScoringEngine(playerName: "Sidney", opponentName: "Klaudia")

        let message = scorer.awardPoint(to: .player)

        XCTAssertTrue(message.contains("Point to Sidney"))
        XCTAssertTrue(message.contains("15-Love"))
    }

    func testManualTieBreakCanStartAndFinish() {
        var scorer = TennisScoringEngine(playerName: "Sidney", opponentName: "Klaudia", tieBreakRule: .manual)

        XCTAssertFalse(scorer.state.isTiebreak)
        _ = scorer.startTieBreak()
        XCTAssertTrue(scorer.state.isTiebreak)
        _ = scorer.finishTieBreak(winner: .player)

        XCTAssertFalse(scorer.state.isTiebreak)
        XCTAssertEqual(scorer.state.playerGames, 1)
    }

    func testScoreSnapshotRestoresInProgressMatch() {
        var scorer = TennisScoringEngine(playerName: "Sidney", opponentName: "Klaudia")
        _ = scorer.awardPoint(to: .player)
        _ = scorer.awardPoint(to: .opponent)

        let restored = TennisScoringEngine(
            playerName: "Sidney",
            opponentName: "Klaudia",
            snapshot: scorer.state.snapshot
        )

        XCTAssertEqual(restored.state.playerPoints, 1)
        XCTAssertEqual(restored.state.opponentPoints, 1)
        XCTAssertEqual(restored.fullScore, scorer.fullScore)
    }

    private func winGames(_ count: Int, for winner: PointWinner, scorer: inout TennisScoringEngine) {
        for _ in 0..<count {
            for _ in 0..<4 {
                _ = scorer.awardPoint(to: winner)
            }
        }
    }
}
