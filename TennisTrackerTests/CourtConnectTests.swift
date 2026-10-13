import XCTest
@testable import TennisTracker

@MainActor final class CourtConnectTests: XCTestCase {
    func testInvitationParserRejectsWrongOriginAndMalformedCodes() {
        let code=String(repeating:"a",count:64), host="connect.example.invalid"
        XCTAssertEqual(CourtConnectProtocol.code("https://\(host)/connect/invite#\(code)",host:host),code)
        XCTAssertEqual(CourtConnectProtocol.code(code,host:host),code)
        for value in ["http://\(host)/connect/invite#\(code)","https://evil.example/connect/invite#\(code)","https://\(host)/connect/invite?code=\(code)","https://user@\(host)/connect/invite#\(code)","https://\(host):443/connect/invite#\(code)",String(repeating:"a",count:63)] {
            XCTAssertNil(CourtConnectProtocol.code(value,host:host))
        }
    }
    func testCrossPlatformNoteIdentity() {
        XCTAssertEqual(CourtConnectProtocol.noteID(UUID(uuidString:"00000000-0000-0000-0000-000000000001")!).uuidString.lowercased(),"fe1cb8b1-724c-5eaf-b03c-6d003d053b48")
    }
    func testProjectionRequiresExplicitPlayerAndSeparatesNotes() throws {
        var player=PlayerProfile(); player.name="Synthetic athlete"
        var match=MatchRecord(playerID:player.id); match.notes="Private unless notes are approved"; match.setScores="6–4"
        var library=AppData(); library.players=[player]; library.matches=[match]
        XCTAssertTrue(try CourtConnect.projections(library,players:[]).isEmpty)
        let rows=try CourtConnect.projections(library,players:[player.id.uuidString.lowercased()])
        XCTAssertEqual(rows.count,2)
        let sporting=rows.first { $0["p_category"] as? String == "match" }!
        XCTAssertNil((sporting["p_body"] as? [String:Any])?["notes"])
        XCTAssertNil((sporting["p_body"] as? [String:Any])?["workout"])
        XCTAssertEqual((sporting["p_body"] as? [String:Any])?["score"] as? String,"6–4")
        XCTAssertEqual(library.matches[0],match)
    }
    func testAllSportingCategoriesStayUnderTheirExplicitPlayer() throws {
        let owner=PlayerProfile(), other=PlayerProfile()
        var match=MatchRecord(playerID:owner.id); match.notes="Shared note"; match.matchStory="Sporting reflection"; match.nextPracticeFocus="Practice volleys"; match.playerName="Synthetic player"; match.partnerName="Synthetic partner"; match.opponentName="Synthetic opponent"
        var training=TrainingSession(playerID:owner.id); training.focus="Footwork"; training.durationMinutes=45
        var tournament=TournamentRecord(playerID:owner.id); tournament.name="Synthetic event"; tournament.goal="Consistent serves"
        var library=AppData(); library.players=[owner,other]; library.matches=[match,MatchRecord(playerID:other.id)]; library.trainingSessions=[training]; library.tournaments=[tournament]
        let projected=try CourtConnect.projections(library,players:[owner.id.uuidString.lowercased()])
        XCTAssertEqual(Set(projected.compactMap { $0["p_category"] as? String }),Set(CourtConnectProtocol.categories))
        XCTAssertTrue(projected.allSatisfy { $0["p_player"] as? String == owner.id.uuidString.lowercased() })
        let people=projected.first { $0["p_category"] as? String == "match" }?["p_people"] as? [[String:Any]]
        XCTAssertEqual(people?.count,3)
        XCTAssertEqual(people?[1]["team"] as? Int,0)
        XCTAssertEqual(people?[2]["team"] as? Int,1)
        XCTAssertEqual(Set(projected.compactMap { $0["p_id"] as? String }).count,projected.count)
    }
    func testTrainingPlanSharesSportingFieldsAndSeparatesReview() throws {
        let owner=PlayerProfile()
        var training=TrainingSession(playerID:owner.id)
        var plan=CourtSessionPlan(); plan.objective="Serve placement"; plan.drills="Ten serves"; plan.equipment="Racket"; plan.successMeasure="Eight in target"; plan.review="Improving"; plan.adaptations="Sensitive access information"
        training.court.plan=plan; training.court.surface="Clay"
        var library=AppData(); library.players=[owner]; library.trainingSessions=[training]
        let rows=try CourtConnect.projections(library,players:[owner.id.uuidString.lowercased()])
        let body=rows.first { $0["p_category"] as? String == "training" }?["p_body"] as? [String:Any]
        XCTAssertEqual(body?["planObjective"] as? String,"Serve placement")
        XCTAssertEqual(body?["surface"] as? String,"Clay")
        XCTAssertNil(body?["adaptations"]); XCTAssertNil(body?["review"])
        let serialized=String(data:try JSONSerialization.data(withJSONObject:rows),encoding:.utf8)!
        XCTAssertFalse(serialized.contains("Sensitive access information"))
        XCTAssertTrue(rows.contains { $0["p_category"] as? String == "reflection" })
    }
    func testNativeSportScoreHasSharedReadableSummary() throws {
        let owner=PlayerProfile()
        var match=MatchRecord(playerID:owner.id)
        match.court.score=CourtScoreSession(sport:.tennis,rules:CourtScoringRules(),sides:[CourtScoreSide(name:"Synthetic side A"),CourtScoreSide(name:"Synthetic side B")])
        var library=AppData(); library.players=[owner]; library.matches=[match]
        let rows=try CourtConnect.projections(library,players:[owner.id.uuidString.lowercased()])
        let body=rows.first { $0["p_category"] as? String == "match" }?["p_body"] as? [String:Any]
        XCTAssertEqual(body?["customScoreSummary"] as? String,match.court.score!.summary + ". " + match.court.score!.resultSummary)
        XCTAssertNil(body?["history"]); XCTAssertNil(body?["access"])
    }
}
