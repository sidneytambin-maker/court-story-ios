import XCTest
@testable import TennisTracker

final class CourtSyncTests: XCTestCase {
    func testHealthOwnerIsIndependentOfSelectedAthleteAndRequiresAnExistingPersonalProfile() {
        var owner = PlayerProfile(); owner.name = "Demo Owner"
        var athlete = PlayerProfile(); athlete.name = "Demo Athlete"; athlete.court.coachOwnerID = owner.id
        var snapshot = TennisWatchSnapshot()
        snapshot.players = [owner, athlete]
        snapshot.court.deviceOwnerPlayerID = owner.id
        snapshot.selectedPlayerID = athlete.id
        XCTAssertTrue(snapshot.mayUseHealth(for: owner.id))
        XCTAssertFalse(snapshot.mayUseHealth(for: athlete.id))
        snapshot.players.removeAll { $0.id == owner.id }
        XCTAssertFalse(snapshot.mayUseHealth(for: owner.id))
        snapshot.court.deviceOwnerPlayerID = athlete.id
        XCTAssertFalse(snapshot.mayUseHealth(for: athlete.id))
    }

    func testSelectedSportScopesAllTimeHistoryAndLeavesOtherRecordsUntouched() {
        let owner = UUID(), other = UUID()
        var tennis = MatchRecord(playerID: owner); tennis.status = .completed
        var badminton = tennis; badminton.id = UUID(); badminton.court.sport = CourtSportSelection(sport: .badminton)
        var anotherPlayer = badminton; anotherPlayer.id = UUID(); anotherPlayer.playerID = other
        var snapshot = TennisWatchSnapshot()
        snapshot.matches = [tennis, badminton, anotherPlayer]
        snapshot.achievementHistory = TennisAchievementRecord.collect(matches: snapshot.matches, training: [], tournaments: [])
        let scoped = snapshot.scoped(playerID: owner, sport: badminton.court.sport)
        XCTAssertEqual(scoped.matches.map(\.id), [badminton.id])
        XCTAssertEqual(scoped.achievementHistory.map(\.id), [badminton.id])
        XCTAssertEqual(snapshot.matches.count, 3)
        XCTAssertEqual(snapshot.achievementHistory.count, 3)
    }

    func testArchivingSelectedAthleteRestoresOwnerSelectionWithoutDeletingHistory() {
        var owner = PlayerProfile(); owner.name = "Demo Coach"
        owner.court.sports[0].role = .coach
        var athlete = PlayerProfile(); athlete.name = "Demo Athlete"; athlete.court.coachOwnerID = owner.id
        var data = AppData(); data.players = [owner, athlete]
        data.court.ownerPlayerID = owner.id; data.court.activeAthleteID = athlete.id; data.selectedPlayerID = athlete.id
        let match = MatchRecord(playerID: athlete.id); data.matches = [match]
        athlete.court.archivedAt = Date(); athlete.court.revision += 1
        XCTAssertTrue(CourtWatchMutation.profile(athlete).apply(to: &data))
        XCTAssertNil(data.court.activeAthleteID)
        XCTAssertEqual(data.selectedPlayerID, owner.id)
        XCTAssertEqual(data.matches, [match])
        XCTAssertNil(CourtLibraryValidation.message(in: data))
    }

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
