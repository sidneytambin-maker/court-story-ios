import XCTest
@testable import TennisTracker

final class TennisTournamentStatusTests: XCTestCase {
    func testCompletionAndReopeningHaveStateSpecificActionsAndAnnouncements() {
        let entered = fixture()
        XCTAssertEqual(entered.completionActionTitle, "Mark Tournament Complete")
        XCTAssertEqual(entered.statusText, "Entered")
        let completed = entered.togglingCompletion(now: entered.modifiedAt)
        XCTAssertEqual(completed.finalResult, .completed)
        XCTAssertTrue(completed.isCompleted)
        XCTAssertEqual(completed.statusText, "Completed")
        XCTAssertEqual(completed.completionActionTitle, "Mark Tournament Entered")
        XCTAssertEqual(completed.completionActionSymbol, "arrow.uturn.backward")
        XCTAssertEqual(completed.completionAnnouncement, "Tournament Example Open marked complete.")
        let reopened = completed.togglingCompletion(now: entered.modifiedAt)
        XCTAssertEqual(reopened.finalResult, .entered)
        XCTAssertFalse(reopened.isCompleted)
        XCTAssertEqual(reopened.completionActionTitle, "Mark Tournament Complete")
        XCTAssertEqual(reopened.completionAnnouncement, "Tournament Example Open marked entered.")
        XCTAssertEqual(reopened.revision, entered.revision + 2)
        XCTAssertTrue(reopened.hasExplicitStatus)
        var expected = entered
        expected.hasExplicitStatus = true
        expected.revision += 2
        XCTAssertEqual(reopened, expected)
    }

    func testHistoricalAutoCompletionIsPreservedUntilExplicitlyReopened() throws {
        var legacy = fixture()
        legacy.date = Date(timeIntervalSince1970: 1_000)
        legacy.endDate = Date(timeIntervalSince1970: 2_000)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.tennisTracker.encode(legacy)) as? [String: Any])
        json.removeValue(forKey: "hasExplicitStatus")
        let restored = try JSONDecoder.tennisTracker.decode(TournamentRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(restored.isCompleted)
        XCTAssertFalse(restored.hasExplicitStatus)
        XCTAssertEqual(restored.finalResult, .entered)
        XCTAssertEqual(restored.statusText, "Completed")
        let reopened: TournamentRecord = try roundTrip(restored.togglingCompletion())
        XCTAssertFalse(reopened.isCompleted)
        XCTAssertEqual(reopened.finalResult, .entered)
        XCTAssertEqual(reopened.statusText, "Entered")
        XCTAssertEqual(reopened.date, restored.date)
        XCTAssertEqual(reopened.endDate, restored.endDate)
        XCTAssertEqual(reopened.stageReached, restored.stageReached)
        XCTAssertEqual(reopened.finishingPosition, restored.finishingPosition)
        XCTAssertTrue(try roundTrip(reopened.togglingCompletion()).isCompleted)
    }

    func testCompletionFinishesActiveTimingAndReopeningKeepsRecordedTimes() {
        var active = fixture()
        active.finalResult = .inProgress
        active.hasExplicitStatus = true
        active.actualStart = active.date
        let finish = active.date.addingTimeInterval(600)
        let completed = active.togglingCompletion(now: finish)
        XCTAssertEqual(completed.actualStart, active.actualStart)
        XCTAssertEqual(completed.actualFinish, finish)
        let reopened = completed.togglingCompletion(now: finish)
        XCTAssertEqual(reopened.actualFinish, finish)
        XCTAssertEqual(reopened.actualStart, active.actualStart)
        XCTAssertFalse(reopened.isCompleted)
    }

    func testStatusToggleDoesNotClaimUnrecordedTimingOrAlterDetails() {
        let entered = fixture()
        let completed = entered.togglingCompletion()
        XCTAssertNil(completed.actualStart)
        XCTAssertNil(completed.actualFinish)
        XCTAssertEqual(completed.stageReached, entered.stageReached)
        XCTAssertEqual(completed.finishingPosition, entered.finishingPosition)
        XCTAssertEqual(completed.matchesPlayed, entered.matchesPlayed)
        XCTAssertEqual(completed.needsDetails, entered.needsDetails)
        XCTAssertEqual(completed.notes, entered.notes)
        XCTAssertEqual(completed.goal, entered.goal)
        XCTAssertEqual(completed.id, entered.id)
    }

    func testWatchDetailsEditorCannotUndoConcurrentStatusToggle() {
        let original = fixture()
        var draft = original
        draft.notes = "Edited notes"
        let completed = original.togglingCompletion()
        let saved = TennisWatchRecordEdits.tournament(draft, current: completed)
        XCTAssertEqual(saved.finalResult, .completed)
        XCTAssertTrue(saved.hasExplicitStatus)
        XCTAssertEqual(saved.notes, "Edited notes")
        XCTAssertEqual(saved.stageReached, original.stageReached)
        XCTAssertEqual(saved.finishingPosition, original.finishingPosition)
    }

    func testOfflineReopenSurvivesCompletedSnapshotAndSyncAcknowledgement() throws {
        let completed = fixture().togglingCompletion()
        let reopened: TournamentRecord = try roundTrip(completed.togglingCompletion())
        var snapshot = TennisWatchSnapshot()
        snapshot.tournaments = [completed]
        let command: TennisWatchSyncCommand = try roundTrip(.upsertTournament(reopened))
        let pending = TennisWatchReconciliation.reconcile(incoming: snapshot, pending: [command])
        XCTAssertEqual(pending.snapshot.tournaments, [reopened])
        XCTAssertEqual(pending.pending, [command])
        snapshot.tournaments = [reopened]
        let acknowledged = TennisWatchReconciliation.reconcile(incoming: try roundTrip(snapshot), pending: pending.pending)
        XCTAssertTrue(acknowledged.pending.isEmpty)
        XCTAssertEqual(acknowledged.snapshot.tournaments, [reopened])
        XCTAssertFalse(acknowledged.snapshot.tournaments[0].isCompleted)
    }

    @MainActor func testPhoneStatusActionsSaveImmediatelyAnnounceAndSyncReversal() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        var original = fixture()
        original.date = Date(timeIntervalSince1970: 1_000)
        original.endDate = Date(timeIntervalSince1970: 2_000)
        original.hasExplicitStatus = true
        var match = MatchRecord(playerID: original.playerID)
        match.tournamentID = original.id
        match.notes = "Keep linked match"
        var data = AppData()
        data.tournaments = [original]
        data.matches = [match]
        data = try roundTrip(data)
        try JSONEncoder.tennisTracker.encode(data).write(to: url)
        let phone = TennisStore(storeURL: url)
        var announcements: [String] = []
        phone.announcementDelivery = { announcements.append($0) }

        phone.toggleTournamentCompletion(original.id)
        let completed = try XCTUnwrap(TennisStore(storeURL: url).data.tournaments.first)
        XCTAssertTrue(completed.isCompleted)
        XCTAssertEqual(completed.finalResult, .completed)
        XCTAssertEqual(announcements, ["Tournament Example Open marked complete."])
        let snapshot: TennisWatchSnapshot = try roundTrip(TennisWatchSnapshot(data: phone.data, including: original.id))
        let onWatch = try XCTUnwrap(snapshot.tournaments.first)
        XCTAssertEqual(onWatch, completed)

        let reopened = onWatch.togglingCompletion()
        phone.applyWatchCommand(try roundTrip(TennisWatchSyncCommand.upsertTournament(reopened)))
        let reloaded = TennisStore(storeURL: url)
        XCTAssertFalse(try XCTUnwrap(reloaded.data.tournaments.first).isCompleted)
        XCTAssertEqual(reloaded.data.tournaments.first?.stageReached, original.stageReached)
        XCTAssertEqual(reloaded.data.tournaments.first?.finishingPosition, original.finishingPosition)
        XCTAssertEqual(reloaded.data.matches, data.matches)
        reloaded.announcementDelivery = { announcements.append($0) }
        reloaded.toggleTournamentCompletion(original.id)
        reloaded.toggleTournamentCompletion(original.id)
        XCTAssertEqual(announcements.last, "Tournament Example Open marked entered.")
        let final = try XCTUnwrap(TennisStore(storeURL: url).data.tournaments.first)
        XCTAssertFalse(final.isCompleted)
        XCTAssertEqual(final.finalResult, .entered)
        XCTAssertEqual(final.finishingPosition, 6)
        XCTAssertEqual(final.stageReached, .fifthSixthPlayOff)
        reloaded.applyWatchCommand(.upsertTournament(completed))
        XCTAssertEqual(reloaded.data.tournaments.first?.finalResult, .entered)
    }

    @MainActor func testDeletedTournamentCannotBeRecreatedByStatusAction() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TennisStore(storeURL: url)
        let tournament = fixture()
        store.upsertTournament(tournament)
        store.deleteTournamentKeepingMatches(tournament)
        store.toggleTournamentCompletion(tournament.id)
        XCTAssertTrue(store.data.tournaments.isEmpty)
        XCTAssertTrue(store.data.deletedRecordIDs.contains(tournament.id))
    }

    private func fixture() -> TournamentRecord {
        var tournament = TournamentRecord(playerID: UUID())
        tournament.name = "Example Open"
        tournament.date = Date(timeIntervalSince1970: 1_800_000_000)
        tournament.endDate = .distantFuture
        tournament.modifiedAt = tournament.date
        tournament.stageReached = .fifthSixthPlayOff
        tournament.finishingPosition = 6
        tournament.matchesPlayed = 4
        tournament.needsDetails = true
        tournament.notes = "Keep notes"
        tournament.goal = "Keep goal"
        return tournament
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder.tennisTracker.decode(T.self, from: JSONEncoder.tennisTracker.encode(value))
    }
}
