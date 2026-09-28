import XCTest
@testable import TennisTracker

final class TennisWatchFocusRetentionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFortyRecordedSessionsKeepPhoneFocusTotalsAfterWireRoundTrip() throws {
        var data = library()
        data.trainingSessions = recentSessions(playerID: data.selectedPlayerID!)
        for index in data.trainingSessions.indices {
            if index.isMultiple(of: 3) {
                data.trainingSessions[index].actualStart = nil
                data.trainingSessions[index].actualFinish = nil
            }
            if index.isMultiple(of: 5) { data.trainingSessions[index].focus = "" }
            else if index.isMultiple(of: 4) {
                data.trainingSessions[index].additionalFocus = [TennisTrainingFocus.footwork.rawValue]
            }
        }
        let snapshot = TennisWatchSnapshot(data: data, now: now)
        XCTAssertEqual(snapshot.trainingSessions.count, 40)
        XCTAssertEqual(Set(snapshot.trainingSessions.map(\.id)), Set(data.trainingSessions.map(\.id)))
        assertFocusParity(data, snapshot)
        let decoded = try JSONDecoder.tennisTracker.decode(TennisWatchSnapshot.self, from: JSONEncoder.tennisTracker.encode(snapshot))
        XCTAssertEqual(decoded.trainingSessions, snapshot.trainingSessions)
        assertFocusParity(data, decoded)
    }

    func testOldScheduledDateKeepsRecentlyStartedAndFinishedTraining() {
        var data = library()
        var completed = session(playerID: data.selectedPlayerID!, date: now.addingTimeInterval(-120 * 86_400))
        completed.actualStart = now.addingTimeInterval(-1200)
        completed.actualFinish = now
        data.trainingSessions = [completed]
        let snapshot = TennisWatchSnapshot(data: data, now: now)
        XCTAssertEqual(snapshot.trainingSessions, [completed])
        assertFocusParity(data, snapshot)
        let progress = TennisPlayerProgress.build(player: data.players[0], matches: [], training: snapshot.trainingSessions, now: now)
        XCTAssertEqual(progress.focus, [TennisFocusProgress(focus: TennisTrainingFocus.serves.rawValue, sessions: 1, seconds: 1200)])
    }

    func testFocusWindowUsesActualStartOrDateAndIncludesBothBoundaries() {
        var data = library()
        let playerID = data.selectedPlayerID!
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Calendar.current.startOfDay(for: now))!
        let distantDate = now.addingTimeInterval(-120 * 86_400)
        let fillers = Array(recentSessions(playerID: playerID).prefix(30))
        var atStart = session(playerID: playerID, date: start)
        atStart.date = distantDate
        var atEnd = session(playerID: playerID, date: now)
        atEnd.date = distantDate
        atEnd.actualFinish = now
        var dateOnly = session(playerID: playerID, date: start)
        dateOnly.actualStart = nil
        dateOnly.actualFinish = nil
        var beforeStart = session(playerID: playerID, date: start.addingTimeInterval(-1))
        beforeStart.date = now.addingTimeInterval(-20 * 86_400)
        var beforeDateOnly = session(playerID: playerID, date: start.addingTimeInterval(-1))
        beforeDateOnly.actualStart = nil
        beforeDateOnly.actualFinish = nil
        var afterEnd = session(playerID: playerID, date: now.addingTimeInterval(1))
        afterEnd.date = distantDate
        data.trainingSessions = fillers + [beforeStart, beforeDateOnly, afterEnd, atStart, atEnd, dateOnly]
        let snapshot = TennisWatchSnapshot(data: data, now: now)
        XCTAssertEqual(Set(snapshot.trainingSessions.map(\.id)), Set((fillers + [atStart, atEnd, dateOnly]).map(\.id)))
        XCTAssertEqual(snapshot.trainingSessions.count, 33)
        assertFocusParity(data, snapshot)
    }

    func testRecordedHistoryOutsideFocusWindowRemainsBounded() {
        var data = library()
        let playerID = data.selectedPlayerID!
        let older = (0..<40).map { index in
            session(playerID: playerID, date: now.addingTimeInterval(-35 * 86_400 - Double(index) * 3600))
        }
        let archived = (0..<40).map { index in
            session(playerID: playerID, date: now.addingTimeInterval(Double(-100 - index) * 86_400))
        }
        data.trainingSessions = older + archived
        let snapshot = TennisWatchSnapshot(data: data, now: now)
        XCTAssertEqual(snapshot.trainingSessions.count, 30)
        XCTAssertEqual(snapshot.trainingSessions.map(\.id), older.prefix(30).map(\.id))
        XCTAssertEqual(snapshot.achievementHistory.count, 80)
        assertFocusParity(data, snapshot)
        XCTAssertTrue(TennisPlayerProgress.build(player: data.players[0], matches: [], training: snapshot.trainingSessions, now: now).focus.isEmpty)
    }

    func testFocusRetentionPreservesActiveScheduledWeeklyAndPendingDetailsRecords() {
        var data = library()
        let playerID = data.selectedPlayerID!
        let recorded = recentSessions(playerID: playerID)
        let scheduled = (0..<30).map { index -> TrainingSession in
            var record = session(playerID: playerID, date: now.addingTimeInterval(86_400 + Double(index) * 3600))
            record.actualStart = nil
            record.actualFinish = nil
            return record
        }
        var active = session(playerID: playerID, date: now.addingTimeInterval(-100 * 86_400))
        active.actualFinish = nil
        var pending = session(playerID: playerID, date: now.addingTimeInterval(-100 * 86_400))
        pending.needsDetails = true
        var weekly = session(playerID: playerID, date: now)
        weekly.actualStart = nil
        weekly.actualFinish = nil
        data.trainingSessions = recorded + scheduled + [active, pending, weekly]
        let snapshot = TennisWatchSnapshot(data: data, now: now)
        XCTAssertEqual(Set(snapshot.trainingSessions.map(\.id)), Set(data.trainingSessions.map(\.id)))
        XCTAssertEqual(snapshot.trainingSessions.count, 73)
        assertFocusParity(data, snapshot)
        let progress = TennisPlayerProgress.build(player: data.players[0], matches: [], training: snapshot.trainingSessions, now: now)
        XCTAssertEqual(progress.trainingTypes.reduce(0) { $0 + $1.sessions }, 40)
    }

    private func assertFocusParity(_ data: AppData, _ snapshot: TennisWatchSnapshot,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let player = data.players.first { $0.id == data.selectedPlayerID }
        let phone = TennisPlayerProgress.build(player: player, matches: [], training: data.trainingSessions, now: now)
        let watch = TennisPlayerProgress.build(player: player, matches: [], training: snapshot.trainingSessions, now: now)
        XCTAssertEqual(watch.focus, phone.focus, file: file, line: line)
        XCTAssertEqual(watch.trainingTypes, phone.trainingTypes, file: file, line: line)
        XCTAssertEqual(watch.trainingNeedingFocus, phone.trainingNeedingFocus, file: file, line: line)
    }

    private func library() -> AppData {
        var data = AppData()
        var player = PlayerProfile()
        player.name = "Focus Example"
        data.players = [player]
        data.selectedPlayerID = player.id
        return data
    }

    private func recentSessions(playerID: UUID) -> [TrainingSession] {
        (0..<40).map { index in
            var record = session(playerID: playerID, date: now.addingTimeInterval(-10 * 86_400 + Double(index) * 3600))
            record.focus = index.isMultiple(of: 2) ? TennisTrainingFocus.serves.rawValue : TennisTrainingFocus.returns.rawValue
            return record
        }
    }

    private func session(playerID: UUID, date: Date) -> TrainingSession {
        var record = TrainingSession(playerID: playerID)
        record.modifiedAt = now
        record.date = date
        record.actualStart = date
        record.actualFinish = date.addingTimeInterval(600)
        record.durationMinutes = 10
        record.focus = TennisTrainingFocus.serves.rawValue
        return record
    }
}
