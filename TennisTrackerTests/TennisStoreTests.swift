import XCTest
@testable import TennisTracker

@MainActor
final class TennisStoreTests: XCTestCase {
    func testInvalidWatchScoreCannotReplaceSavedRecordOrPersistOnRelaunch() throws {
        let url = temporaryStoreURL()
        let store = TennisStore(storeURL: url)
        var player = PlayerProfile(); player.name = "Demo Player"
        XCTAssertTrue(store.completeOnboarding(player: player, settings: AppSettings()))
        var match = store.makeDefaultMatch()!
        match.opponentName = "Demo Opponent"
        XCTAssertTrue(store.upsertMatch(match))
        let original = store.data.matches[0]
        var invalid = original
        invalid.court.rules?.target = 0
        invalid.revision += 1; invalid.modifiedAt = Date().addingTimeInterval(10)
        store.applyWatchCommand(.upsertMatch(invalid))
        XCTAssertEqual(store.data.matches, [original])
        XCTAssertEqual(try JSONEncoder.tennisTracker.encode(TennisStore(storeURL: url).data.matches),
                       try JSONEncoder.tennisTracker.encode([original]))
    }

    func testWatchCannotAttachPersonalHealthToCoachedAthlete() {
        let store = TennisStore(storeURL: temporaryStoreURL())
        var owner = PlayerProfile(); owner.name = "Demo Coach"; owner.court.sports[0].role = .coach
        XCTAssertTrue(store.completeOnboarding(player: owner, settings: AppSettings()))
        var athlete = PlayerProfile(); athlete.name = "Demo Athlete"; athlete.court.coachOwnerID = owner.id
        XCTAssertTrue(store.saveCourtProfile(athlete))
        var training = TrainingSession(playerID: athlete.id)
        training.court = CourtActivity(player: athlete, coachID: owner.id)
        training.workout = TennisWorkoutResult(workoutID: UUID(), durationSeconds: 600, averageHeartRate: 120)
        store.applyWatchCommand(.upsertTraining(training))
        XCTAssertFalse(store.data.trainingSessions.contains { $0.id == training.id })
        XCTAssertTrue(store.lastAnnouncement.contains("Personal Health"))
    }

    func testMarkingTrainingCompleteDoesNotInventBodyRatings() {
        let store = TennisStore(storeURL: temporaryStoreURL())
        var session = TrainingSession(playerID: UUID())
        session.needsDetails = true
        session.hasSessionDetails = false
        session.context.coachesNeedDetails = true
        session.context.participantsNeedDetails = true
        store.upsertTraining(session)
        store.completeTrainingDetails(session.id)
        let saved = store.data.trainingSessions.first!
        XCTAssertFalse(saved.needsDetails)
        XCTAssertFalse(saved.hasSessionDetails)
        XCTAssertEqual(saved.context.coachesNeedDetails, false)
        XCTAssertEqual(saved.context.participantsNeedDetails, false)
        XCTAssertNil(saved.workout)
    }

    func testStaleTrainingEditorPreservesReceivedWorkout() {
        let store = TennisStore(storeURL: temporaryStoreURL())
        let draft = TrainingSession(playerID: UUID())
        store.upsertTraining(draft)
        var completed = store.data.trainingSessions.first!
        completed.actualStart = Date(timeIntervalSince1970: 100)
        completed.actualFinish = Date(timeIntervalSince1970: 700)
        completed.durationMinutes = 10
        completed.workout = TennisWorkoutResult(workoutID: UUID(), durationSeconds: 600, averageHeartRate: 120, activeEnergyKcal: 50)
        completed = TennisRecordConflictResolver.prepareLocalTraining(completed)
        store.applyWatchCommand(.upsertTraining(completed))
        var edited = draft
        edited.notes = "Notes entered while the Watch was saving"
        store.upsertTraining(edited)
        let saved = store.data.trainingSessions.first!
        XCTAssertEqual(saved.id, draft.id)
        XCTAssertEqual(saved.workout, completed.workout)
        XCTAssertEqual(saved.actualStart, completed.actualStart)
        XCTAssertEqual(saved.actualFinish, completed.actualFinish)
        XCTAssertEqual(saved.durationMinutes, 10)
        XCTAssertEqual(saved.notes, edited.notes)
        XCTAssertEqual(store.data.trainingSessions.count, 1)
    }

    func testSettingsThemeAndAnnouncementModePersist() {
        let url = temporaryStoreURL()
        let store = TennisStore(storeURL: url)
        var player = PlayerProfile()
        player.name = "Sidney"
        var settings = AppSettings()
        settings.theme = .classic
        settings.scoreAnnouncementMode = .reduced

        store.completeOnboarding(player: player, settings: settings)
        let reloaded = TennisStore(storeURL: url)

        XCTAssertEqual(reloaded.data.settings.theme, .classic)
        XCTAssertEqual(reloaded.data.settings.scoreAnnouncementMode, .reduced)
        XCTAssertEqual(reloaded.selectedPlayer?.displayName, "Sidney")
    }

    func testDefaultMatchUsesProfileAndLinksTournament() {
        let store = TennisStore(storeURL: temporaryStoreURL())
        var player = PlayerProfile()
        player.name = "Sidney"
        player.sightLevel = .b2
        player.playerMode = .blindTennis
        store.completeOnboarding(player: player, settings: AppSettings())
        var tournament = store.makeDefaultTournament()!
        tournament.name = "Regional Open"
        tournament.location = "Brighton Tennis Centre"
        tournament.date = Date(timeIntervalSince1970: 1_800_200_000)
        tournament.endDate = tournament.date.addingTimeInterval(86_400)
        tournament.hasStartTime = true
        tournament.isAllDay = false
        tournament.format = .roundRobin
        store.upsertTournament(tournament)

        let match = store.makeDefaultMatch(tournamentID: tournament.id)

        XCTAssertEqual(match?.playerName, "Sidney")
        XCTAssertEqual(match?.tournamentID, tournament.id)
        XCTAssertEqual(match?.date, tournament.date)
        XCTAssertEqual(match?.hasStartTime, true)
        XCTAssertEqual(match?.location, "Brighton Tennis Centre")
        XCTAssertEqual(match?.matchPosition, .roundRobin)
        XCTAssertEqual(match?.allowedBounces, 3)
        XCTAssertEqual(match?.suddenDeathDeuce, true)
    }

    func testLinkedMatchesAndTournamentDeleteChoicesStayConsistent() {
        let store = TennisStore(storeURL: temporaryStoreURL())
        var player = PlayerProfile()
        player.name = "Sidney"
        store.completeOnboarding(player: player, settings: AppSettings())
        var tournament = store.makeDefaultTournament()!
        store.upsertTournament(tournament)
        var linked = store.makeDefaultMatch(tournamentID: tournament.id)!
        linked.opponentName = "Klaudia"
        var unlinked = store.makeDefaultMatch()!
        unlinked.opponentName = "Sam"
        store.upsertMatch(linked)
        store.upsertMatch(unlinked)

        XCTAssertEqual(store.linkedMatches(for: tournament).map(\.id), [linked.id])

        store.deleteTournamentKeepingMatches(tournament)
        XCTAssertNil(store.data.matches.first { $0.id == linked.id }?.tournamentID)
        XCTAssertNotNil(store.data.matches.first { $0.id == unlinked.id })

        tournament.id = UUID()
        store.upsertTournament(tournament)
        linked.tournamentID = tournament.id
        store.upsertMatch(linked)
        store.deleteTournamentAndLinkedMatches(tournament)

        XCTAssertNil(store.data.matches.first { $0.id == linked.id })
        XCTAssertNotNil(store.data.matches.first { $0.id == unlinked.id })
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}
