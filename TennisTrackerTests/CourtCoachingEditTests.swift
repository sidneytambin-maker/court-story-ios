import XCTest
@testable import TennisTracker

@MainActor
final class CourtCoachingEditTests: XCTestCase {
    func testOlderPhoneEditsCannotOverwriteNewWatchObservationDrillOrProfile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TennisStore(storeURL: url)
        try store.restoreBackup(CourtDemoLibrary.make())
        let observation = try XCTUnwrap(store.data.court.observations.first)
        var newerObservation = observation; newerObservation.revision += 1; newerObservation.happened = "New Watch observation"; newerObservation.modifiedAt = Date()
        store.applyWatchCommand(.court(.observation(newerObservation)))
        XCTAssertFalse(store.saveObservation(observation))
        XCTAssertEqual(store.data.court.observations.first?.happened, "New Watch observation")
        let drill = try XCTUnwrap(store.data.court.drills.first)
        var newerDrill = drill; newerDrill.revision += 1; newerDrill.successfulAttempts = 8; newerDrill.modifiedAt = Date()
        store.applyWatchCommand(.court(.drill(newerDrill)))
        XCTAssertFalse(store.saveMeasuredDrill(drill))
        XCTAssertEqual(store.data.court.drills.first?.successfulAttempts, 8)
        let profile = try XCTUnwrap(store.data.players.last)
        var newerProfile = profile; newerProfile.court.revision += 1; newerProfile.court.modifiedAt = Date(); newerProfile.preferredName = "Morgan's current name"
        store.applyWatchCommand(.court(.profile(newerProfile)))
        XCTAssertFalse(store.saveCourtProfile(profile))
        XCTAssertEqual(store.data.players.last?.preferredName, "Morgan's current name")
    }

    func testWatchCannotArchiveAnAthleteWithActiveTraining() throws {
        var data = CourtDemoLibrary.make()
        var athlete = try XCTUnwrap(data.players.last)
        var active = TrainingSession(playerID: athlete.id); active.actualStart = Date()
        data.trainingSessions.append(active)
        let original = try JSONEncoder.tennisTracker.encode(data)
        athlete.court.archivedAt = Date(); athlete.court.revision += 1
        XCTAssertFalse(CourtWatchMutation.profile(athlete).apply(to: &data))
        XCTAssertEqual(try JSONEncoder.tennisTracker.encode(data), original)
    }

    func testWatchPracticePlanTransfersAndReloadsWithIndependentAthleteRules() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TennisStore(storeURL: url)
        try store.restoreBackup(CourtDemoLibrary.make())
        let observation = try XCTUnwrap(store.data.court.observations.first)
        let athlete = try XCTUnwrap(store.data.players.first { $0.id == observation.athleteID })
        var planned = observation.practicePlan(on: Date().addingTimeInterval(86400))
        planned.court.access = athlete.court.selected.access
        planned.court.rules = athlete.court.selected.rules
        planned = TennisRecordConflictResolver.prepareLocalTraining(planned)
        store.applyWatchCommand(.upsertTraining(planned))
        store.applyWatchCommand(.upsertTraining(planned))
        let restored = TennisStore(storeURL: url)
        let saved = try XCTUnwrap(restored.data.trainingSessions.first { $0.id == planned.id })
        XCTAssertEqual(restored.data.trainingSessions.filter { $0.id == planned.id }.count, 1)
        XCTAssertEqual(saved.court.plan?.sourceObservationID, observation.id)
        XCTAssertEqual(saved.court.plan?.objective, observation.nextAction)
        XCTAssertEqual(saved.court.access?.allowedBounces(for: .tennis), 3)
        XCTAssertEqual(saved.playerID, athlete.id)
        XCTAssertNil(saved.actualStart); XCTAssertNil(saved.actualFinish); XCTAssertNil(saved.workout)
    }

    func testWatchPlanEditPreservesConcurrentPhoneSchedulePlanAndLiveTiming() throws {
        let data = CourtDemoLibrary.make()
        var original = try XCTUnwrap(data.trainingSessions.first { $0.actualStart == nil })
        original.court.plan = CourtSessionPlan(objective: "Original objective")
        var draft = original
        draft.date = original.date.addingTimeInterval(3600)
        draft.court.plan?.objective = "New Watch objective"
        let edited = TennisWatchRecordEdits.training(draft, current: original, original: original)
        XCTAssertEqual(edited.date, draft.date)
        XCTAssertEqual(edited.court.plan?.objective, "New Watch objective")
        var current = original
        current.date = original.date.addingTimeInterval(7200)
        current.court.plan?.objective = "New phone objective"
        let merged = TennisWatchRecordEdits.training(draft, current: current, original: original)
        XCTAssertEqual(merged.date, current.date)
        XCTAssertEqual(merged.court.plan, current.court.plan)
        current = original; current.actualStart = Date()
        let active = TennisWatchRecordEdits.training(draft, current: current, original: original)
        XCTAssertEqual(active.actualStart, current.actualStart)
        XCTAssertEqual(active.date, original.date)
    }
}
