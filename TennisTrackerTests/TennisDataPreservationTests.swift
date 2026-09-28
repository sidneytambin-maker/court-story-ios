import XCTest
@testable import TennisTracker

final class TennisDataPreservationTests: XCTestCase {
    @MainActor func testFullStoreAndWatchCommandsPreserveSetupLinksHealthScoresAndDeletions() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        var data = AppData()
        data.players = ["Alex", "Sam", "Jo", "Kim"].map { name in
            var player = PlayerProfile(); player.name = name; player.playingHand = "Both hands"
            player.isRegularPartner = true; player.profileNotes = "Keep player notes"
            return player
        }
        data.selectedPlayerID = data.players[0].id
        data.setup.coaches = (1...6).map { TennisCoach(name: "Coach \($0)", organisation: "Club", notes: "Keep coach notes") }
        data.setup.venues = (1...12).map { TennisVenue(name: "Court \($0)", town: "Town", address: "Club address", notes: "Keep venue notes") }
        data.setup.locations = [TennisLocation(name: "Town")]
        data.setup.tournamentTemplates = [TennisTournamentTemplate(name: "League", venueID: data.setup.venues[0].id)]
        data.settings.calendarIntegrationEnabled = true
        data.settings.reminderLeadMinutes = 15
        var tournament = TournamentRecord(playerID: data.players[0].id)
        tournament.name = "Club Open"; tournament.venueID = data.setup.venues[0].id
        tournament.date = now; tournament.endDate = now.addingTimeInterval(86400)
        tournament.modifiedAt = now; tournament.notes = "Keep tournament notes"
        data.tournaments = [tournament]
        var training = TrainingSession(playerID: data.players[0].id)
        training.date = now.addingTimeInterval(-7200); training.modifiedAt = now
        training.focus = "Serve and return"; training.trainingType = .doublesPractice
        training.context.coachIDs = [data.setup.coaches[0].id, data.setup.coaches[5].id]
        training.context.otherCoachName = "Guest coach"
        training.context.participantIDs = [data.players[1].id, data.players[2].id]
        training.context.venueID = data.setup.venues[0].id
        training.context.tournamentID = tournament.id
        training.context.captureLegacyNames(coaches: data.setup.coaches, players: data.players)
        training.actualStart = now.addingTimeInterval(-159); training.actualFinish = now
        training.workout = TennisWorkoutResult(workoutID: UUID(), durationSeconds: 159, averageHeartRate: 72,
            activeEnergyKcal: 4, peakHeartRate: 90, distanceMeters: 123, stepCount: 201)
        training.notes = "Keep training notes"
        data.trainingSessions = [training]
        var match = MatchRecord(playerID: data.players[0].id)
        match.date = now; match.modifiedAt = now; match.matchType = .doubles
        match.playerName = "Alex"; match.opponentID = data.players[1].id; match.opponentName = "Sam"
        match.partnerID = data.players[2].id; match.partnerName = "Jo"
        match.opponent2ID = data.players[3].id; match.opponent2Name = "Kim"
        match.venueID = data.setup.venues[0].id; match.tournamentID = tournament.id
        match.trainingSessionID = training.id; match.yourSetsWon = 1; match.setScores = "6\u{2013}4, 7\u{2013}5"
        match.environment = TennisMatchEnvironment(noise: .loud, setting: .outdoors, weather: [.sunny, .lightRain, .windy])
        match.courtSurface = .artificialGrass; match.notes = "Keep match notes"
        data.matches = [match]; data.deletedRecordIDs = [UUID()]
        try JSONEncoder.tennisTracker.encode(data).write(to: url)
        let store = TennisStore(storeURL: url)
        XCTAssertEqual(store.data, data)

        // Exercise the same command path as a real Watch edit, then save unrelated settings.
        var draft = training; draft.notes = "Updated on Watch"
        let edited = TennisWatchRecordEdits.training(draft, current: training, now: now)
        let command = try JSONDecoder.tennisTracker.decode(TennisWatchSyncCommand.self,
            from: JSONEncoder.tennisTracker.encode(TennisWatchSyncCommand.upsertTraining(edited)))
        store.applyWatchCommand(command)
        store.updateSettings(data.settings)
        let reloaded = TennisStore(storeURL: url)
        XCTAssertEqual(reloaded.data.setup, data.setup)
        XCTAssertEqual(reloaded.data.players, data.players)
        XCTAssertEqual(reloaded.data.matches, data.matches)
        XCTAssertEqual(reloaded.data.tournaments, data.tournaments)
        XCTAssertEqual(reloaded.data.settings, data.settings)
        XCTAssertEqual(reloaded.data.deletedRecordIDs, data.deletedRecordIDs)
        var completedContext = training.context
        completedContext.coachesNeedDetails = false
        completedContext.participantsNeedDetails = false
        XCTAssertEqual(reloaded.data.trainingSessions[0].context, completedContext)
        XCTAssertEqual(reloaded.data.trainingSessions[0].workout, training.workout)
        XCTAssertEqual(reloaded.data.trainingSessions[0].actualStart, training.actualStart)
        XCTAssertEqual(reloaded.data.trainingSessions[0].actualFinish, training.actualFinish)
        XCTAssertEqual(reloaded.data.trainingSessions[0].focus, training.focus)
        XCTAssertEqual(reloaded.data.trainingSessions[0].notes, "Updated on Watch")
        let snapshot = TennisWatchSnapshot(data: reloaded.data, now: now)
        let wire = try JSONDecoder.tennisTracker.decode(TennisWatchSnapshot.self, from: JSONEncoder.tennisTracker.encode(snapshot))
        XCTAssertEqual(wire, snapshot)
        XCTAssertEqual(wire.setup.venues.count, 12)
        XCTAssertEqual(wire.matches[0].environment.weather, [.sunny, .lightRain, .windy])

        store.deleteTraining(reloaded.data.trainingSessions[0])
        store.applyWatchCommand(command)
        let afterDelete = TennisStore(storeURL: url)
        XCTAssertTrue(afterDelete.data.trainingSessions.isEmpty)
        XCTAssertTrue(afterDelete.data.deletedRecordIDs.contains(training.id))
        XCTAssertEqual(afterDelete.data.setup, data.setup)
        XCTAssertEqual(afterDelete.data.players, data.players)
    }
}
