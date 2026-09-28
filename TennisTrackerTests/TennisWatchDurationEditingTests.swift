import XCTest
@testable import TennisTracker

final class TennisWatchDurationEditingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testExplicitWatchPlannedDurationEditSurvivesCoding() throws {
        let planned = TrainingSession(playerID: UUID())
        var draft = planned
        draft.setManualDuration(minutes: 120, at: now)
        let saved = TennisWatchRecordEdits.training(draft, current: planned, durationWasEdited: true, now: now)
        let decoded = try roundTrip(saved)
        XCTAssertEqual(decoded.durationMinutes, 120)
        XCTAssertEqual(decoded.durationSource, .recorded)
        XCTAssertNil(decoded.durationEditedAt)
        XCTAssertNil(decoded.workout)
        XCTAssertNil(decoded.actualStart)
        XCTAssertNil(decoded.actualFinish)
        XCTAssertEqual(decoded.id, planned.id)
        XCTAssertEqual(decoded.revision, planned.revision + 1)
    }

    func testUnrelatedWatchEditKeepsNewerPhonePlannedDuration() {
        let planned = TrainingSession(playerID: UUID())
        var draft = planned; draft.notes = "Edited on Watch"
        var phone = planned
        phone.setManualDuration(minutes: 90, at: now)
        phone = TennisRecordConflictResolver.prepareLocalTraining(phone, now: now)
        let saved = TennisWatchRecordEdits.training(draft, current: phone, now: now)
        XCTAssertEqual(saved.durationMinutes, 90)
        XCTAssertEqual(saved.notes, draft.notes)
        XCTAssertEqual(saved.durationSource, .recorded)
    }

    func testPlannedEditCannotReplaceTimingIfSessionStartedWhileEditorWasOpen() {
        let planned = TrainingSession(playerID: UUID())
        var draft = planned
        draft.setManualDuration(minutes: 120, at: now)
        var active = planned
        active.actualStart = now.addingTimeInterval(-600)
        active.trackedOnWatch = true
        let saved = TennisWatchRecordEdits.training(draft, current: active, durationWasEdited: true, now: now)
        XCTAssertTrue(saved.isActive)
        XCTAssertEqual(saved.durationMinutes, active.durationMinutes)
        XCTAssertEqual(saved.durationSource, .recorded)
        XCTAssertNil(saved.durationEditedAt)
        XCTAssertEqual(saved.actualStart, active.actualStart)
        XCTAssertNil(saved.actualFinish)
        XCTAssertNil(saved.workout)
        XCTAssertEqual(TennisDurationFormatter.training(saved, now: now), "10 minutes")
        let finished = TennisWatchActivityFactory.finishTrainingSession(saved, finishDate: now)
        XCTAssertEqual(finished.durationMinutes, 10)
    }

    func testPlannedEditCannotReplaceCompletedRecordingOrPhoneCorrection() {
        let recorded = completedSession()
        var draft = TrainingSession(playerID: recorded.playerID)
        draft.id = recorded.id
        draft.setManualDuration(minutes: 90, at: now)
        let savedRecording = TennisWatchRecordEdits.training(draft, current: recorded, durationWasEdited: true, now: now)
        XCTAssertEqual(savedRecording.effectiveDurationSeconds, 21_120)
        assertRecording(savedRecording, equals: recorded)
        var phone = recorded
        phone.setManualDuration(minutes: 120, at: now)
        let savedCorrection = TennisWatchRecordEdits.training(draft, current: phone, durationWasEdited: true, now: now)
        XCTAssertEqual(savedCorrection.effectiveDurationSeconds, 7200)
        XCTAssertEqual(savedCorrection.durationSource, .manual)
        assertRecording(savedCorrection, equals: recorded)
    }

    func testNewerPhoneCorrectionSurvivesAnOlderExplicitWatchCorrection() throws {
        let original = completedSession()
        var draft = original
        draft.setManualDuration(minutes: 120, at: now)
        draft.notes = "Watch note"
        var phone = original
        phone.setManualDuration(minutes: 90, at: now.addingTimeInterval(1))
        phone = TennisRecordConflictResolver.prepareLocalTraining(phone, now: now.addingTimeInterval(1))
        let saved = TennisWatchRecordEdits.training(draft, current: phone, durationWasEdited: true, now: now.addingTimeInterval(2))
        XCTAssertEqual(saved.effectiveDurationSeconds, 5400)
        XCTAssertEqual(saved.durationEditedAt, phone.durationEditedAt)
        XCTAssertEqual(saved.notes, draft.notes)
        XCTAssertGreaterThan(saved.revision, phone.revision)
        assertRecording(saved, equals: original)
        var snapshot = TennisWatchSnapshot(); snapshot.trainingSessions = [try roundTrip(saved)]
        let result = TennisWatchReconciliation.reconcile(incoming: snapshot, pending: [.upsertTraining(draft)])
        XCTAssertTrue(result.pending.isEmpty)
        XCTAssertEqual(result.snapshot.trainingSessions.first?.effectiveDurationSeconds, 5400)
    }

    func testLaterWatchCorrectionWinsAndKeepsOriginalHealthMeasurements() {
        let original = completedSession()
        var phone = original
        phone.setManualDuration(minutes: 90, at: now)
        var draft = phone
        draft.setManualDuration(minutes: 120, at: now.addingTimeInterval(1))
        let saved = TennisWatchRecordEdits.training(draft, current: phone, durationWasEdited: true, now: now.addingTimeInterval(2))
        XCTAssertEqual(saved.effectiveDurationSeconds, 7200)
        XCTAssertEqual(TennisDurationFormatter.training(saved), "2 hours")
        XCTAssertTrue(TennisSummaryFormatter.training(saved, style: .detailed).contains("original 5 hours 52 minutes recording"))
        assertRecording(saved, equals: original)
    }

    func testSavingWithoutTouchingDurationKeepsRecordedSecondPrecision() {
        let original = completedSession(seconds: 159)
        let saved = TennisWatchRecordEdits.training(original, current: original, now: now)
        XCTAssertEqual(saved.durationSource, .recorded)
        XCTAssertNil(saved.durationEditedAt)
        XCTAssertEqual(TennisDurationFormatter.training(saved), "2 minutes 39 seconds")
        assertRecording(saved, equals: original)
    }

    func testSameSecondWatchCorrectionAppliesWhenRevisionHasNotChanged() {
        var current = completedSession()
        current.setManualDuration(minutes: 120, at: now)
        var draft = current
        draft.setManualDuration(minutes: 90, at: now.addingTimeInterval(0.5))
        let saved = TennisWatchRecordEdits.training(draft, current: current, durationWasEdited: true, now: now)
        XCTAssertEqual(saved.effectiveDurationSeconds, 5400)
        XCTAssertEqual(saved.durationSource, .manual)
        XCTAssertGreaterThan(saved.revision, current.revision)
        assertRecording(saved, equals: current)
    }

    func testSameSecondPhoneCorrectionSurvivesStaleWatchForm() {
        var original = completedSession()
        original.setManualDuration(minutes: 120, at: now)
        var draft = original
        draft.setManualDuration(minutes: 90, at: now.addingTimeInterval(0.25))
        var phone = original
        phone.setManualDuration(minutes: 60, at: now.addingTimeInterval(0.5))
        phone = TennisRecordConflictResolver.prepareLocalTraining(phone, now: now)
        let saved = TennisWatchRecordEdits.training(draft, current: phone, durationWasEdited: true, now: now)
        XCTAssertEqual(saved.effectiveDurationSeconds, 3600)
        XCTAssertEqual(saved.durationSource, .manual)
        assertRecording(saved, equals: original)
    }

    func testUnmarkedMinuteValuesCannotReplaceActiveReadings() {
        var active = completedSession(seconds: 159)
        active.actualFinish = nil
        var draft = active
        draft.durationMinutes = 120
        let saved = TennisWatchRecordEdits.training(draft, current: active, durationWasEdited: true, now: now)
        XCTAssertEqual(saved.durationMinutes, active.durationMinutes)
        XCTAssertEqual(saved.durationSource, .recorded)
        XCTAssertEqual(TennisDurationFormatter.training(saved, now: now), "2 minutes 39 seconds")
        assertRecording(saved, equals: active)
    }

    @MainActor
    func testWatchPlanEditSyncsToPhoneAndReloadsWithoutBecomingHealthOverride() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TennisStore(storeURL: url)
        var planned = TrainingSession(playerID: UUID())
        planned.date = now.addingTimeInterval(3600)
        store.upsertTraining(planned)
        let current = try XCTUnwrap(store.data.trainingSessions.first)
        var draft = current
        draft.setManualDuration(minutes: 120, at: now)
        let edited = TennisWatchRecordEdits.training(draft, current: current, durationWasEdited: true, now: now)
        store.applyWatchCommand(try roundTrip(TennisWatchSyncCommand.upsertTraining(edited)))
        let saved = try XCTUnwrap(TennisStore(storeURL: url).data.trainingSessions.first)
        XCTAssertEqual(saved.durationMinutes, 120)
        XCTAssertEqual(saved.durationSource, .recorded)
        XCTAssertEqual(saved.id, planned.id)
        XCTAssertNil(saved.workout)
        var active = saved; active.actualStart = now
        let finished = TennisWatchActivityFactory.finishTrainingSession(active, finishDate: now.addingTimeInterval(600))
        XCTAssertEqual(finished.durationMinutes, 10)
        XCTAssertEqual(finished.effectiveDurationSeconds, 600)
    }

    private func completedSession(seconds: TimeInterval = 21_120) -> TrainingSession {
        let start = now.addingTimeInterval(-seconds)
        let active = TennisWatchActivityFactory.trainingSession(playerID: UUID(), startDate: start)
        var finished = TennisWatchActivityFactory.finishTrainingSession(active, finishDate: now)
        finished.workout = TennisWorkoutResult(workoutID: UUID(), durationSeconds: seconds,
            averageHeartRate: 120, activeEnergyKcal: 900, peakHeartRate: 160, distanceMeters: 3000, stepCount: 4500)
        return finished
    }

    private func assertRecording(_ actual: TrainingSession, equals expected: TrainingSession,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.id, expected.id, file: file, line: line)
        XCTAssertEqual(actual.playerID, expected.playerID, file: file, line: line)
        XCTAssertEqual(actual.actualStart, expected.actualStart, file: file, line: line)
        XCTAssertEqual(actual.actualFinish, expected.actualFinish, file: file, line: line)
        XCTAssertEqual(actual.workout, expected.workout, file: file, line: line)
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder.tennisTracker.decode(T.self, from: JSONEncoder.tennisTracker.encode(value))
    }
}
