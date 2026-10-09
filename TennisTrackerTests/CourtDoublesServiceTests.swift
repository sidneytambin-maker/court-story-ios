import XCTest
@testable import TennisTracker

final class CourtDoublesServiceTests: XCTestCase {
    private func match(_ sport: CourtSport) -> CourtScoreSession {
        CourtScoreSession(sport: CourtSportSelection(sport: sport), rules: .standard(for: sport, doubles: true),
            sides: [CourtScoreSide(name: "Alex and Blair", members: ["Alex", "Blair"]),
                    CourtScoreSide(name: "Casey and Drew", members: ["Casey", "Drew"])])
    }

    private func pair(_ score: CourtScoreSession) -> [String] {
        guard let service = score.frame.doublesService else { return [] }
        return [score.sides[score.frame.server].members[service.serverMember],
                service.receiverMember.map { score.sides[1 - score.frame.server].members[$0] } ?? "Either"]
    }

    func testTennisNamedServersRotateThroughAllFourPlayersAndCourtReceivers() {
        var score = match(.tennis)
        XCTAssertEqual(pair(score), ["Alex", "Casey"])
        score.awardRally(to: 0)
        XCTAssertEqual(pair(score), ["Alex", "Drew"])
        for _ in 0..<3 { score.awardRally(to: 0) }
        XCTAssertEqual(pair(score), ["Casey", "Alex"])
        for _ in 0..<4 { score.awardRally(to: 0) }
        XCTAssertEqual(pair(score), ["Blair", "Casey"])
        for _ in 0..<4 { score.awardRally(to: 0) }
        XCTAssertEqual(pair(score), ["Drew", "Alex"])
        XCTAssertTrue(score.summary.contains("Drew"))
        XCTAssertTrue(score.undo())
        XCTAssertEqual(pair(score), ["Blair", "Drew"])
    }

    func testCorrectedTennisPointsRefreshCourtAndTieBreakServerAndUndo() {
        var score = match(.tennis)
        XCTAssertTrue(score.correctPoints([1, 0]))
        XCTAssertEqual(pair(score), ["Alex", "Drew"])
        XCTAssertTrue(score.undo())
        XCTAssertEqual(pair(score), ["Alex", "Casey"])
        for _ in 0..<6 {
            for _ in 0..<4 { score.awardRally(to: 0) }
            for _ in 0..<4 { score.awardRally(to: 1) }
        }
        let before = score.frame
        XCTAssertTrue(score.correctPoints([4, 3]))
        XCTAssertTrue(score.frame.tennis.isTiebreak)
        XCTAssertEqual(score.frame.server, 0)
        XCTAssertEqual(pair(score), ["Alex", "Drew"])
        XCTAssertFalse(score.correctPoints([7, 5]))
        XCTAssertTrue(score.undo()); XCTAssertEqual(score.frame, before)
    }

    func testPointCorrectionUpdatesTablePairAndBadmintonCourtWithoutPhantomHandover() {
        var table = match(.tableTennis)
        XCTAssertTrue(table.correctPoints([2, 0]))
        XCTAssertEqual(pair(table), ["Casey", "Blair"])
        XCTAssertTrue(table.correctPoints([0, 0]))
        XCTAssertEqual(pair(table), ["Alex", "Casey"])
        var badminton = match(.badminton)
        XCTAssertTrue(badminton.correctPoints([3, 1]))
        XCTAssertEqual(pair(badminton), ["Alex", "Drew"])
        XCTAssertEqual(badminton.frame.doublesService?.box, .left)
        var pickleball = match(.pickleball)
        XCTAssertTrue(pickleball.correctPoints([1, 0]))
        XCTAssertEqual(pair(pickleball), ["Alex", "Drew"])
        XCTAssertEqual(pickleball.frame.serverNumber, 2)
    }

    func testExpediteAtDecidingFivePreservesChangedEndsAndUndo() {
        var score = match(.tableTennis)
        for winner in [0, 1, 0, 1] { for _ in 0..<11 { score.awardRally(to: winner) } }
        for _ in 0..<5 { score.awardRally(to: 0) }
        let before = score.frame
        XCTAssertTrue(score.startExpedite(interruptedRally: false))
        XCTAssertTrue(score.frame.doublesService?.midpointChanged == true)
        XCTAssertTrue(score.undo()); XCTAssertEqual(score.frame, before)
    }

    func testTableTennisReceiverBecomesServerAndFormerServersPartnerReceives() {
        var score = match(.tableTennis)
        let expected = [["Alex", "Casey"], ["Casey", "Blair"], ["Blair", "Drew"], ["Drew", "Alex"], ["Alex", "Casey"]]
        for (index, names) in expected.enumerated() {
            XCTAssertEqual(pair(score), names)
            if index < expected.count - 1 { score.awardRally(to: 0); score.awardRally(to: 1) }
        }
    }

    func testTableTennisSubsequentGameReceiverIsPreviousServerToChosenPlayer() {
        var score = match(.tableTennis)
        for _ in 0..<11 { score.awardRally(to: 0) }
        XCTAssertEqual(score.frame.server, 1)
        XCTAssertEqual(pair(score), ["Casey", "Alex"])
        XCTAssertTrue(score.chooseDoublesOrder(firstMembers: [0, 1], rightMembers: [0, 0]))
        XCTAssertEqual(pair(score), ["Drew", "Blair"])
    }

    func testTableTennisDecidingGameChangesReceiverAtFiveAndUndoRestoresOrder() {
        var score = match(.tableTennis)
        for winner in [0, 1, 0, 1] { for _ in 0..<11 { score.awardRally(to: winner) } }
        for _ in 0..<4 { score.awardRally(to: 0) }
        let before = score.frame
        score.awardRally(to: 0)
        XCTAssertTrue(score.frame.doublesService?.midpointChanged == true)
        XCTAssertNotEqual(score.frame.doublesService?.receiverMember, before.doublesService?.receiverMember)
        XCTAssertTrue(score.undo()); XCTAssertEqual(score.frame, before)
    }

    func testBadmintonServerKeepsServingButChangesCourtAfterWinningRally() {
        var score = match(.badminton)
        score.awardRally(to: 0)
        XCTAssertEqual(pair(score), ["Alex", "Drew"])
        XCTAssertEqual(score.frame.doublesService?.box, .left)
        score.awardRally(to: 1)
        XCTAssertEqual(pair(score), ["Drew", "Alex"])
        score.awardRally(to: 1)
        XCTAssertEqual(pair(score), ["Drew", "Blair"])
        XCTAssertEqual(score.frame.doublesService?.box, .right)
    }

    func testPickleballOpeningServerAndTwoServerSideOutUseCorrectNamedPartners() {
        var score = match(.pickleball)
        XCTAssertEqual(pair(score), ["Alex", "Casey"])
        score.awardRally(to: 0)
        XCTAssertEqual(pair(score), ["Alex", "Drew"])
        score.awardRally(to: 1)
        XCTAssertEqual(pair(score), ["Casey", "Blair"])
        score.awardRally(to: 0)
        XCTAssertEqual(pair(score), ["Drew", "Alex"])
        score.awardRally(to: 0)
        XCTAssertEqual(pair(score), ["Blair", "Casey"])
        XCTAssertEqual(score.frame.points, [1, 0])
    }

    func testSquashBoxChoiceAndFourPlayerHandoverDoNotFollowTennisGames() {
        var score = match(.squash)
        XCTAssertTrue(score.chooseServiceBox(.left))
        XCTAssertEqual(pair(score), ["Alex", "Drew"])
        score.awardRally(to: 0)
        XCTAssertEqual(score.frame.doublesService?.box, .right)
        XCTAssertFalse(score.chooseServiceBox(.left))
        score.awardRally(to: 1)
        XCTAssertEqual(pair(score), ["Casey", "Alex"])
        XCTAssertTrue(score.chooseServiceBox(.left))
        score.awardRally(to: 0)
        XCTAssertEqual(pair(score), ["Blair", "Casey"])
        score.awardRally(to: 1)
        XCTAssertEqual(pair(score), ["Drew", "Alex"])
    }

    func testRacquetballOpeningPlayerThenPartnersAndUnrestrictedReceiver() {
        var score = match(.racquetball)
        XCTAssertEqual(pair(score), ["Alex", "Either"])
        score.awardRally(to: 1)
        XCTAssertEqual(pair(score), ["Casey", "Either"])
        score.awardRally(to: 0)
        XCTAssertEqual(pair(score), ["Drew", "Either"])
        score.awardRally(to: 0)
        XCTAssertEqual(pair(score), ["Alex", "Either"])
    }

    func testBeachTennisDoesNotInventFixedReceiverAndPlatformTieStartsLeft() {
        var beach = match(.beachTennis)
        XCTAssertEqual(pair(beach), ["Alex", "Either"])
        beach.awardRally(to: 0)
        XCTAssertEqual(pair(beach), ["Alex", "Either"])
        var platform = match(.platformTennis)
        for _ in 0..<6 {
            for _ in 0..<4 { platform.awardRally(to: 0) }
            for _ in 0..<4 { platform.awardRally(to: 1) }
        }
        XCTAssertEqual(platform.frame.doublesService?.box, .left)
        platform.awardRally(to: 0)
        XCTAssertEqual(platform.frame.doublesService?.box, .right)
        XCTAssertEqual(pair(platform), ["Casey", "Alex"])
    }

    func testNoAdDecidingCourtChoiceAndUndoAreExplicit() {
        var score = match(.padel)
        score.rules.deuce = .noAd
        for _ in 0..<3 { score.awardRally(to: 0); score.awardRally(to: 1) }
        XCTAssertTrue(score.chooseServiceBox(.left))
        XCTAssertEqual(pair(score), ["Alex", "Drew"])
        score.awardRally(to: 0)
        XCTAssertNil(score.frame.doublesService?.selectedDecidingBox)
        score.undo()
        XCTAssertEqual(score.frame.doublesService?.selectedDecidingBox, .left)
    }

    func testServiceStateRoundTripsAndOldFramesWithoutServiceStillDecode() throws {
        var score = match(.pickleball)
        score.awardRally(to: 0); score.awardRally(to: 1)
        let data = try JSONEncoder().encode(score)
        XCTAssertEqual(try JSONDecoder().decode(CourtScoreSession.self, from: data), score)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var frame = try XCTUnwrap(object["frame"] as? [String: Any]); frame.removeValue(forKey: "doublesService"); object["frame"] = frame
        object["history"] = []
        let old = try JSONDecoder().decode(CourtScoreSession.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.frame.doublesService)
        XCTAssertNil(old.validationMessage)
    }

    func testRacketlonTableTennisChangesReceiversAtElevenAndSquashChangesBothPlayers() {
        var score = match(.racketlon)
        for _ in 0..<10 { score.awardRally(to: 0); score.awardRally(to: 1) }
        let receiver = score.frame.doublesService?.receiverMember
        score.awardRally(to: 0)
        XCTAssertTrue(score.frame.doublesService?.midpointChanged == true)
        XCTAssertNotEqual(score.frame.doublesService?.receiverMember, receiver)
        score.undo()
        XCTAssertFalse(score.frame.doublesService?.midpointChanged == true)
        for _ in 10..<19 { score.awardRally(to: 0); score.awardRally(to: 1) }
        score.awardRally(to: 0); score.awardRally(to: 0)
        XCTAssertEqual(score.frame.disciplineIndex, 1)
        XCTAssertEqual(pair(score), ["Casey", "Alex"])
        score.awardRally(to: 0)
        XCTAssertEqual(pair(score), ["Casey", "Blair"])
        score.awardRally(to: 1)
        XCTAssertEqual(pair(score), ["Alex", "Drew"])
        for _ in 1..<19 { score.awardRally(to: 0); score.awardRally(to: 1) }
        score.awardRally(to: 1); score.awardRally(to: 1)
        XCTAssertEqual(score.frame.disciplineIndex, 2)
        XCTAssertEqual(pair(score), ["Alex", "Casey"])
        for _ in 0..<10 { score.awardRally(to: 0); score.awardRally(to: 1) }
        score.awardRally(to: 0)
        XCTAssertEqual(pair(score), ["Blair", "Drew"])
        XCTAssertEqual(score.frame.points, [11, 10])
    }

    func testRacketlonHalftimeReceiverChoicesAndGummiarmKeepSecondHalfPositions() {
        var score = match(.racketlon)
        for winner in [0, 1, 0] {
            for _ in 0..<19 { score.awardRally(to: 0); score.awardRally(to: 1) }
            score.awardRally(to: winner); score.awardRally(to: winner)
        }
        for _ in 0..<10 { score.awardRally(to: 0); score.awardRally(to: 1) }
        score.awardRally(to: 0)
        XCTAssertTrue(score.canSwapRacketlonReceivers)
        XCTAssertTrue(score.swapRacketlonReceivers(side: 0))
        XCTAssertEqual(score.frame.doublesService?.rightMembers[0], 1)
        score.awardRally(to: 1)
        XCTAssertFalse(score.canSwapRacketlonReceivers)
        for _ in 11..<19 { score.awardRally(to: 0); score.awardRally(to: 1) }
        score.awardRally(to: 1); score.awardRally(to: 1)
        XCTAssertTrue(score.frame.gummiarm)
        XCTAssertEqual(score.frame.doublesService?.rightMembers[0], 1)
        XCTAssertTrue(score.setServer(1))
        XCTAssertTrue(score.chooseGummiarmServer(member: 1))
        XCTAssertTrue(score.chooseServiceBox(.right))
        XCTAssertEqual(pair(score), ["Drew", "Blair"])
        score.awardRally(to: 1)
        XCTAssertTrue(score.frame.complete)
        score.undo()
        XCTAssertEqual(pair(score), ["Drew", "Blair"])
    }

    func testExpediteBetweenRalliesUsesPreviousReceiverAndContinuesAcrossGames() {
        var score = match(.tableTennis)
        score.awardRally(to: 0)
        XCTAssertEqual(pair(score), ["Alex", "Casey"])
        XCTAssertTrue(score.startExpedite(interruptedRally: false))
        XCTAssertEqual(pair(score), ["Casey", "Blair"])
        score.awardRally(to: 0)
        XCTAssertEqual(pair(score), ["Blair", "Drew"])
        for _ in 0..<9 { score.awardRally(to: 0) }
        XCTAssertEqual(score.frame.rounds.count, 1)
        XCTAssertTrue(score.frame.expedite == true)
        let server = score.frame.server
        score.awardRally(to: 0)
        XCTAssertNotEqual(score.frame.server, server)
    }

    func testExpediteInterruptedRallyKeepsServerAndCannotStartAfterEighteenPoints() {
        var score = match(.tableTennis)
        score.awardRally(to: 0)
        let names = pair(score)
        XCTAssertTrue(score.startExpedite(interruptedRally: true))
        XCTAssertEqual(pair(score), names)
        score.undo()
        XCTAssertNil(score.frame.expedite)
        score.awardRally(to: 1)
        for _ in 0..<8 { score.awardRally(to: 0); score.awardRally(to: 1) }
        XCTAssertFalse(score.startExpedite(interruptedRally: false))
    }

    func testAllNamedSportsFinishWithValidServiceCheckpointsAndUndoEveryRally() throws {
        for sport in CourtSport.allCases where sport != .custom {
            var score = match(sport)
            for _ in 0..<500 where !score.frame.complete {
                let before = score.frame
                XCTAssertTrue(score.awardRally(to: 0), sport.rawValue)
                XCTAssertNil(score.validationMessage, sport.rawValue)
                let after = score.frame
                XCTAssertTrue(score.undo()); XCTAssertEqual(score.frame, before)
                XCTAssertTrue(score.awardRally(to: 0)); XCTAssertEqual(score.frame, after)
            }
            XCTAssertTrue(score.frame.complete, sport.rawValue)
            XCTAssertEqual(try JSONDecoder().decode(CourtScoreSession.self, from: JSONEncoder().encode(score)), score)
        }
    }
}
