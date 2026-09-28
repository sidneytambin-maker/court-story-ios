import XCTest
@testable import TennisTracker

@MainActor
final class TennisWatchNavigationTests: XCTestCase {
    private func store() -> TennisStore {
        TennisStore(storeURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
    }

    func testWatchDeletionSurvivesDelayedTrainingAndStalePhoneEditor() throws {
        let phone = store()
        var training = TrainingSession(playerID: UUID())
        phone.upsertTraining(training)
        let deletion = TennisRecordDeletion(id: training.id, kind: .training)
        phone.applyWatchCommand(.deleteRecord(deletion))
        training.revision = 100
        phone.applyWatchCommand(.upsertTraining(training))
        phone.upsertTraining(training)
        XCTAssertTrue(phone.data.trainingSessions.isEmpty)
        XCTAssertTrue(phone.data.deletedRecordIDs.contains(training.id))
        let decoded = try JSONDecoder.tennisTracker.decode(AppData.self, from: JSONEncoder.tennisTracker.encode(phone.data))
        XCTAssertTrue(decoded.deletedRecordIDs.contains(training.id))
    }

    func testOfflineDeletionIsNotAcknowledgedByAHistoryLimitedSnapshot() {
        let id = UUID()
        let command = TennisWatchSyncCommand.deleteRecord(TennisRecordDeletion(id: id, kind: .training))
        let pending = TennisWatchReconciliation.reconcile(incoming: .empty, pending: [command])
        XCTAssertEqual(pending.pending, [command])
        var acknowledged = TennisWatchSnapshot()
        acknowledged.deletedRecordIDs.insert(id)
        XCTAssertTrue(TennisWatchReconciliation.reconcile(incoming: acknowledged, pending: [command]).pending.isEmpty)
    }

    func testAcknowledgedDeletionStillWinsOverAnOldSnapshot() {
        let training = TrainingSession(playerID: UUID())
        var stale = TennisWatchSnapshot(); stale.trainingSessions = [training]
        let result = TennisWatchReconciliation.reconcile(incoming: stale, pending: [], localDeletedIDs: [training.id])
        XCTAssertTrue(result.snapshot.trainingSessions.isEmpty)
        XCTAssertTrue(result.snapshot.deletedRecordIDs.contains(training.id))
    }

    func testPhoneDeletionCancelsQueuedWatchUpsert() {
        let match = MatchRecord(playerID: UUID())
        var incoming = TennisWatchSnapshot(); incoming.deletedRecordIDs.insert(match.id)
        let result = TennisWatchReconciliation.reconcile(incoming: incoming, pending: [.upsertMatch(match)])
        XCTAssertTrue(result.snapshot.matches.isEmpty)
        XCTAssertTrue(result.pending.isEmpty)
    }

    func testMultipleOfflineDeletesRemainPendingIndependently() throws {
        let commands: [TennisWatchSyncCommand] = [
            .deleteRecord(TennisRecordDeletion(id: UUID(), kind: .training)),
            .deleteRecord(TennisRecordDeletion(id: UUID(), kind: .match))
        ]
        let wire = try JSONDecoder.tennisTracker.decode([TennisWatchSyncCommand].self, from: JSONEncoder.tennisTracker.encode(commands))
        let result = TennisWatchReconciliation.reconcile(incoming: .empty, pending: wire)
        XCTAssertEqual(result.pending.count, 2)
        XCTAssertEqual(result.snapshot.deletedRecordIDs.count, 2)
    }

    func testTournamentDeleteKeepsMatchesAndDetachesTraining() {
        let phone = store()
        let tournament = TournamentRecord(playerID: UUID())
        var match = MatchRecord(playerID: tournament.playerID); match.tournamentID = tournament.id
        var training = TrainingSession(playerID: tournament.playerID); training.context.tournamentID = tournament.id
        phone.upsertTournament(tournament); phone.upsertMatch(match); phone.upsertTraining(training)
        phone.applyWatchCommand(.deleteRecord(TennisRecordDeletion(id: tournament.id, kind: .tournament)))
        XCTAssertTrue(phone.data.tournaments.isEmpty)
        XCTAssertEqual(phone.data.matches.count, 1)
        XCTAssertNil(phone.data.matches.first?.tournamentID)
        XCTAssertNil(phone.data.trainingSessions.first?.context.tournamentID)
        phone.applyWatchCommand(.upsertMatch(match))
        XCTAssertNil(phone.data.matches.first?.tournamentID)
    }

    func testTournamentCascadeDeletesAllLinkedMatchesButNotUnrelatedRecords() {
        let phone = store()
        let tournament = TournamentRecord(playerID: UUID())
        var linked = MatchRecord(playerID: tournament.playerID); linked.tournamentID = tournament.id
        let unrelated = MatchRecord(playerID: tournament.playerID)
        phone.upsertTournament(tournament); phone.upsertMatch(linked); phone.upsertMatch(unrelated)
        phone.applyWatchCommand(.deleteRecord(TennisRecordDeletion(id: tournament.id, kind: .tournament, includeLinkedMatches: true)))
        phone.applyWatchCommand(.upsertMatch(linked))
        XCTAssertEqual(phone.data.matches.map(\.id), [unrelated.id])
        XCTAssertTrue(phone.data.deletedRecordIDs.contains(linked.id))
    }

    func testLegacyDataAndSnapshotDecodeWithoutTombstones() throws {
        let json = Data("{}".utf8)
        XCTAssertTrue(try JSONDecoder.tennisTracker.decode(AppData.self, from: json).deletedRecordIDs.isEmpty)
        XCTAssertTrue(try JSONDecoder.tennisTracker.decode(TennisWatchSnapshot.self, from: json).deletedRecordIDs.isEmpty)
    }

    func testScheduledTrainingWindowIncludesFifteenMinuteBoundaryOnly() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let player = UUID()
        var snapshot = TennisWatchSnapshot(); snapshot.selectedPlayerID = player
        for offset in [-901.0, -900, 0, 900, 901] {
            var training = TrainingSession(playerID: player); training.date = now.addingTimeInterval(offset); training.hasStartTime = true
            snapshot.trainingSessions.append(training)
        }
        let candidates = TennisScheduling.nearbyTraining(in: snapshot, now: now)
        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(candidates.first?.date, now)
    }

    func testQuickStartExcludesUntimedStartedFinishedDeletedAndOtherPlayers() {
        let now = Date()
        let player = UUID()
        var snapshot = TennisWatchSnapshot(); snapshot.selectedPlayerID = player
        var eligible = TrainingSession(playerID: player); eligible.date = now; eligible.hasStartTime = true
        var untimed = eligible; untimed.id = UUID(); untimed.hasStartTime = false
        var started = eligible; started.id = UUID(); started.actualStart = now
        var finished = eligible; finished.id = UUID(); finished.actualFinish = now
        var other = eligible; other.id = UUID(); other.playerID = UUID()
        var deleted = eligible; deleted.id = UUID()
        snapshot.deletedRecordIDs.insert(deleted.id)
        snapshot.trainingSessions = [eligible, untimed, started, finished, other, deleted]
        XCTAssertEqual(TennisScheduling.nearbyTraining(in: snapshot, now: now).map(\.id), [eligible.id])
        let running = TennisGlance.make(kind: .startTraining, snapshot: snapshot, now: now)
        XCTAssertEqual(running.url.lastPathComponent, "live")
        XCTAssertTrue(running.accessibilitySummary.hasPrefix("Training in progress."))
        snapshot.trainingSessions.removeAll { $0.id == started.id }
        let glance = TennisGlance.make(kind: .startTraining, snapshot: snapshot, now: now)
        XCTAssertEqual(glance.url.lastPathComponent, "start-training")
        XCTAssertEqual(TennisWatchPage.destination(for: glance.url), .track)
        XCTAssertTrue(glance.accessibilitySummary.contains("Start scheduled training"))
    }

    func testTrainingSummaryNamesRolesInBothCompactAndDetailedForms() {
        var training = TrainingSession(playerID: UUID())
        training.context.coachName = "Ben and Jaggy"
        training.context.participantNames = ["Alex", "Sam"]
        for style in [TennisSummaryStyle.short, .detailed] {
            let summary = TennisSummaryFormatter.training(training, style: style)
            XCTAssertTrue(summary.contains("Coaches: Ben and Jaggy"))
            XCTAssertTrue(summary.contains("Players: Alex"))
        }
    }

    func testZeroMeasurementsAreSpokenAndMissingValuesAreNotInvented() {
        let zero = TennisWorkoutResult.fitnessSummary(heartRate: nil, energy: nil, distance: 0, steps: 0)
        XCTAssertEqual(zero, "Distance 0 metres. 0 steps.")
        let missing = TennisWorkoutResult.fitnessSummary(heartRate: nil, energy: nil, distance: nil, steps: nil)
        XCTAssertEqual(missing, "Distance unavailable. Steps unavailable.")
    }

    func testWeeklyComplicationHasNoAbbreviatedSpokenCountersOrAppPrefix() {
        let glance = TennisGlance.make(kind: .week, snapshot: .empty)
        XCTAssertTrue(glance.accessibilitySummary.hasPrefix("This week."))
        XCTAssertFalse(glance.accessibilitySummary.contains("Tennis Tracker"))
        XCTAssertFalse(glance.circularDetail.contains("T "))
        XCTAssertTrue(glance.circularDetail.contains("sessions"))
    }
}
