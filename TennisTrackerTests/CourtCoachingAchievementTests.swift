import XCTest
@testable import TennisTracker

final class CourtCoachingAchievementTests: XCTestCase {
    func testCoachingAwardsMatchReferenceAndUseUniquePastSessionsAndPlayers() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var coach = PlayerProfile(); coach.name = "Demo Coach"; coach.court.sports[0].role = .coach
        let athletes = (1...3).map { index -> PlayerProfile in
            var player = PlayerProfile(); player.name = "Demo Athlete \(index)"; player.court.coachOwnerID = coach.id
            return player
        }
        var data = AppData(); data.players = [coach] + athletes; data.selectedPlayerID = coach.id
        data.court.ownerPlayerID = coach.id; data.court.deviceOwnerPlayerID = coach.id
        let sessions = (0..<10).map { index -> TrainingSession in
            var session = TrainingSession(playerID: athletes[index % 3].id)
            session.court = CourtActivity(player: athletes[index % 3], coachID: coach.id)
            session.date = now.addingTimeInterval(-100 * 86400 - Double(index * 3600))
            session.actualStart = session.date; session.actualFinish = session.date.addingTimeInterval(1800)
            session.durationMinutes = 30; session.needsDetails = false
            session.context.participantIDs = athletes.map(\.id)
            return session
        }
        var planned = sessions[0]; planned.id = UUID(); planned.actualStart = nil; planned.actualFinish = nil; planned.date = now.addingTimeInterval(86400)
        var future = sessions[0]; future.id = UUID(); future.date = now.addingTimeInterval(86400); future.actualFinish = future.date
        var own = sessions[0]; own.id = UUID(); own.playerID = coach.id
        var zero = sessions[0]; zero.id = UUID(); zero.durationMinutes = 0; zero.actualFinish = zero.actualStart
        data.trainingSessions = sessions + [sessions[0], planned, future, own, zero]
        data.players[1].court.archivedAt = now
        let raw = TennisAchievementRecord.collect(matches: [], training: data.trainingSessions, tournaments: [], now: now, players: data.players)
        let badges = TennisAchievement.build(records: raw, playerID: coach.id)
        XCTAssertEqual(badges.count, 25)
        XCTAssertEqual(badges.first { $0.id == "coach.1" }?.title, "A Coaching Beginning")
        XCTAssertEqual(badges.first { $0.id == "coach.10" }?.progress, 10)
        XCTAssertEqual(badges.first { $0.id == "coach.players3" }?.progress, 3)
        XCTAssertEqual(badges.filter { $0.id.hasPrefix("coach.") && $0.earned }.count, 3)

        let snapshot = TennisWatchSnapshot(data: data, now: now).scoped(playerID: coach.id, sport: .tennis)
        XCTAssertTrue(snapshot.trainingSessions.allSatisfy { $0.playerID == coach.id })
        XCTAssertEqual(snapshot.achievements.first { $0.id == "coach.10" }?.progress, 10)
        let badminton = TennisWatchSnapshot(data: data, now: now).scoped(playerID: coach.id, sport: CourtSportSelection(sport: .badminton))
        XCTAssertEqual(badminton.achievements.first { $0.id == "coach.10" }?.progress, 0)
        let removed = TennisAchievementRecord.merge(history: raw, current: [], deleted: [sessions[0].id])
        XCTAssertEqual(TennisAchievement.build(records: removed, playerID: coach.id).first { $0.id == "coach.10" }?.progress, 9)
    }

    func testMissingAthleteAndUnrelatedParticipantNeverEarnCoachingCredit() {
        let now = Date()
        var coach = PlayerProfile(); coach.name = "Demo Coach"
        var unrelated = PlayerProfile(); unrelated.name = "Demo Other"
        var session = TrainingSession(playerID: unrelated.id)
        session.court.enteredByCoachID = coach.id
        session.date = now.addingTimeInterval(-3600); session.actualStart = session.date
        session.actualFinish = now.addingTimeInterval(-1800); session.durationMinutes = 30
        let records = TennisAchievementRecord.collect(matches: [], training: [session], tournaments: [], now: now, players: [coach, unrelated])
        XCTAssertNil(records[0].coachID)
        XCTAssertNil(records[0].coachedPlayerIDs)
        XCTAssertFalse(TennisAchievement.build(records: records, playerID: coach.id).contains { $0.id.hasPrefix("coach.") && $0.earned })
    }
}
