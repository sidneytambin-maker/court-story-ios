import XCTest
@testable import TennisTracker

final class CourtSyncTests: XCTestCase {
    func testLegacySnapshotKeepsOldTennisTotalsWithoutMixingSportsOrUnsupportedResults() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var owner = PlayerProfile(); owner.name = "Demo Owner"
        var athlete = PlayerProfile(); athlete.name = "Demo Athlete"
        athlete.court.coachOwnerID = owner.id
        var old = MatchRecord(playerID: owner.id)
        old.date = now.addingTimeInterval(-100 * 86400); old.status = .completed
        old.needsDetails = false; old.result = .win
        var badminton = old; badminton.id = UUID(); badminton.court.sport = CourtSportSelection(sport: .badminton)
        var modern = old; modern.id = UUID(); modern.court.rules = .standard(for: .tennis)
        var coached = old; coached.id = UUID(); coached.playerID = athlete.id; coached.court.enteredByCoachID = owner.id
        var data = AppData()
        data.players = [owner, athlete]; data.selectedPlayerID = owner.id
        data.court.ownerPlayerID = owner.id; data.court.deviceOwnerPlayerID = owner.id
        data.matches = [old, badminton, modern, coached]
        let all = TennisWatchSnapshot(data: data, now: now, including: modern.id)
        XCTAssertEqual(all.achievementHistory.count, 4)
        XCTAssertTrue(all.matches.contains { $0.id == modern.id })
        let legacy = all.legacyCompatible
        XCTAssertEqual(legacy.achievementHistory.map(\.id), [old.id])
        XCTAssertFalse(legacy.matches.contains { $0.id == modern.id })
        XCTAssertEqual(legacy.requestedActivityFound, false)
        XCTAssertEqual(legacy.players.map(\.id), [owner.id])
        XCTAssertEqual(legacy.achievements.first { $0.id == "match.1" }?.progress, 1)
    }

    func testOldAchievementWireDataStillDecodesAsLegacyTennis() throws {
        let old = TennisAchievementRecord(id: UUID(), playerID: UUID(), date: Date(timeIntervalSince1970: 100), metrics: ["match"])
        let bytes = try JSONEncoder.tennisTracker.encode(old)
        let decoded = try JSONDecoder.tennisTracker.decode(TennisAchievementRecord.self, from: bytes)
        XCTAssertNil(decoded.courtSport)
        XCTAssertNil(decoded.usesCourtScoring)
        var snapshot = TennisWatchSnapshot()
        snapshot.selectedPlayerID = old.playerID
        snapshot.achievementHistory = [decoded]
        XCTAssertEqual(snapshot.legacyCompatible.achievementHistory, [old])
    }

    func testLegacyWatchCannotChangeOfficialCourtFormatOrScoringRecord() {
        var person = PlayerProfile(); person.name = "Demo Player"
        var record = MatchRecord(playerID: person.id)
        record.court = CourtActivity(player: person)
        record.configureNewCourtMatch()
        var data = AppData(); data.players = [person]; data.selectedPlayerID = person.id; data.matches = [record]
        var oldClient = record; oldClient.court = CourtActivity()
        XCTAssertNil(CourtSyncCompatibility.command(.upsertMatch(oldClient), protocolVersion: 1, data: data))
        XCTAssertNil(CourtSyncCompatibility.command(.markMatchDetailsComplete(record.id), protocolVersion: 1, data: data))
        XCTAssertNil(CourtSyncCompatibility.command(.deleteRecord(TennisRecordDeletion(id: record.id, kind: .match)), protocolVersion: 1, data: data))
        XCTAssertNotNil(CourtSyncCompatibility.command(.upsertMatch(record), protocolVersion: 2, data: data))
    }
}
