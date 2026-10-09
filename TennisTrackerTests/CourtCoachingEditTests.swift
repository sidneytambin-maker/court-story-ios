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
}
