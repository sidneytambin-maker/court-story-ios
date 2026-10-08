import XCTest
@testable import TennisTracker

final class CourtScoreTests: XCTestCase {
    private func match(_ sport: CourtSport, doubles: Bool = false, sides: Int = 2) -> CourtScoreSession {
        CourtScoreSession(sport: CourtSportSelection(sport: sport, customName: sport == .custom ? "Goalball" : ""),
            rules: .standard(for: sport, doubles: doubles), sides: (0..<sides).map { CourtScoreSide(name: "Side \($0 + 1)") })
    }

    func testCustomNumericMultiSideScoringUndoResetAndPersistence() throws {
        var score = match(.custom, sides: 3)
        XCTAssertNil(score.validationMessage)
        for _ in 0..<9 { XCTAssertTrue(score.awardRally(to: 2)) }
        XCTAssertFalse(score.frame.complete)
        XCTAssertFalse(score.summary.contains("Love"))
        XCTAssertTrue(score.awardRally(to: 2))
        XCTAssertEqual(score.frame.winningSide, 2)
        XCTAssertTrue(score.frame.complete)
        let saved = try JSONDecoder().decode(CourtScoreSession.self, from: JSONEncoder().encode(score))
        XCTAssertEqual(saved, score)
        XCTAssertTrue(score.undo())
        XCTAssertFalse(score.frame.complete)
        XCTAssertEqual(score.frame.points, [0, 0, 9])
        score.reset()
        XCTAssertEqual(score.frame.points, [0, 0, 0])
        XCTAssertTrue(score.undo())
        XCTAssertEqual(score.frame.points, [0, 0, 9])
    }

    func testPickleballOnlyServerScoresAndOpeningDoublesHasOneServer() {
        var score = match(.pickleball, doubles: true)
        XCTAssertEqual(score.frame.serverNumber, 2)
        score.awardRally(to: 1)
        XCTAssertEqual(score.frame.points, [0, 0])
        XCTAssertEqual(score.frame.server, 1)
        XCTAssertEqual(score.frame.serverNumber, 1)
        score.awardRally(to: 0)
        XCTAssertEqual(score.frame.server, 1)
        XCTAssertEqual(score.frame.serverNumber, 2)
        score.awardRally(to: 1)
        XCTAssertEqual(score.frame.points, [0, 1])
        XCTAssertTrue(score.undo())
        XCTAssertEqual(score.frame.points, [0, 0])
        XCTAssertEqual(score.frame.serverNumber, 2)
    }

    func testBadmintonCapAndWinByTwo() {
        var score = match(.badminton)
        for _ in 0..<20 { score.awardRally(to: 0); score.awardRally(to: 1) }
        score.awardRally(to: 0)
        XCTAssertEqual(score.frame.rounds.count, 0)
        score.awardRally(to: 1)
        for _ in 0..<8 { score.awardRally(to: 0); score.awardRally(to: 1) }
        XCTAssertEqual(score.frame.points, [29, 29])
        score.awardRally(to: 1)
        XCTAssertEqual(score.frame.rounds[0].points, [29, 30])
        XCTAssertEqual(score.frame.roundsWon, [0, 1])
    }

    func testTableTennisServiceChangesEveryTwoThenEveryOneAtDeuce() {
        var score = match(.tableTennis)
        score.awardRally(to: 0); XCTAssertEqual(score.frame.server, 0)
        score.awardRally(to: 1); XCTAssertEqual(score.frame.server, 1)
        for _ in 0..<9 { score.awardRally(to: 0); score.awardRally(to: 1) }
        let server = score.frame.server
        score.awardRally(to: 0)
        XCTAssertNotEqual(score.frame.server, server)
        score.awardRally(to: 1)
        XCTAssertEqual(score.frame.server, server)
    }

    func testPadelThirdDeuceIsDecidingStarPoint() {
        var score = match(.padel)
        for _ in 0..<5 { score.awardRally(to: 0); score.awardRally(to: 1) }
        XCTAssertEqual(score.frame.tennis.playerGames, 0)
        score.awardRally(to: 1)
        XCTAssertEqual(score.frame.tennis.opponentGames, 1)
        XCTAssertEqual(score.frame.points, [0, 0])
    }

    func testAdvantageSetDoesNotStopAtSevenSixWithoutTiebreak() {
        var score = match(.tennis)
        score.rules.tieBreakAt = nil
        for _ in 0..<6 {
            for _ in 0..<4 { score.awardRally(to: 0) }
            for _ in 0..<4 { score.awardRally(to: 1) }
        }
        for _ in 0..<4 { score.awardRally(to: 0) }
        XCTAssertFalse(score.frame.complete)
        XCTAssertEqual(score.frame.tennis.playerGames, 7)
        for _ in 0..<4 { score.awardRally(to: 0) }
        XCTAssertTrue(score.frame.complete)
        XCTAssertEqual(score.frame.rounds[0].points, [8, 6])
    }

    func testBeachDecidingMatchTiebreakPreservesActualPoints() {
        var score = match(.beachTennis)
        for side in 0...1 { for _ in 0..<24 { score.awardRally(to: side) } }
        XCTAssertEqual(score.frame.roundsWon, [1, 1])
        for _ in 0..<9 { score.awardRally(to: 0); score.awardRally(to: 1) }
        score.awardRally(to: 0)
        XCTAssertFalse(score.frame.complete)
        score.awardRally(to: 0)
        XCTAssertTrue(score.frame.complete)
        XCTAssertEqual(score.frame.rounds.last?.points, [11, 9])
        XCTAssertEqual(score.frame.rounds.last?.tieBreak, [11, 9])
    }

    func testRacketlonAggregateTieRequiresGummiarmNotGamesWon() {
        var score = match(.racketlon)
        for winner in [0, 1, 0, 1] {
            for _ in 0..<19 { score.awardRally(to: 0); score.awardRally(to: 1) }
            score.awardRally(to: winner); score.awardRally(to: winner)
        }
        XCTAssertEqual(score.frame.aggregate, [80, 80])
        XCTAssertTrue(score.frame.gummiarm)
        XCTAssertFalse(score.frame.complete)
        score.awardRally(to: 1)
        XCTAssertTrue(score.frame.complete)
        XCTAssertEqual(score.frame.winningSide, 1)
        XCTAssertTrue(score.frame.gummiarmPlayed)
        XCTAssertEqual(score.frame.aggregate, [80, 80])
        XCTAssertTrue(score.undo())
        XCTAssertTrue(score.frame.gummiarm)
        XCTAssertFalse(score.frame.complete)
    }

    func testInvalidScoresDoNotDiscardDraft() {
        var score = match(.custom, sides: 3)
        score.awardRally(to: 1)
        let original = score
        XCTAssertFalse(score.correctPoints([-1, 0, 0]))
        XCTAssertFalse(score.correctPoints([0, 0]))
        XCTAssertFalse(score.awardRally(to: 3))
        XCTAssertFalse(score.correctPoints([10, 0, 0]))
        XCTAssertEqual(score, original)
        XCTAssertTrue(score.correctPoints([2, 4, 1]))
        XCTAssertTrue(score.undo())
        XCTAssertEqual(score.frame, original.frame)
    }
}
