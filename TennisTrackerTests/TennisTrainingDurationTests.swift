import XCTest
@testable import TennisTracker

final class TennisTrainingDurationTests: XCTestCase {
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 18))!

    func testCorrectionWinsWithoutChangingRawWorkoutTimingOrIdentity() throws {
        let original = recordedSession()
        var edited = original
        edited.setManualDuration(minutes: 120, at: now)
        XCTAssertEqual(edited.durationSource, .manual)
        XCTAssertEqual(edited.effectiveDurationSeconds, 7200)
        XCTAssertEqual(TennisDurationFormatter.training(edited), "2 hours")
        assertOriginalRecording(edited, equals: original)
        XCTAssertEqual(try roundTrip(edited), edited)
    }

    func testLegacySavedTwoHourCorrectionMigratesAndRemainsIdempotent() throws {
        let original = recordedSession()
        var legacy = original
        legacy.durationMinutes = 120
        let migrated = try JSONDecoder.tennisTracker.decode(TrainingSession.self, from: legacyBytes(legacy))
        XCTAssertEqual(migrated.durationSource, .manual)
        XCTAssertEqual(migrated.durationEditedAt, legacy.modifiedAt)
        XCTAssertEqual(migrated.durationMinutes, 120)
        XCTAssertEqual(migrated.effectiveDurationSeconds, 7200)
        XCTAssertEqual(migrated.revision, legacy.revision)
        assertOriginalRecording(migrated, equals: original)
        XCTAssertEqual(try roundTrip(migrated), migrated)
        XCTAssertEqual(try roundTrip(roundTrip(migrated)), migrated)
    }

    func testLegacyRoundingAndHealthActiveTimeDoNotBecomeCorrections() throws {
        for minutes in [2, 3, 4] {
            var original = recordedSession(seconds: 159)
            original.durationMinutes = minutes
            original.workout?.durationSeconds = 151
            let decoded = try JSONDecoder.tennisTracker.decode(TrainingSession.self, from: legacyBytes(original))
            XCTAssertEqual(decoded.durationSource, .recorded)
            XCTAssertNil(decoded.durationEditedAt)
            XCTAssertEqual(decoded.effectiveDurationSeconds, 151)
            XCTAssertEqual(TennisDurationFormatter.training(decoded), "2 minutes 31 seconds")
        }
    }

    func testLegacyPlannedAndRunningDurationsAreNotMigrated() throws {
        var planned = TrainingSession(playerID: UUID())
        planned.date = now.addingTimeInterval(3600)
        planned.durationMinutes = 120
        let decodedPlan = try JSONDecoder.tennisTracker.decode(TrainingSession.self, from: legacyBytes(planned))
        XCTAssertEqual(decodedPlan.durationSource, .recorded)
        planned.actualStart = now.addingTimeInterval(-21_120)
        let running = try JSONDecoder.tennisTracker.decode(TrainingSession.self, from: legacyBytes(planned))
        XCTAssertEqual(running.durationSource, .recorded)
        XCTAssertEqual(TennisDurationFormatter.training(running, now: now), "5 hours 52 minutes")
    }

    func testFinishingScheduledTrainingReplacesPlanBeforeLegacyMigration() throws {
        var planned = TrainingSession(playerID: UUID())
        planned.setManualDuration(minutes: 120, at: now)
        XCTAssertEqual(planned.durationSource, .recorded)
        planned.actualStart = now.addingTimeInterval(-21_120)
        planned.trackedOnWatch = true
        let finished = TennisWatchActivityFactory.finishTrainingSession(planned, finishDate: now)
        XCTAssertEqual(finished.durationMinutes, 352)
        let decoded = try JSONDecoder.tennisTracker.decode(TrainingSession.self, from: legacyBytes(finished))
        XCTAssertEqual(decoded.durationSource, .recorded)
        XCTAssertEqual(decoded.effectiveDurationSeconds, 21_120)
    }

    func testCurrentRecordedSourceAndMissingLegacyMinutesAreNotGuessed() throws {
        var recorded = recordedSession()
        recorded.durationMinutes = 120
        XCTAssertEqual(try roundTrip(recorded).durationSource, .recorded)
        XCTAssertEqual(try roundTrip(recorded).effectiveDurationSeconds, 21_120)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyBytes(recorded)) as? [String: Any])
        object.removeValue(forKey: "durationMinutes")
        let decoded = try JSONDecoder.tennisTracker.decode(TrainingSession.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.durationSource, .recorded)
        XCTAssertEqual(decoded.effectiveDurationSeconds, 21_120)
    }

    func testExplicitSmallCorrectionAndTimingWithoutHealthWork() throws {
        var recorded = recordedSession(seconds: 159)
        recorded.workout = nil
        recorded.setManualDuration(minutes: 3, at: now)
        XCTAssertEqual(recorded.effectiveDurationSeconds, 180)
        XCTAssertEqual(TennisDurationFormatter.training(try roundTrip(recorded)), "3 minutes")
        let edited = recorded
        recorded.setManualDuration(minutes: 0, at: now)
        recorded.setManualDuration(minutes: -1, at: now)
        XCTAssertEqual(recorded, edited)
    }

    func testFinishingActiveTrainingPreservesExplicitCorrection() {
        let start = now.addingTimeInterval(-21_120)
        var running = TennisWatchActivityFactory.trainingSession(playerID: UUID(), startDate: start)
        running.setManualDuration(minutes: 120, at: now)
        XCTAssertEqual(TennisDurationFormatter.training(running, now: now), "5 hours 52 minutes")
        let finished = TennisWatchActivityFactory.finishTrainingSession(running, finishDate: now)
        XCTAssertEqual(finished.durationSource, .manual)
        XCTAssertEqual(finished.durationMinutes, 120)
        XCTAssertEqual(finished.effectiveDurationSeconds, 7200)
        XCTAssertEqual(finished.actualStart, start)
        XCTAssertEqual(finished.actualFinish, now)
        XCTAssertEqual(finished.id, running.id)
    }

    func testLegacyCorrectionWithoutHealthStillUsesSavedMinutes() throws {
        var legacy = recordedSession()
        legacy.workout = nil
        legacy.durationMinutes = 120
        let corrected = try JSONDecoder.tennisTracker.decode(TrainingSession.self, from: legacyBytes(legacy))
        XCTAssertEqual(corrected.durationSource, .manual)
        XCTAssertEqual(corrected.effectiveDurationSeconds, 7200)
        XCTAssertNil(corrected.workout)
        XCTAssertEqual(corrected.actualStart, legacy.actualStart)
        XCTAssertEqual(corrected.actualFinish, legacy.actualFinish)
    }

    func testAllSummaryStylesUseCorrectionAndFitnessKeepsOriginalWindow() {
        let original = recordedSession()
        var edited = original
        edited.setManualDuration(minutes: 120, at: now)
        for style in [TennisSummaryStyle.short, .long, .accessibility, .detailed] {
            let summary = TennisSummaryFormatter.training(edited, style: style, now: now)
            XCTAssertTrue(summary.contains("2 hours"))
            if style != .detailed { XCTAssertFalse(summary.contains("5 hours 52 minutes")) }
        }
        let detail = TennisSummaryFormatter.training(edited, style: .detailed, now: now)
        XCTAssertTrue(detail.contains("Fitness measurements cover the original 5 hours 52 minutes recording"))
        XCTAssertTrue(detail.contains("Active energy 900 calories"))
        XCTAssertTrue(detail.contains("Average heart rate 120 beats per minute"))
        assertOriginalRecording(edited, equals: original)
    }

    func testDashboardFocusAndWatchGlancesAggregateCorrectedDuration() throws {
        let player = PlayerProfile()
        var legacy = recordedSession(playerID: player.id)
        legacy.durationMinutes = 120
        let corrected = try JSONDecoder.tennisTracker.decode(TrainingSession.self, from: legacyBytes(legacy))
        let precise = recordedSession(playerID: player.id, seconds: 159)
        var future = TrainingSession(playerID: player.id)
        future.date = now.addingTimeInterval(3600)
        var running = recordedSession(playerID: player.id)
        running.actualFinish = nil
        let sessions = [corrected, precise, future, running]
        let stats = TennisStatistics.build(matches: [], training: sessions, tournaments: [], today: now)
        XCTAssertEqual(stats.trainingCountLast30Days, 2)
        XCTAssertEqual(stats.trainingSecondsLast30Days, 7359)
        XCTAssertEqual(stats.trainingMinutesLast30Days, 122)
        let progress = TennisPlayerProgress.build(player: player, matches: [], training: sessions, now: now)
        XCTAssertEqual(progress.trainingTypes.map(\.seconds).reduce(0, +), 7359)
        XCTAssertEqual(progress.focus.map(\.seconds).reduce(0, +), 7359)
        var snapshot = TennisWatchSnapshot()
        snapshot.players = [player]; snapshot.selectedPlayerID = player.id
        snapshot.trainingSessions = [corrected]
        XCTAssertTrue(TennisGlance.make(kind: .week, snapshot: snapshot, now: now).accessibilitySummary.contains("2 hours"))
        let latest = TennisGlance.make(kind: .latest, snapshot: snapshot, now: now)
        XCTAssertEqual(latest.circularDetail, "2:00:00")
        XCTAssertTrue(latest.accessibilitySummary.contains("original 5 hours 52 minutes recording"))
    }

    @MainActor
    func testPhoneSaveReloadBackupAndWatchSnapshotKeepCorrection() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = PlayerProfile()
        let store = TennisStore(storeURL: url)
        store.completeOnboarding(player: player, settings: AppSettings())
        let original = recordedSession(playerID: player.id)
        store.applyWatchCommand(.upsertTraining(original))
        var edited = try XCTUnwrap(store.data.trainingSessions.first)
        edited.setManualDuration(minutes: 120, at: now)
        store.upsertTraining(edited)
        let reloaded = TennisStore(storeURL: url)
        let saved = try XCTUnwrap(reloaded.data.trainingSessions.first)
        XCTAssertEqual(saved.effectiveDurationSeconds, 7200)
        XCTAssertEqual(saved.durationSource, .manual)
        XCTAssertGreaterThan(saved.revision, original.revision)
        assertOriginalRecording(saved, equals: original)
        let restoredBackup = try TennisBackup.decode(JSONEncoder.tennisTracker.encode(reloaded.data))
        XCTAssertEqual(restoredBackup.libraryID, reloaded.data.libraryID)
        XCTAssertEqual(restoredBackup.trainingSessions, [saved])
        let snapshot = TennisWatchSnapshot(data: restoredBackup, now: now)
        XCTAssertEqual(try roundTrip(snapshot).trainingSessions, [saved])
    }

    @MainActor
    func testLoadingAlreadySavedLegacyLibraryFixesSummariesAndTotals() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var data = AppData()
        let player = PlayerProfile()
        data.players = [player]; data.selectedPlayerID = player.id
        let original = recordedSession(playerID: player.id)
        var corrected = original; corrected.durationMinutes = 120
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.tennisTracker.encode(data)) as? [String: Any])
        object["trainingSessions"] = [try JSONSerialization.jsonObject(with: legacyBytes(corrected))]
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let store = TennisStore(storeURL: url)
        XCTAssertNil(store.storageError)
        let loaded = try XCTUnwrap(store.data.trainingSessions.first)
        XCTAssertTrue(store.trainingSummary(loaded).contains("2 hours"))
        XCTAssertEqual(TennisStatistics.build(matches: [], training: store.data.trainingSessions, tournaments: [], today: now).trainingSecondsLast30Days, 7200)
        XCTAssertEqual(store.data.libraryID, data.libraryID)
        assertOriginalRecording(loaded, equals: original)
        store.updateSettings(store.data.settings)
        XCTAssertEqual(TennisStore(storeURL: url).data.trainingSessions, [loaded])
    }

    @MainActor
    func testStalePhoneEditorCannotEraseCorrectionOrConfirmedHealthResult() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TennisStore(storeURL: url)
        let original = recordedSession()
        var stale = original
        stale.workout?.workoutID = nil
        store.applyWatchCommand(.upsertTraining(original))
        var edited = original
        edited.setManualDuration(minutes: 120, at: now)
        store.upsertTraining(edited)
        stale.notes = "Unrelated note from an older editor"
        store.upsertTraining(stale)
        let saved = try XCTUnwrap(store.data.trainingSessions.first)
        XCTAssertEqual(saved.effectiveDurationSeconds, 7200)
        XCTAssertEqual(saved.notes, stale.notes)
        assertOriginalRecording(saved, equals: original)
    }

    @MainActor
    func testExplicitEditWhileWatchFinishesKeepsCorrectionAndActualFinish() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TennisStore(storeURL: url)
        let original = recordedSession()
        var draft = original
        draft.workout = nil; draft.actualFinish = nil; draft.durationMinutes = 1
        store.applyWatchCommand(.upsertTraining(original))
        draft.setManualDuration(minutes: 120, at: now)
        store.upsertTraining(draft)
        let saved = try XCTUnwrap(store.data.trainingSessions.first)
        XCTAssertEqual(saved.effectiveDurationSeconds, 7200)
        assertOriginalRecording(saved, equals: original)
    }

    func testWatchDetailsEditPreservesOrExplicitlyUpdatesCorrection() {
        let original = recordedSession()
        var current = original
        current.setManualDuration(minutes: 120, at: now)
        var draft = original; draft.notes = "Focus updated on Watch"
        let unchanged = TennisWatchRecordEdits.training(draft, current: current, now: now)
        XCTAssertEqual(unchanged.effectiveDurationSeconds, 7200)
        draft.setManualDuration(minutes: 90, at: now.addingTimeInterval(1))
        let edited = TennisWatchRecordEdits.training(draft, current: current, now: now.addingTimeInterval(1))
        XCTAssertEqual(edited.effectiveDurationSeconds, 5400)
        assertOriginalRecording(edited, equals: original)
    }

    @MainActor
    func testLateWatchHealthSaveMergesWithPhoneCorrectionAndAcknowledges() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TennisStore(storeURL: url)
        let original = recordedSession()
        var withoutHealth = original; withoutHealth.workout = nil
        store.applyWatchCommand(.upsertTraining(withoutHealth))
        var corrected = withoutHealth
        corrected.setManualDuration(minutes: 120, at: now)
        store.upsertTraining(corrected)
        // The delayed result has an older record revision than the phone edit.
        store.applyWatchCommand(try roundTrip(TennisWatchSyncCommand.upsertTraining(original)))
        let saved = try XCTUnwrap(store.data.trainingSessions.first)
        XCTAssertEqual(saved.effectiveDurationSeconds, 7200)
        assertOriginalRecording(saved, equals: original)
        let incoming = try roundTrip(TennisWatchSnapshot(data: store.data, now: now))
        let reconciled = TennisWatchReconciliation.reconcile(incoming: incoming, pending: [.upsertTraining(original)])
        XCTAssertTrue(reconciled.pending.isEmpty)
        XCTAssertEqual(reconciled.snapshot.trainingSessions, [saved])
        store.applyWatchCommand(.upsertTraining(original))
        XCTAssertEqual(store.data.trainingSessions, [saved])
    }

    func testNewerWatchMetadataCannotRevertManualDuration() {
        let original = recordedSession()
        var corrected = original
        corrected.setManualDuration(minutes: 120, at: now)
        var newerMetadata = original
        newerMetadata.notes = "Updated after correction"
        newerMetadata.revision += 10
        newerMetadata.modifiedAt = now.addingTimeInterval(10)
        let merged = TennisRecordConflictResolver.mergeTraining(incoming: newerMetadata, existing: corrected)
        XCTAssertEqual(merged.effectiveDurationSeconds, 7200)
        XCTAssertEqual(merged.notes, newerMetadata.notes)
        XCTAssertGreaterThan(merged.revision, newerMetadata.revision)
        XCTAssertEqual(TennisRecordConflictResolver.mergeTraining(incoming: corrected, existing: newerMetadata), merged)
        XCTAssertEqual(TennisRecordConflictResolver.mergeTraining(incoming: newerMetadata, existing: merged), merged)
    }

    func testLatestDurationEditWinsOverNewerUnrelatedRecordRevision() {
        var olderEdit = recordedSession()
        olderEdit.setManualDuration(minutes: 120, at: now)
        var newerEdit = olderEdit
        newerEdit.setManualDuration(minutes: 90, at: now.addingTimeInterval(1))
        olderEdit.revision += 10
        olderEdit.modifiedAt = now.addingTimeInterval(20)
        let merged = TennisRecordConflictResolver.mergeTraining(incoming: olderEdit, existing: newerEdit)
        XCTAssertEqual(merged.effectiveDurationSeconds, 5400)
        XCTAssertEqual(merged.durationEditedAt, newerEdit.durationEditedAt)
    }

    func testSnapshotReconciliationKeepsMergedCorrectionPendingUntilAcknowledged() throws {
        let original = recordedSession()
        var corrected = original
        corrected.setManualDuration(minutes: 120, at: now)
        var snapshot = TennisWatchSnapshot()
        var newer = original; newer.revision += 10
        snapshot.trainingSessions = [newer]
        let result = TennisWatchReconciliation.reconcile(incoming: snapshot, pending: [.upsertTraining(corrected)])
        let merged = try XCTUnwrap(result.snapshot.trainingSessions.first)
        XCTAssertEqual(merged.effectiveDurationSeconds, 7200)
        XCTAssertEqual(result.pending, [.upsertTraining(merged)])
        let queue = TennisWatchCommandQueue(libraryID: UUID(), commands: result.pending)
        XCTAssertEqual(try roundTrip(queue).commands, result.pending)
        let acknowledged = TennisWatchReconciliation.reconcile(incoming: try roundTrip(result.snapshot), pending: result.pending)
        XCTAssertTrue(acknowledged.pending.isEmpty)
        XCTAssertEqual(acknowledged.snapshot.trainingSessions, [merged])
        var deleted = snapshot; deleted.deletedRecordIDs = [corrected.id]
        let removed = TennisWatchReconciliation.reconcile(incoming: deleted, pending: result.pending)
        XCTAssertTrue(removed.pending.isEmpty)
        XCTAssertTrue(removed.snapshot.trainingSessions.isEmpty)
    }

    private func recordedSession(playerID: UUID = UUID(), seconds: TimeInterval = 21_120) -> TrainingSession {
        let finish = now.addingTimeInterval(-600)
        let running = TennisWatchActivityFactory.trainingSession(playerID: playerID, startDate: finish.addingTimeInterval(-seconds))
        var session = TennisWatchActivityFactory.finishTrainingSession(running, finishDate: finish)
        session.focus = "Serve and return"
        session.workout = TennisWorkoutResult(workoutID: UUID(), durationSeconds: seconds, averageHeartRate: 120,
            activeEnergyKcal: 900, peakHeartRate: 160, distanceMeters: 3000, stepCount: 4500)
        return session
    }

    private func assertOriginalRecording(_ value: TrainingSession, equals original: TrainingSession,
                                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value.id, original.id, file: file, line: line)
        XCTAssertEqual(value.playerID, original.playerID, file: file, line: line)
        XCTAssertEqual(value.actualStart, original.actualStart, file: file, line: line)
        XCTAssertEqual(value.actualFinish, original.actualFinish, file: file, line: line)
        XCTAssertEqual(value.workout, original.workout, file: file, line: line)
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder.tennisTracker.decode(T.self, from: JSONEncoder.tennisTracker.encode(value))
    }

    private func legacyBytes(_ session: TrainingSession) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.tennisTracker.encode(session)) as? [String: Any])
        object.removeValue(forKey: "durationSource")
        object.removeValue(forKey: "durationEditedAt")
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    }
}
