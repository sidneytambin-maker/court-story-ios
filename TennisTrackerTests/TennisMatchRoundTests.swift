import XCTest
@testable import TennisTracker

final class TennisMatchRoundTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func match() -> MatchRecord {
        var match = MatchRecord(playerID: UUID())
        match.date = now
        match.modifiedAt = now
        match.revision = 4
        match.status = .scheduled
        match.playerName = "Alex"; match.partnerName = "Jo"
        match.opponentName = "Sam"; match.opponent2Name = "Kim"
        match.matchType = .doubles
        match.venue = "Example Centre"; match.location = "Example Town"
        return match
    }

    private func wire<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder.tennisTracker.decode(T.self, from: JSONEncoder.tennisTracker.encode(value))
    }

    func testLegacyRoundRawValuesAndIDsRemainStable() throws {
        let legacy: [(MatchPosition, String)] = [(.notSpecified, "Not specified"), (.roundRobin, "Round robin"),
            (.last16, "Last 16"), (.quarterFinal, "Quarter-final"), (.semiFinal, "Semi-final"), (.final, "Final")]
        for (round, raw) in legacy {
            let bytes = try JSONEncoder().encode(raw)
            XCTAssertEqual(try JSONDecoder().decode(MatchPosition.self, from: bytes), round)
            XCTAssertEqual(try JSONDecoder().decode(String.self, from: JSONEncoder().encode(round)), raw)
            XCTAssertEqual(round.id, raw)
        }
        XCTAssertEqual(MatchPosition.last16.label, "Round of 16")
        XCTAssertEqual(MatchPosition.notSpecified.label, "Not specified")
    }

    func testEveryRoundRoundTripsWithoutDuplicateOptionsOrIdentityChanges() throws {
        XCTAssertEqual(Set(MatchPosition.allCases.map(\.label)).count, MatchPosition.allCases.count)
        for round in MatchPosition.allCases {
            var record = match(); record.matchPosition = round
            XCTAssertEqual(try wire(record), record)
        }
        for round in [MatchPosition.qualifying, .groupStage, .roundRobin, .roundOf128, .roundOf64, .roundOf32,
            .last16, .quarterFinal, .semiFinal, .final, .thirdPlacePlayOff, .fifthPlacePlayOff,
            .seventhPlacePlayOff, .placementPlayOff, .consolation] {
            XCTAssertTrue(MatchPosition.allCases.contains(round))
        }
    }

    func testMissingLegacyRoundAndTimeMetadataRemainUnspecified() throws {
        let record = match()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.tennisTracker.encode(record)) as? [String: Any])
        json.removeValue(forKey: "matchPosition")
        json.removeValue(forKey: "hasStartTime")
        let decoded = try JSONDecoder.tennisTracker.decode(MatchRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.matchPosition, .notSpecified)
        XCTAssertFalse(decoded.hasStartTime)
        XCTAssertEqual(decoded.date, record.date)
        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.stableShareID, record.stableShareID)
        let summary = TennisSummaryFormatter.matchSummary(decoded)
        XCTAssertEqual(summary.headline, "Scheduled doubles match")
        XCTAssertEqual(summary.scheduleText, "\(record.date.tennisSummaryDate) at Example Centre, Example Town")
    }

    func testScheduledDoublesRoundSummaryIncludesTimeOnlyWhenExplicit() {
        var record = match(); record.matchPosition = .semiFinal
        let original = record
        let summary = TennisSummaryFormatter.matchSummary(record)
        XCTAssertEqual(summary.headline, "Scheduled doubles semi-final")
        XCTAssertEqual(summary.longText, "Scheduled doubles semi-final. Alex and Jo will play Sam and Kim, \(record.date.tennisSummaryDate) at Example Centre, Example Town.")
        XCTAssertEqual(summary.accessibilityText, summary.longText)
        XCTAssertEqual(record, original)
        record.hasStartTime = true
        XCTAssertEqual(TennisSummaryFormatter.matchSummary(record).scheduleText,
            "\(record.date.tennisSummaryDate) at \(record.date.shortTennisTime) at Example Centre, Example Town")
        record.location = record.venue
        XCTAssertEqual(TennisSummaryFormatter.matchSummary(record).scheduleText,
            "\(record.date.tennisSummaryDate) at \(record.date.shortTennisTime) at Example Centre")
    }

    func testAllSummaryStylesPreserveDoublesTiebreakOpponentsAndTournament() {
        var record = match(); record.matchPosition = .final; record.status = .completed
        record.matchFormat = .oneSet
        var tournament = TournamentRecord(playerID: record.playerID); tournament.name = "Example Open"
        tournament.finishingPosition = 3
        record.tournamentID = tournament.id; record.trainingSessionID = UUID()
        TennisRecordedScore.apply([TennisRecordedSet(yourGames: 6, opponentGames: 6, hasTiebreak: true,
            yourTiebreak: 9, opponentTiebreak: 7)], to: &record)
        let original = record
        for style in [TennisSummaryStyle.short, .long, .accessibility, .detailed] {
            let text = TennisSummaryFormatter.match(record, tournaments: [tournament], style: style)
            for phrase in ["Completed doubles final", "Alex and Jo beat Sam and Kim", "Example Open",
                "tie-break: your 9 points, opponent 7 points"] {
                XCTAssertTrue(text.contains(phrase), text)
            }
            XCTAssertFalse(text.contains("Third"))
        }
        XCTAssertEqual(record, original)
        XCTAssertEqual(tournament.finishingPosition, 3)
    }

    func testLiveRoundSummaryKeepsScoreAndOrdinaryMatchDoesNotInventRound() {
        var record = match(); record.status = .inProgress; record.matchPosition = .roundRobin
        record.liveScore = TennisScoreSnapshot(playerPoints: 2, opponentPoints: 1, playerGames: 4, opponentGames: 3)
        let summary = TennisSummaryFormatter.matchSummary(record)
        XCTAssertEqual(summary.headline, "In progress doubles round robin")
        XCTAssertTrue(summary.longText.contains("Alex and Jo are playing Sam and Kim"))
        XCTAssertTrue(summary.scoreText.contains("4-3")); XCTAssertTrue(summary.scoreText.contains("30-15"))
        record.matchPosition = .notSpecified; record.matchType = .singles
        XCTAssertEqual(TennisSummaryFormatter.matchSummary(record).headline, "In progress singles match")
    }

    func testWatchRoundAndScheduleEditsPreserveIdentityAndLinks() throws {
        let original = match()
        var draft = original; draft.matchPosition = .roundOf32
        draft.date = now.addingTimeInterval(3600); draft.hasStartTime = true
        draft.tournamentID = UUID(); draft.trainingSessionID = UUID()
        let saved = TennisWatchRecordEdits.match(draft, current: original, original: original, now: now)
        var expected = draft; expected.revision += 1
        XCTAssertEqual(saved, expected)
        XCTAssertEqual(try wire(saved), expected)
    }

    func testUnchangedWatchFieldsDoNotEraseConcurrentPhoneRoundAndSchedule() {
        let original = match()
        var phone = original; phone.matchPosition = .semiFinal; phone.hasStartTime = true
        phone.date = now.addingTimeInterval(7200); phone.revision += 1
        var draft = original; draft.notes = "Watch note"
        let saved = TennisWatchRecordEdits.match(draft, current: phone, original: original, now: now)
        var expected = phone; expected.notes = draft.notes; expected.revision += 1
        XCTAssertEqual(saved, expected)
    }

    func testConflictingWatchRoundAndTimeEditsKeepCurrentPhoneValues() {
        var original = match(); original.matchPosition = .quarterFinal
        var phone = original; phone.matchPosition = .final; phone.hasStartTime = true
        phone.date = now.addingTimeInterval(7200); phone.revision += 1
        var draft = original; draft.matchPosition = .semiFinal
        draft.date = now.addingTimeInterval(3600); draft.hasStartTime = true
        let saved = TennisWatchRecordEdits.match(draft, current: phone, original: original, now: now)
        var expected = phone; expected.revision += 1
        XCTAssertEqual(saved, expected)
    }

    func testExplicitRoundCanBeClearedWithoutErasingKnownTime() {
        var original = match(); original.matchPosition = .final; original.hasStartTime = true
        var draft = original; draft.matchPosition = .notSpecified
        let saved = TennisWatchRecordEdits.match(draft, current: original, original: original, now: now)
        var expected = draft; expected.revision += 1
        XCTAssertEqual(saved, expected)
    }

    func testActiveScoreUpdateKeepsTimingButAcceptsIndependentRoundEdit() {
        var original = match(); original.status = .inProgress; original.actualStart = now; original.hasStartTime = true
        var latest = original; latest.revision += 1
        latest.liveScore = TennisScoreSnapshot(playerPoints: 2, opponentPoints: 1, playerGames: 4, opponentGames: 3)
        var draft = original; draft.matchPosition = .semiFinal
        draft.date = now.addingTimeInterval(3600); draft.hasStartTime = false
        let saved = TennisWatchRecordEdits.match(draft, current: latest, original: original, now: now)
        var expected = latest; expected.matchPosition = .semiFinal; expected.revision += 1
        XCTAssertEqual(saved, expected)
    }

    func testScheduledEditorCannotUndoConcurrentStartOrFinish() {
        let original = match()
        for status in [MatchStatus.inProgress, .completed] {
            var latest = original; latest.status = status; latest.actualStart = now
            latest.hasStartTime = true; latest.revision += 1
            if status == .completed { latest.actualFinish = now.addingTimeInterval(1800) }
            var draft = original; draft.date = now.addingTimeInterval(86400); draft.matchPosition = .final
            let saved = TennisWatchRecordEdits.match(draft, current: latest, original: original, now: now)
            var expected = latest; expected.matchPosition = .final; expected.revision += 1
            XCTAssertEqual(saved, expected)
        }
    }

    func testCompletedDateOnlyEditPreservesActualRecordingTimes() {
        var original = match(); original.status = .completed; original.hasStartTime = true
        original.actualStart = now; original.actualFinish = now.addingTimeInterval(3600)
        var draft = original; draft.hasStartTime = false; draft.date = now.addingTimeInterval(86400)
        let saved = TennisWatchRecordEdits.match(draft, current: original, original: original, now: now)
        var expected = draft; expected.revision += 1
        XCTAssertEqual(saved, expected)
    }

    func testUnknownOrWrongEditorBaselineCannotReplaceNewerRoundOrSchedule() {
        let original = match()
        var latest = original; latest.matchPosition = .final; latest.hasStartTime = true; latest.revision += 1
        var draft = original; draft.matchPosition = .semiFinal; draft.date = now.addingTimeInterval(3600)
        var wrong = original; wrong.id = UUID()
        for baseline in [MatchRecord?.none, Optional(wrong)] {
            let saved = TennisWatchRecordEdits.match(draft, current: latest, original: baseline, now: now)
            var expected = latest; expected.revision += 1
            XCTAssertEqual(saved, expected)
        }
    }

    @MainActor
    func testPhoneEditorPreservesConcurrentWatchRoundAndSchedule() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let phone = TennisStore(storeURL: url)
        var player = PlayerProfile(); player.name = "Alex"
        XCTAssertTrue(phone.completeOnboarding(player: player, settings: AppSettings()))
        var original = match(); original.playerID = player.id
        phone.applyWatchCommand(.upsertMatch(original))
        var watch = original; watch.matchPosition = .semiFinal
        watch.date = now.addingTimeInterval(3600); watch.hasStartTime = true; watch.revision += 1
        phone.applyWatchCommand(.upsertMatch(watch))
        var draft = original; draft.notes = "Phone note"; draft.matchPosition = .quarterFinal
        draft.date = now.addingTimeInterval(7200)
        phone.upsertMatch(draft, original: original)
        let saved = try XCTUnwrap(phone.data.matches.first)
        var expected = watch; expected.notes = draft.notes
        expected.revision += 1; expected.modifiedAt = saved.modifiedAt
        XCTAssertEqual(saved, expected)
        XCTAssertEqual(TennisStore(storeURL: url).data.matches, [try wire(expected)])
    }

    func testWatchSnapshotRetainsEveryScheduledMatchBeyondHistoryDateAndCountLimits() throws {
        var data = AppData()
        let player = PlayerProfile(); data.players = [player]; data.selectedPlayerID = player.id
        var overdue = match(); overdue.playerID = player.id; overdue.date = now.addingTimeInterval(-90 * 86400)
        overdue.matchPosition = .qualifying
        let future = (1...40).map { day -> MatchRecord in
            var record = match(); record.playerID = player.id; record.date = now.addingTimeInterval(Double(day) * 86400)
            record.matchPosition = .roundRobin; record.hasStartTime = true
            return record
        }
        var oldCompleted = overdue; oldCompleted.id = UUID(); oldCompleted.status = .completed
        var oldActive = overdue; oldActive.id = UUID(); oldActive.status = .inProgress
        var oldNeedsDetails = oldCompleted; oldNeedsDetails.id = UUID(); oldNeedsDetails.needsDetails = true
        data.matches = [overdue, oldCompleted, oldActive, oldNeedsDetails] + future
        let original = data
        let snapshot = try wire(TennisWatchSnapshot(data: data, now: now))
        let expected = [overdue, oldActive, oldNeedsDetails] + future
        XCTAssertEqual(Set(snapshot.matches.map(\.id)), Set(expected.map(\.id)))
        XCTAssertEqual(snapshot.matches.count, expected.count)
        for record in expected { XCTAssertEqual(snapshot.matches.first { $0.id == record.id }, record) }
        XCTAssertEqual(data, original)
    }

    @MainActor
    func testPhoneEditorSavesAndClearsExplicitRoundAndKnownTime() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let phone = TennisStore(storeURL: url)
        var player = PlayerProfile(); player.name = "Alex"
        XCTAssertTrue(phone.completeOnboarding(player: player, settings: AppSettings()))
        var original = match(); original.playerID = player.id
        phone.applyWatchCommand(.upsertMatch(original))
        var draft = original; draft.matchPosition = .final; draft.hasStartTime = true
        draft.date = now.addingTimeInterval(3600)
        phone.upsertMatch(draft, original: original)
        let saved = try XCTUnwrap(phone.data.matches.first)
        var expected = draft; expected.revision += 1; expected.modifiedAt = saved.modifiedAt
        XCTAssertEqual(saved, expected)
        var cleared = saved; cleared.matchPosition = .notSpecified; cleared.hasStartTime = false
        phone.upsertMatch(cleared, original: saved)
        let savedClear = try XCTUnwrap(phone.data.matches.first)
        cleared.revision += 1; cleared.modifiedAt = savedClear.modifiedAt
        XCTAssertEqual(savedClear, cleared)
        XCTAssertEqual(savedClear.date, saved.date)
        XCTAssertFalse(TennisSummaryFormatter.matchSummary(savedClear).scheduleText.contains(saved.date.shortTennisTime))
    }

    @MainActor
    func testPhoneSaveReloadBackupAndWatchSyncKeepRoundAndCompleteRecord() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let phone = TennisStore(storeURL: url)
        var player = PlayerProfile(); player.name = "Alex"
        XCTAssertTrue(phone.completeOnboarding(player: player, settings: AppSettings()))
        var record = match(); record.playerID = player.id; record.matchPosition = .last16; record.hasStartTime = true
        phone.upsertMatch(record)
        let reloaded = TennisStore(storeURL: url)
        let saved = try XCTUnwrap(reloaded.data.matches.first)
        XCTAssertEqual(saved.matchPosition, .last16); XCTAssertEqual(saved.id, record.id)
        XCTAssertEqual(saved.stableShareID, record.stableShareID); XCTAssertEqual(saved.date, record.date)
        XCTAssertTrue(saved.hasStartTime)
        XCTAssertEqual(try TennisBackup.decode(reloaded.backupData()), reloaded.data)
        let snapshot = try wire(TennisWatchSnapshot(data: reloaded.data, now: now))
        XCTAssertEqual(snapshot.matches, [saved])
        var draft = saved; draft.matchPosition = .placementPlayOff
        let edited = TennisWatchRecordEdits.match(draft, current: saved, original: saved, now: now.addingTimeInterval(1))
        let command = try wire(TennisWatchSyncCommand.upsertMatch(edited))
        let pending = TennisWatchReconciliation.reconcile(incoming: snapshot, pending: [command])
        XCTAssertEqual(pending.snapshot.matches, [edited]); XCTAssertEqual(pending.pending, [command])
        reloaded.applyWatchCommand(command)
        let acknowledged = try wire(TennisWatchSnapshot(data: reloaded.data, now: now.addingTimeInterval(2)))
        let reconciled = TennisWatchReconciliation.reconcile(incoming: acknowledged, pending: pending.pending)
        XCTAssertEqual(reconciled.snapshot.matches, [edited]); XCTAssertTrue(reconciled.pending.isEmpty)
        reloaded.applyWatchCommand(.upsertMatch(saved))
        XCTAssertEqual(reloaded.data.matches, [edited])
        XCTAssertEqual(TennisStore(storeURL: url).data.matches, [edited])
    }

    @MainActor
    func testPhoneCanCompleteScheduledMatchWhileChangingDateAndSettingOrClearingTime() throws {
        for hasStartTime in [true, false] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
            defer { try? FileManager.default.removeItem(at: url) }
            let phone = TennisStore(storeURL: url)
            var player = PlayerProfile(); player.name = "Alex"
            XCTAssertTrue(phone.completeOnboarding(player: player, settings: AppSettings()))
            var original = match(); original.playerID = player.id; original.hasStartTime = !hasStartTime
            phone.applyWatchCommand(.upsertMatch(original))
            var draft = original; draft.status = .completed; draft.matchPosition = .final
            draft.date = now.addingTimeInterval(3600); draft.hasStartTime = hasStartTime
            draft.result = .loss; draft.setScores = "4-6"
            phone.upsertMatch(draft, original: original)
            let saved = try XCTUnwrap(phone.data.matches.first)
            var expected = draft; expected.revision += 1; expected.modifiedAt = saved.modifiedAt
            XCTAssertEqual(saved, expected)
            XCTAssertEqual(TennisStore(storeURL: url).data.matches, [try wire(expected)])
        }
    }

    func testFractionalScheduleBaselineAllowsExplicitEditAfterWireRoundTrip() throws {
        var original = match(); original.date = now.addingTimeInterval(0.875)
        let current = try wire(original)
        XCTAssertEqual(original.date.timeIntervalSince(current.date), 0.875, accuracy: 0.000001)
        var draft = original; draft.date = original.date.addingTimeInterval(3600); draft.hasStartTime = true
        let saved = TennisWatchRecordEdits.match(draft, current: current, original: original, now: now)
        var expected = draft; expected.revision += 1
        XCTAssertEqual(saved, expected)
        XCTAssertEqual(try wire(saved).date, now.addingTimeInterval(3600))
    }

    func testUnchangedFractionalScheduleKeepsCurrentStoredDate() throws {
        var original = match(); original.date = now.addingTimeInterval(0.875)
        let current = try wire(original)
        var draft = original; draft.notes = "Round-trip note"; draft.matchPosition = .semiFinal
        let saved = TennisWatchRecordEdits.match(draft, current: current, original: original, now: now)
        var expected = current; expected.notes = draft.notes; expected.matchPosition = .semiFinal; expected.revision += 1
        XCTAssertEqual(saved, expected)
        XCTAssertEqual(saved.date, current.date)
    }

    func testConcurrentWholeSecondScheduleChangeIsNotMistakenForRounding() throws {
        var original = match(); original.date = now.addingTimeInterval(0.875)
        var current = try wire(original); current.date = now.addingTimeInterval(1); current.revision += 1
        var draft = original; draft.date = now.addingTimeInterval(3600); draft.hasStartTime = true
        let saved = TennisWatchRecordEdits.match(draft, current: current, original: original, now: now)
        var expected = current; expected.revision += 1
        XCTAssertEqual(saved, expected)
    }
}
