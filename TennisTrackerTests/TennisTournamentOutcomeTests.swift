import XCTest
@testable import TennisTracker

final class TennisTournamentOutcomeTests: XCTestCase {
    func testLegacyStagesDecodeWithoutInventingFinishingPosition() throws {
        let legacy: [(TournamentStage, String)] = [
            (.notStarted, "Not started"), (.groupStage, "Group stage"), (.last16, "Last 16"),
            (.quarterFinal, "Quarter-final"), (.semiFinal, "Semi-final"), (.final, "Final"), (.winner, "Winner")
        ]
        for (stage, rawValue) in legacy {
            var original = fixture()
            original.stageReached = stage
            var json = try object(original)
            json.removeValue(forKey: "finishingPosition")
            json.removeValue(forKey: "hasExplicitStatus")
            json["stageReached"] = rawValue
            let restored = try decode(json)
            XCTAssertEqual(restored, original, rawValue)
            XCTAssertNil(restored.finishingPosition, rawValue)
        }
    }

    func testMinimalLegacyRecordKeepsDefaultStageAndOptionalPosition() throws {
        let restored = try decode(["playerID": UUID().uuidString])
        XCTAssertEqual(restored.stageReached, .notStarted)
        XCTAssertNil(restored.finishingPosition)
    }

    func testStageChoicesIncludeRoundRobinGroupsAndEveryPlacementPlayOff() throws {
        let expected: [TournamentStage] = [
            .roundRobin, .groupStage, .thirdFourthPlayOff, .fifthSixthPlayOff, .seventhEighthPlayOff,
            .ninthTenthPlayOff, .eleventhTwelfthPlayOff, .thirteenthFourteenthPlayOff, .fifteenthSixteenthPlayOff
        ]
        for stage in expected {
            XCTAssertTrue(TournamentStage.allCases.contains(stage))
            XCTAssertFalse(stage.rawValue.contains("/"))
        }
        XCTAssertEqual(Set(TournamentStage.allCases.map(\.rawValue)).count, TournamentStage.allCases.count)
        for stage in TournamentStage.allCases {
            for position in 1...16 {
                var original = fixture()
                original.stageReached = stage
                original.finishingPosition = position
                XCTAssertEqual(try roundTrip(original), original)
            }
        }
    }

    func testFinishingPositionsValidateAndUseCorrectOrdinals() {
        let labels = ["1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th", "10th", "11th", "12th", "13th", "14th", "15th", "16th"]
        XCTAssertEqual(TournamentFinishingPosition.allValues, Array(1...16))
        for (index, label) in labels.enumerated() {
            var tournament = fixture()
            tournament.finishingPosition = index + 1
            XCTAssertEqual(tournament.finishingPosition, index + 1)
            XCTAssertEqual(TournamentFinishingPosition.label(tournament.finishingPosition), label)
        }
        for invalid in [Int.min, -1, 0, 17, Int.max] {
            var tournament = fixture()
            tournament.finishingPosition = invalid
            XCTAssertNil(tournament.finishingPosition)
            XCTAssertEqual(TournamentFinishingPosition.label(invalid), "Not recorded")
        }
        XCTAssertEqual(TournamentFinishingPosition.label(nil), "Not recorded")
    }

    func testInvalidPositionDoesNotDiscardOtherSavedTournamentData() throws {
        let original = fixture()
        let invalidValues: [Any] = [-1, 0, 17, "3rd", 3.5, true, NSNull()]
        for invalid in invalidValues {
            var json = try object(original)
            json["finishingPosition"] = invalid
            let restored = try decode(json)
            XCTAssertNil(restored.finishingPosition)
            XCTAssertEqual(restored, original)
        }
    }

    func testStageAndPositionChangeIndependentlyAndPositionCanBeCleared() throws {
        var tournament = fixture()
        tournament.stageReached = .fifthSixthPlayOff
        tournament.finishingPosition = 6
        XCTAssertEqual(tournament.stageReached, .fifthSixthPlayOff)
        tournament.stageReached = .groupStage
        XCTAssertEqual(tournament.finishingPosition, 6)
        tournament.finishingPosition = nil
        let restored: TournamentRecord = try roundTrip(tournament)
        XCTAssertEqual(restored.stageReached, .groupStage)
        XCTAssertNil(restored.finishingPosition)
        tournament.stageReached = .winner
        XCTAssertNil(tournament.finishingPosition)
    }

    func testSummariesGiveStageAndPositionDistinctLabels() {
        var tournament = fixture()
        tournament.stageReached = .fifthSixthPlayOff
        tournament.finishingPosition = 6
        for style in [TennisSummaryStyle.short, .long, .detailed, .accessibility] {
            let summary = TennisSummaryFormatter.tournament(tournament, style: style)
            XCTAssertTrue(summary.contains("Stage reached: 5th and 6th place play-off"))
            XCTAssertTrue(summary.contains("Finishing position: 6th"))
        }
        tournament.finishingPosition = nil
        XCTAssertFalse(TennisSummaryFormatter.tournament(tournament).contains("Finishing position:"))
        XCTAssertTrue(TennisSummaryFormatter.tournament(tournament, style: .accessibility).contains("Finishing position: Not recorded"))
        tournament.stageReached = .notStarted
        XCTAssertFalse(TennisSummaryFormatter.tournament(tournament, style: .short).contains("Stage reached:"))
        XCTAssertTrue(TennisSummaryFormatter.tournament(tournament, style: .accessibility).contains("Stage reached: Not started"))
    }

    func testSummaryValueDoesNotRepeatSeparateAccessibleName() {
        var tournament = fixture()
        tournament.hasExplicitStatus = true
        tournament.finishingPosition = 5
        let value = TennisSummaryFormatter.tournament(tournament, style: .accessibility, includeName: false)
        XCTAssertFalse(value.contains(tournament.name))
        XCTAssertTrue(value.contains("Stage reached: Quarter-final"))
        XCTAssertTrue(value.contains("Finishing position: 5th"))
        XCTAssertTrue(value.contains("Status: Entered"))
        XCTAssertTrue(value.contains("Format: Round robin"))
    }

    func testWatchEditPreservesOtherDataAndConcurrentFinish() {
        var current = fixture()
        var draft = current
        draft.stageReached = .thirdFourthPlayOff
        draft.finishingPosition = 4
        current.finalResult = .completed
        current.actualFinish = current.date.addingTimeInterval(3600)
        current.revision = 8
        let saved = TennisWatchRecordEdits.tournament(draft, current: current, now: current.modifiedAt)
        var expected = current
        expected.stageReached = .thirdFourthPlayOff
        expected.finishingPosition = 4
        expected.revision += 1
        XCTAssertEqual(saved, expected)

        var cleared = saved
        cleared.finishingPosition = nil
        let savedClear = TennisWatchRecordEdits.tournament(cleared, current: saved)
        XCTAssertNil(savedClear.finishingPosition)
        XCTAssertEqual(savedClear.stageReached, .thirdFourthPlayOff)
    }

    func testOfflineEditSurvivesOlderSnapshotThenAcknowledgesBothFields() throws {
        let original = fixture()
        var draft = original
        draft.stageReached = .fifteenthSixteenthPlayOff
        draft.finishingPosition = 15
        let saved = TennisWatchRecordEdits.tournament(draft, current: original, now: original.modifiedAt)
        let command: TennisWatchSyncCommand = try roundTrip(.upsertTournament(saved))
        var older = TennisWatchSnapshot()
        older.tournaments = [original]
        let pending = TennisWatchReconciliation.reconcile(incoming: older, pending: [command])
        XCTAssertEqual(pending.snapshot.tournaments, [saved])
        XCTAssertEqual(pending.pending, [command])
        var acknowledged = older
        acknowledged.tournaments = [saved]
        let result = TennisWatchReconciliation.reconcile(incoming: try roundTrip(acknowledged), pending: pending.pending)
        XCTAssertEqual(result.snapshot.tournaments, [saved])
        XCTAssertTrue(result.pending.isEmpty)
    }

    func testSnapshotUsesWholeSecondModifiedAtWithoutChangingTournamentFields() throws {
        var original = fixture()
        original.stageReached = .seventhEighthPlayOff
        original.finishingPosition = 8
        let fractionalDate = original.modifiedAt.addingTimeInterval(0.375)
        let saved = TennisRecordConflictResolver.prepareLocalTournament(original, now: fractionalDate)
        var snapshot = TennisWatchSnapshot()
        snapshot.generatedAt = original.date
        snapshot.tournaments = [saved]

        let restored: TennisWatchSnapshot = try roundTrip(snapshot)
        var expected = original
        expected.revision += 1
        XCTAssertEqual(saved.modifiedAt, fractionalDate)
        XCTAssertNotEqual(saved.modifiedAt, expected.modifiedAt)
        XCTAssertEqual(restored.tournaments, [expected])
        XCTAssertEqual(try XCTUnwrap(restored.tournaments.first).modifiedAt, original.modifiedAt)
        XCTAssertEqual(snapshot.tournaments, [saved])
    }

    @MainActor func testStoreWatchSyncAndReloadPreserveBothMetricsAndLinkedData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = fixture()
        var player = PlayerProfile()
        player.id = original.playerID
        player.name = "Example player"
        var data = AppData()
        data.players = [player]
        data.selectedPlayerID = player.id
        data.onboardingCompleted = true
        data.tournaments = [original]
        var match = MatchRecord(playerID: player.id)
        match.tournamentID = original.id
        match.notes = "Keep linked match"
        data.matches = [match]
        data = try roundTrip(data)
        try JSONEncoder.tennisTracker.encode(data).write(to: url)

        let phone = TennisStore(storeURL: url)
        var edited = original
        edited.stageReached = .seventhEighthPlayOff
        edited.finishingPosition = 8
        phone.upsertTournament(edited)
        let phoneSaved = try XCTUnwrap(phone.data.tournaments.first)
        let snapshot: TennisWatchSnapshot = try roundTrip(TennisWatchSnapshot(data: phone.data, now: original.date))
        var expectedSnapshotTournament = edited
        expectedSnapshotTournament.revision += 1
        // The store keeps subsecond Date() values; the existing ISO-8601 wire format carries whole seconds.
        expectedSnapshotTournament.modifiedAt = Date(timeIntervalSince1970: phoneSaved.modifiedAt.timeIntervalSince1970.rounded(.down))
        XCTAssertNil(phone.storageError)
        XCTAssertEqual(snapshot.tournaments, [expectedSnapshotTournament])
        XCTAssertEqual(snapshot.tournaments.first?.stageReached, .seventhEighthPlayOff)
        XCTAssertEqual(snapshot.tournaments.first?.finishingPosition, 8)

        var watchDraft = phoneSaved
        watchDraft.finishingPosition = 7
        let watchSaved = TennisWatchRecordEdits.tournament(watchDraft, current: phoneSaved, now: phoneSaved.modifiedAt)
        phone.applyWatchCommand(try roundTrip(TennisWatchSyncCommand.upsertTournament(watchSaved)))
        phone.applyWatchCommand(.upsertTournament(original))
        let reloaded = TennisStore(storeURL: url)
        XCTAssertNil(reloaded.storageError)
        XCTAssertEqual(reloaded.data.tournaments, [try roundTrip(watchSaved)])
        XCTAssertEqual(reloaded.data.matches, data.matches)
        XCTAssertEqual(reloaded.data.players, data.players)
        XCTAssertEqual(reloaded.data.setup, data.setup)

        var cleared = try XCTUnwrap(reloaded.data.tournaments.first)
        cleared.finishingPosition = nil
        cleared = TennisWatchRecordEdits.tournament(cleared, current: cleared)
        reloaded.applyWatchCommand(try roundTrip(TennisWatchSyncCommand.upsertTournament(cleared)))
        let afterClear = TennisStore(storeURL: url)
        XCTAssertNil(afterClear.data.tournaments.first?.finishingPosition)
        XCTAssertEqual(afterClear.data.tournaments.first?.stageReached, .seventhEighthPlayOff)
    }

    @MainActor func testPrivateBackupRestoresNewTournamentFieldsAndLinkedRecords() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destinationURL)
        }
        var player = PlayerProfile()
        player.name = "Example player"
        var data = AppData()
        data.players = [player]
        data.selectedPlayerID = player.id
        data.onboardingCompleted = true
        let venue = TennisVenue(name: "Example venue")
        let template = TennisTournamentTemplate(name: "Example series", venueID: venue.id)
        data.setup.venues = [venue]
        data.setup.tournamentTemplates = [template]
        data.tournaments = TournamentStage.allCases.enumerated().map { index, stage in
            var tournament = fixture()
            tournament.playerID = player.id
            tournament.venueID = venue.id
            tournament.templateID = template.id
            tournament.stageReached = stage
            tournament.finishingPosition = index + 1
            tournament.hasExplicitStatus = true
            tournament.date = Date(timeIntervalSince1970: 1_000)
            tournament.endDate = Date(timeIntervalSince1970: 2_000)
            return tournament
        }
        var unplaced = fixture()
        unplaced.playerID = player.id
        unplaced.venueID = venue.id
        unplaced.templateID = template.id
        unplaced.stageReached = .winner
        data.tournaments.append(unplaced)
        var last = unplaced
        last.id = UUID()
        last.stageReached = .fifteenthSixteenthPlayOff
        last.finishingPosition = 16
        data.tournaments.append(last)
        var match = MatchRecord(playerID: player.id)
        match.tournamentID = data.tournaments[0].id
        data.matches = [match]
        data = try roundTrip(data)
        try JSONEncoder.tennisTracker.encode(data).write(to: sourceURL)

        let source = TennisStore(storeURL: sourceURL)
        let backup = try TennisBackup.decode(source.backupData())
        XCTAssertEqual(backup, data)
        let destination = TennisStore(storeURL: destinationURL)
        try destination.restoreBackup(backup)
        let reloaded = TennisStore(storeURL: destinationURL)
        XCTAssertNil(reloaded.storageError)
        XCTAssertEqual(reloaded.data.tournaments, data.tournaments)
        XCTAssertEqual(reloaded.data.matches, data.matches)
        XCTAssertEqual(reloaded.data.setup, data.setup)
        XCTAssertFalse(try XCTUnwrap(reloaded.data.tournaments.first).isCompleted)
        XCTAssertNotEqual(reloaded.data.libraryID, data.libraryID)
    }

    private func fixture() -> TournamentRecord {
        var tournament = TournamentRecord(playerID: UUID())
        tournament.name = "Example Open"
        tournament.date = Date(timeIntervalSince1970: 1_800_000_000)
        tournament.endDate = tournament.date.addingTimeInterval(86400)
        tournament.modifiedAt = tournament.date
        tournament.stageReached = .quarterFinal
        tournament.format = .roundRobin
        tournament.notes = "Keep tournament notes"
        tournament.goal = "Keep tournament goal"
        tournament.templateID = UUID()
        tournament.venueID = UUID()
        tournament.venue = "Example venue"
        tournament.location = "Example town"
        tournament.matchesPlayed = 3
        return tournament
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder.tennisTracker.decode(T.self, from: JSONEncoder.tennisTracker.encode(value))
    }

    private func object(_ tournament: TournamentRecord) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.tennisTracker.encode(tournament)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> TournamentRecord {
        try JSONDecoder.tennisTracker.decode(TournamentRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
