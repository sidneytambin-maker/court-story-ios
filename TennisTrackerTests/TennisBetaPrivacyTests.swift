import XCTest
@testable import TennisTracker

@MainActor
final class TennisBetaPrivacyTests: XCTestCase {
    private func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json") }

    func testFreshInstallIsEmptyAndLibraryIdentityPersists() throws {
        let path = url()
        let first = TennisStore(storeURL: path)
        XCTAssertNil(first.storageError)
        XCTAssertTrue(first.needsOnboarding)
        XCTAssertTrue(first.data.players.isEmpty)
        XCTAssertTrue(first.data.matches.isEmpty)
        XCTAssertTrue(first.data.trainingSessions.isEmpty)
        XCTAssertTrue(first.data.tournaments.isEmpty)
        XCTAssertEqual(first.data.setup, TennisSetup())
        XCTAssertNil(first.data.selectedPlayerID)
        XCTAssertTrue(first.data.achievementRecords.isEmpty)
        XCTAssertFalse(first.data.settings.trainingRemindersEnabled)
        let second = TennisStore(storeURL: path)
        XCTAssertEqual(first.data, second.data)
        let watch = TennisWatchSnapshot(data: second.data)
        XCTAssertTrue(watch.players.isEmpty)
        XCTAssertTrue(watch.achievementHistory.isEmpty)
        XCTAssertTrue(watch.knownVenues.isEmpty)
    }

    func testOnboardingStaysCompleteWithNoActivityAndDoesNotOverwrite() {
        let path = url()
        let store = TennisStore(storeURL: path)
        var player = PlayerProfile(); player.name = "Test Player"
        XCTAssertTrue(store.completeOnboarding(player: player, settings: AppSettings()))
        XCTAssertFalse(store.needsOnboarding)
        let saved = store.data
        XCTAssertFalse(store.completeOnboarding(player: player, settings: AppSettings()))
        XCTAssertEqual(store.data, saved)
        XCTAssertFalse(TennisStore(storeURL: path).needsOnboarding)
        store.deletePlayer(player)
        XCTAssertFalse(TennisStore(storeURL: path).needsOnboarding)
    }

    func testTwoInstallationsNeverShareRecordsOrSetup() throws {
        let a = TennisStore(storeURL: url())
        let b = TennisStore(storeURL: url())
        let owner = sampleLibrary()
        try a.restoreBackup(owner)
        var player = PlayerProfile(); player.name = "Second Tester"
        b.completeOnboarding(player: player, settings: AppSettings())
        XCTAssertNotEqual(a.data.libraryID, b.data.libraryID)
        XCTAssertEqual(b.data.players.map(\.id), [player.id])
        XCTAssertTrue(b.data.matches.isEmpty)
        XCTAssertTrue(b.data.trainingSessions.isEmpty)
        XCTAssertTrue(b.data.tournaments.isEmpty)
        XCTAssertEqual(b.data.setup, TennisSetup())
        XCTAssertTrue(b.data.achievementRecords.isEmpty)
        XCTAssertEqual(b.selectedPlayer?.primaryGoal, "")
        XCTAssertFalse(a.data.players.contains { $0.id == player.id })
        let watch = TennisWatchSnapshot(data: b.data)
        XCTAssertEqual(watch.players.map(\.id), [player.id])
        XCTAssertTrue(watch.trainingSessions.isEmpty)
    }

    func testOptionalOnboardingPeopleAndPlacesPreserveIDsWithoutCreatingActivities() {
        let path = url()
        let store = TennisStore(storeURL: path)
        var player = PlayerProfile(); player.name = "New Tester"
        var partner = PlayerProfile(); partner.name = "Training Partner"; partner.isRegularPartner = true
        var setup = TennisSetup()
        setup.coaches = [TennisCoach(name: "Local Coach")]
        setup.venues = [TennisVenue(name: "Local Courts")]
        setup.locations = [TennisLocation(name: "Court Two")]
        setup.tournamentTemplates = [TennisTournamentTemplate(name: "Club Championship", venueID: setup.venues[0].id)]
        XCTAssertTrue(store.completeOnboarding(player: player, settings: AppSettings(), setup: setup, additionalPlayers: [partner]))
        let restored = TennisStore(storeURL: path)
        XCTAssertEqual(restored.data.players.map(\.id), [player.id, partner.id])
        XCTAssertEqual(restored.data.setup, setup)
        XCTAssertTrue(restored.data.players[1].isRegularPartner)
        XCTAssertTrue(restored.data.matches.isEmpty)
        XCTAssertTrue(restored.data.trainingSessions.isEmpty)
        XCTAssertTrue(restored.data.tournaments.isEmpty)
        XCTAssertTrue(restored.data.achievementRecords.isEmpty)
        XCTAssertEqual(TennisWatchSnapshot(data: restored.data).setup, setup)
    }

    func testWatchRestartCannotReopenRetiredCacheAfterInterruptedLibraryChange() throws {
        let previous = UUID(), current = UUID(), unrelated = UUID()
        var fence = TennisWatchLibraryFence()
        XCTAssertTrue(fence.accept(previous, authoritative: true))
        XCTAssertTrue(fence.accept(current, authoritative: true))
        let persisted = try JSONEncoder.tennisTracker.encode(fence)
        let restarted = try JSONDecoder.tennisTracker.decode(TennisWatchLibraryFence.self, from: persisted)
        XCTAssertFalse(restarted.canRestoreCachedLibrary(previous))
        XCTAssertFalse(restarted.canRestoreCachedLibrary(unrelated))
        XCTAssertFalse(restarted.canRestoreCachedLibrary(nil))
        XCTAssertTrue(restarted.canRestoreCachedLibrary(current))
        XCTAssertTrue(TennisWatchLibraryFence().canRestoreCachedLibrary(current))
    }

    func testVersionTenMigrationPreservesAllFieldsAndStableIDs() throws {
        var original = sampleLibrary(); original.dataVersion = 10
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.tennisTracker.encode(original)) as? [String: Any])
        object.removeValue(forKey: "libraryID")
        object.removeValue(forKey: "onboardingCompleted")
        let path = url()
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        let migrated = TennisStore(storeURL: path)
        XCTAssertNil(migrated.storageError)
        XCTAssertFalse(migrated.needsOnboarding)
        original.libraryID = migrated.data.libraryID
        original.dataVersion = 11
        original.onboardingCompleted = true
        XCTAssertEqual(migrated.data, original)
        XCTAssertEqual(TennisStore(storeURL: path).data, original)
    }

    func testOwnerRestoreKeepsWholeLibraryButCreatesNewTransportIdentity() throws {
        let owner = sampleLibrary()
        let decoded = try TennisBackup.decode(JSONEncoder.tennisTracker.encode(owner))
        let path = url()
        let restored = TennisStore(storeURL: path)
        try restored.restoreBackup(decoded)
        var expected = owner
        XCTAssertNotEqual(restored.data.libraryID, owner.libraryID)
        expected.libraryID = restored.data.libraryID
        XCTAssertEqual(restored.data, expected)
        XCTAssertEqual(TennisStore(storeURL: path).data, expected)
        XCTAssertEqual(restored.data.trainingSessions.first?.workout?.durationSeconds, 159)
    }

    func testRestoreRefusesOccupiedLibraryWithoutChangingDisk() throws {
        let path = url()
        let store = TennisStore(storeURL: path)
        try store.restoreBackup(sampleLibrary())
        let bytes = try Data(contentsOf: path)
        XCTAssertThrowsError(try store.restoreBackup(sampleLibrary()))
        XCTAssertEqual(try Data(contentsOf: path), bytes)
    }

    func testCorruptLibraryIsNotReplacedByFreshSetup() throws {
        let path = url()
        let bytes = Data("{not valid JSON".utf8)
        try bytes.write(to: path)
        let store = TennisStore(storeURL: path)
        XCTAssertNotNil(store.storageError)
        XCTAssertFalse(store.needsOnboarding)
        var player = PlayerProfile(); player.name = "Not Saved"
        XCTAssertFalse(store.completeOnboarding(player: player, settings: AppSettings()))
        XCTAssertEqual(try Data(contentsOf: path), bytes)
    }

    func testBackupRejectsMissingTablesAndRegeneratedIDs() throws {
        XCTAssertThrowsError(try TennisBackup.decode(Data("{}".utf8)))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.tennisTracker.encode(sampleLibrary())) as? [String: Any])
        var players = try XCTUnwrap(object["players"] as? [[String: Any]])
        players[0].removeValue(forKey: "id")
        object["players"] = players
        XCTAssertThrowsError(try TennisBackup.decode(JSONSerialization.data(withJSONObject: object)))
    }

    func testValidJSONWithMissingLibraryFieldsCannotTriggerFreshSetup() throws {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.tennisTracker.encode(sampleLibrary())) as? [String: Any])
        for missing in ["players", "matches", "trainingSessions", "tournaments", "setup", "settings", "libraryID", "onboardingCompleted"] {
            var object = original
            object.removeValue(forKey: missing)
            let path = url()
            let bytes = try JSONSerialization.data(withJSONObject: object)
            try bytes.write(to: path)
            let store = TennisStore(storeURL: path)
            XCTAssertNotNil(store.storageError, "Missing \(missing) must not be replaced with defaults")
            XCTAssertFalse(store.needsOnboarding)
            XCTAssertEqual(try Data(contentsOf: path), bytes)
        }
    }

    func testBackupRejectsDuplicateIDsBrokenLinksAndActiveWorkouts() throws {
        var value = sampleLibrary()
        value.players.append(value.players[0])
        XCTAssertThrowsError(try TennisBackup.validate(value))
        value = sampleLibrary(); value.matches[0].trainingSessionID = UUID()
        XCTAssertThrowsError(try TennisBackup.validate(value))
        value = sampleLibrary(); value.trainingSessions[0].actualFinish = nil
        XCTAssertThrowsError(try TennisBackup.validate(value))
    }

    func testWatchCommandsCannotCrossLibraryBoundary() {
        let a = UUID(), b = UUID()
        let command = TennisWatchSyncCommand.upsertTraining(TrainingSession(playerID: UUID()))
        XCTAssertTrue(TennisWatchCommandEnvelope(libraryID: a, command: command).isAllowed(in: a))
        XCTAssertFalse(TennisWatchCommandEnvelope(libraryID: a, command: command).isAllowed(in: b))
        XCTAssertFalse(TennisWatchCommandEnvelope(libraryID: nil, command: command).isAllowed(in: a))
        XCTAssertFalse(TennisWatchCommandEnvelope(libraryID: a, command: .snapshotReceived(Date())).isAllowed(in: b))
        XCTAssertTrue(TennisWatchCommandEnvelope(libraryID: nil, command: .requestSnapshot).isAllowed(in: b))
    }

    func testDelayedWatchSnapshotsCannotRestorePreviousUser() throws {
        let a = UUID(), b = UUID()
        var fence = TennisWatchLibraryFence()
        XCTAssertFalse(fence.accept(a, authoritative: false))
        XCTAssertTrue(fence.accept(a, authoritative: true))
        XCTAssertFalse(fence.accept(b, authoritative: false))
        XCTAssertTrue(fence.accept(b, authoritative: true))
        XCTAssertFalse(fence.accept(a, authoritative: true))
        XCTAssertFalse(fence.accept(nil, authoritative: true))
        fence = try JSONDecoder.tennisTracker.decode(TennisWatchLibraryFence.self, from: JSONEncoder.tennisTracker.encode(fence))
        XCTAssertFalse(fence.accept(a, authoritative: true))
    }

    func testOpenNotificationCannotCarryRecordIntoDifferentLibrary() {
        let old = TennisWatchSnapshot(data: sampleLibrary())
        var fresh = TennisWatchSnapshot(data: AppData())
        fresh.retainOpenActivities(Set(old.matches.map(\.id)), from: old)
        XCTAssertTrue(fresh.matches.isEmpty)
        XCTAssertTrue(fresh.achievementHistory.isEmpty)
    }

    private func sampleLibrary() -> AppData {
        var value = AppData()
        var player = PlayerProfile(); player.name = "First Tester"; player.primaryGoal = "Improve returns"
        var partner = PlayerProfile(); partner.name = "Practice Partner"; partner.isRegularPartner = true
        value.players = [player, partner]; value.selectedPlayerID = player.id; value.onboardingCompleted = true
        value.setup.coaches = [TennisCoach(name: "Coach A"), TennisCoach(name: "Coach B")]
        value.setup.venues = [TennisVenue(name: "Practice Court")]
        value.setup.locations = [TennisLocation(name: "Home Club")]
        let venue = value.setup.venues[0].id
        value.setup.tournamentTemplates = [TennisTournamentTemplate(name: "Club Event", venueID: venue)]
        var tournament = TournamentRecord(playerID: player.id)
        tournament.date = Date(timeIntervalSince1970: 1000); tournament.endDate = Date(timeIntervalSince1970: 2000)
        tournament.venueID = venue; tournament.templateID = value.setup.tournamentTemplates[0].id
        value.tournaments = [tournament]
        var training = TrainingSession(playerID: player.id)
        training.date = Date(timeIntervalSince1970: 1000)
        training.actualStart = training.date; training.actualFinish = training.date.addingTimeInterval(159)
        training.focus = "Serve and return"; training.additionalFocus = ["Footwork"]
        training.workout = TennisWorkoutResult(workoutID: UUID(), durationSeconds: 159, averageHeartRate: 100, activeEnergyKcal: 5)
        training.trackedOnWatch = true
        training.context.coachIDs = value.setup.coaches.map(\.id)
        training.context.participantIDs = [partner.id]; training.context.venueID = venue
        value.trainingSessions = [training]
        var match = MatchRecord(playerID: player.id)
        match.date = training.date; match.status = .completed; match.matchType = .doubles
        match.partnerID = partner.id; match.tournamentID = tournament.id
        match.trainingSessionID = training.id; match.venueID = venue
        value.matches = [match]
        value.deletedRecordIDs = [UUID()]
        return try! JSONDecoder.tennisTracker.decode(AppData.self, from: JSONEncoder.tennisTracker.encode(value))
    }
}
