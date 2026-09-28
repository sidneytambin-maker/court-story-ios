import XCTest
@testable import TennisTracker

final class TennisRecordedMatchRegressionTests: XCTestCase {
    private func match(kind: MatchKind = .singles, format: MatchFormat = .oneSet) -> MatchRecord {
        var result = MatchRecord(playerID: UUID())
        result.playerName = "Alex"; result.opponentName = "Sam"
        result.matchType = kind; result.matchFormat = format
        if kind == .doubles { result.partnerName = "Chris"; result.opponent2Name = "Jo" }
        return result
    }

    func testSixAllTiebreakDecidesSinglesAndDoublesWinOrLoss() {
        for kind in MatchKind.allCases {
            for won in [true, false] {
                var record = match(kind: kind)
                let set = TennisRecordedSet(yourGames: 6, opponentGames: 6, hasTiebreak: true,
                    yourTiebreak: won ? 9 : 7, opponentTiebreak: won ? 7 : 9)
                TennisRecordedScore.apply([set], to: &record)
                XCTAssertEqual(record.result, won ? .win : .loss)
                XCTAssertEqual(record.setScores, won ? "7-6" : "6-7")
                XCTAssertEqual(record.yourSetsWon, won ? 1 : 0)
                XCTAssertEqual(record.opponentSetsWon, won ? 0 : 1)
                XCTAssertNil(TennisManualMatchEntry.validationMessage(for: record))
                let summary = TennisSummaryFormatter.match(record)
                XCTAssertTrue(summary.contains("tie-break: your"))
                XCTAssertTrue(summary.contains(won ? "9 points, opponent 7 points" : "7 points, opponent 9 points"))
            }
        }
    }

    func testExplicitlyTiedTiebreakAndNoTiebreakAreRecordedDraws() {
        for tie in [true, false] {
            var record = match()
            TennisRecordedScore.apply([TennisRecordedSet(yourGames: 6, opponentGames: 6, hasTiebreak: tie,
                yourTiebreak: tie ? 7 : nil, opponentTiebreak: tie ? 7 : nil)], to: &record)
            XCTAssertEqual(record.result, .draw)
            XCTAssertEqual(record.setScores, "6-6")
            XCTAssertNil(TennisManualMatchEntry.validationMessage(for: record))
        }
    }

    func testRetirementIsNotOverwrittenWhenSetScoresAreEntered() {
        var record = match(); record.result = .retired
        TennisRecordedScore.apply([TennisRecordedSet(yourGames: 2, opponentGames: 3)], to: &record)
        XCTAssertEqual(record.result, .retired)
        XCTAssertEqual(record.setScores, "2-3")
    }

    @MainActor
    func testPhoneStoreLinksPersistWithoutCreatingDuplicateMatches() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TennisStore(storeURL: url)
        var player = PlayerProfile(); player.name = "Alex"; store.upsertPlayer(player)
        let training = TrainingSession(playerID: player.id); store.upsertTraining(training)
        var record = match(); record.playerID = player.id; store.upsertMatch(record)
        store.updateTrainingLinks(training, original: [], selected: [record.id])
        XCTAssertEqual(store.data.matches.count, 1)
        XCTAssertEqual(store.data.matches.first?.trainingSessionID, training.id)
        let reloaded = TennisStore(storeURL: url)
        XCTAssertEqual(reloaded.data.matches.first?.id, record.id)
        XCTAssertEqual(reloaded.data.matches.first?.trainingSessionID, training.id)
        reloaded.deleteTraining(training)
        XCTAssertEqual(reloaded.data.matches.count, 1)
        XCTAssertNil(reloaded.data.matches.first?.trainingSessionID)
    }

    func testMissingTiebreakPointsCannotBeSilentlySavedAsDraw() {
        var record = match()
        for yours in [Int?.none, Optional(7)] {
            TennisRecordedScore.apply([TennisRecordedSet(yourGames: 6, opponentGames: 6,
                hasTiebreak: true, yourTiebreak: yours)], to: &record)
            XCTAssertNotNil(TennisManualMatchEntry.validationMessage(for: record))
        }
    }

    func testConflictingGamesAndTiebreakRequireCorrection() {
        var record = match()
        TennisRecordedScore.apply([TennisRecordedSet(yourGames: 7, opponentGames: 6,
            hasTiebreak: true, yourTiebreak: 5, opponentTiebreak: 7)], to: &record)
        XCTAssertNotNil(TennisManualMatchEntry.validationMessage(for: record))
    }

    func testOneSetAndDecidingThirdSetUseTiebreakWinners() {
        let win = TennisRecordedSet(yourGames: 6, opponentGames: 6, hasTiebreak: true, yourTiebreak: 7, opponentTiebreak: 5)
        let loss = TennisRecordedSet(yourGames: 4, opponentGames: 6)
        XCTAssertEqual(TennisRecordedScore.requiredRows(format: .oneSet, sets: [win, loss]), 1)
        XCTAssertEqual(TennisRecordedScore.requiredRows(format: .bestOfThree, sets: [win, loss]), 3)
        XCTAssertEqual(TennisRecordedScore.requiredRows(format: .bestOfThree, sets: [win, win, loss]), 2)
        var record = match(format: .bestOfThree)
        TennisRecordedScore.apply([win, loss, win], to: &record)
        XCTAssertEqual(record.yourSetsWon, 2); XCTAssertEqual(record.opponentSetsWon, 1)
        XCTAssertEqual(record.result, .win)
        XCTAssertEqual(record.setsPlayed, 3)
    }

    func testBestOfFiveAndCustomScoresDoNotTruncateValidSets() {
        let win = TennisRecordedSet(yourGames: 6, opponentGames: 3)
        let loss = TennisRecordedSet(yourGames: 2, opponentGames: 6)
        for format in [MatchFormat.bestOfFive, .custom] {
            var record = match(format: format)
            TennisRecordedScore.apply([win, loss, win, loss, win], to: &record)
            XCTAssertEqual(record.recordedSets.count, 5)
            XCTAssertEqual(record.yourSetsWon, 3)
            XCTAssertNil(TennisManualMatchEntry.validationMessage(for: record))
        }
    }

    func testReadingLegacyScoresNeverModifiesTheRecord() {
        var record = match(format: .bestOfThree)
        record.setScores = "6\u{2013}4, 7-6 (9-7)"
        record.hadTiebreak = true; record.tiebreakScore = "Original notes"
        let original = record
        let sets = TennisRecordedScore.sets(from: record)
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets.last?.yourTiebreak, 9)
        XCTAssertEqual(record, original)
        record.setScores = "Retired while ahead"
        XCTAssertTrue(TennisRecordedScore.sets(from: record).isEmpty)
        XCTAssertEqual(record.setScores, "Retired while ahead")
    }

    func testStructuredScoreAndLinkSurviveEncodingAndOldRecordsDecode() throws {
        var record = match(); record.trainingSessionID = UUID()
        TennisRecordedScore.apply([TennisRecordedSet(yourGames: 6, opponentGames: 6,
            hasTiebreak: true, yourTiebreak: 10, opponentTiebreak: 8)], to: &record)
        let encoded = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(MatchRecord.self, from: encoded), record)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "recordedSets")
        let decoded = try JSONDecoder().decode(MatchRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(decoded.recordedSets.isEmpty)
        XCTAssertEqual(decoded.trainingSessionID, record.trainingSessionID)
        XCTAssertEqual(decoded.setScores, record.setScores)
    }

    func testWatchEditorPreservesIdentityTimingAndSavesLinkAndTiebreak() {
        var current = match()
        current.actualStart = Date(timeIntervalSince1970: 1000)
        current.actualFinish = Date(timeIntervalSince1970: 1800)
        var draft = current; draft.trainingSessionID = UUID()
        TennisRecordedScore.apply([TennisRecordedSet(yourGames: 6, opponentGames: 6,
            hasTiebreak: true, yourTiebreak: 7, opponentTiebreak: 9)], to: &draft)
        let edited = TennisWatchRecordEdits.match(draft, current: current)
        XCTAssertEqual(edited.trainingSessionID, draft.trainingSessionID)
        XCTAssertEqual(edited.recordedSets, draft.recordedSets)
        XCTAssertEqual(edited.tiebreakScore, draft.tiebreakScore)
        XCTAssertEqual(edited.hadTiebreak, true)
        XCTAssertEqual(edited.result, .loss)
        XCTAssertEqual(edited.id, current.id)
        XCTAssertEqual(edited.actualStart, current.actualStart)
        XCTAssertEqual(edited.actualFinish, current.actualFinish)
    }

    func testTrainingLinksOnlyApplyExplicitChangesAndKeepRecordIDs() {
        let record = match(), sessionID = UUID()
        let changes = TennisTrainingLinks.changes(sessionID: sessionID, playerID: record.playerID,
            matches: [record], original: [], selected: [record.id])
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.id, record.id)
        XCTAssertEqual(changes.first?.trainingSessionID, sessionID)
        let unlinked = TennisTrainingLinks.changes(sessionID: sessionID, playerID: record.playerID,
            matches: changes, original: [record.id], selected: [])
        XCTAssertNil(unlinked.first?.trainingSessionID)
        XCTAssertEqual(unlinked.first?.id, record.id)
        XCTAssertTrue(TennisTrainingLinks.changes(sessionID: sessionID, playerID: UUID(),
            matches: [record], original: [], selected: [record.id]).isEmpty)
    }

    func testUnchangedOrCancelledLinksDoNotOverwriteNewerRelationships() {
        var record = match(); record.trainingSessionID = UUID()
        let sessionID = UUID()
        XCTAssertTrue(TennisTrainingLinks.changes(sessionID: sessionID, playerID: record.playerID,
            matches: [record], original: [record.id], selected: [record.id]).isEmpty)
        XCTAssertTrue(TennisTrainingLinks.changes(sessionID: sessionID, playerID: record.playerID,
            matches: [record], original: [record.id], selected: []).isEmpty)
    }

    func testDeletingTrainingUnlinksButKeepsMatchesAndTombstonesTheSession() {
        var data = AppData()
        var record = match()
        let session = TrainingSession(playerID: record.playerID)
        record.trainingSessionID = session.id
        data.trainingSessions = [session]; data.matches = [record]
        data.delete(TennisRecordDeletion(id: session.id, kind: .training))
        XCTAssertTrue(data.trainingSessions.isEmpty)
        XCTAssertEqual(data.matches.map(\.id), [record.id])
        XCTAssertNil(data.matches[0].trainingSessionID)
        XCTAssertTrue(data.deletedRecordIDs.contains(session.id))
    }

    func testTrainingPracticeAndLinkedMatchOnlyCountOnce() {
        var record = match()
        var session = TrainingSession(playerID: record.playerID)
        session.date = Date(timeIntervalSince1970: 1000)
        session.practiceResult = TennisPracticeResult(result: .win)
        record.trainingSessionID = session.id
        let results = TennisCompletedMatch.collect(matches: [record], training: [session])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, record.id)
    }

    func testWeatherGroupsContainEveryChoiceExactlyOnceAndKeepLegacyValues() throws {
        let weather = TennisWeather.groups.flatMap(\.values)
        XCTAssertEqual(Set(weather), Set(TennisWeather.allCases))
        XCTAssertEqual(weather.count, Set(weather).count)
        XCTAssertGreaterThanOrEqual(weather.count, 25)
        XCTAssertTrue(weather.contains(.lightBreeze))
        XCTAssertTrue(weather.contains(.heavyRain))
        let old = try JSONDecoder().decode([TennisWeather].self, from: Data(#"["Sunny","Light showers","Rain","Windy"]"#.utf8))
        XCTAssertEqual(old, [.sunny, .lightRain, .rain, .windy])
        XCTAssertEqual(try JSONDecoder().decode([TennisWeather].self, from: JSONEncoder().encode(weather)), weather)
    }
    func testValidFocusIsNotRejectedJustBecauseItIsAlsoATrainingType() {
        let player = PlayerProfile()
        var session = TrainingSession(playerID: player.id)
        session.date = Date().addingTimeInterval(-7200)
        for focus in ["Serve and return", "Rally consistency"] {
            session.focus = focus
            let progress = TennisPlayerProgress.build(player: player, matches: [], training: [session])
            XCTAssertEqual(progress.focus.first?.focus, focus)
            XCTAssertEqual(progress.focus.first?.sessions, 1)
            XCTAssertTrue(progress.trainingNeedingFocus.isEmpty)
        }
    }

    func testMultipleFocusCountsEachSessionOncePerFocusWithoutInventingFocusTime() {
        let player = PlayerProfile()
        var session = TrainingSession(playerID: player.id)
        session.date = Date().addingTimeInterval(-7200)
        session.focus = "Serves"; session.additionalFocus = ["Returns", "Serves"]
        let progress = TennisPlayerProgress.build(player: player, matches: [], training: [session])
        XCTAssertEqual(progress.focus.count, 2)
        XCTAssertTrue(progress.focus.allSatisfy { $0.sessions == 1 })
        XCTAssertEqual(progress.trainingTypes.first?.sessions, 1)
        XCTAssertEqual(session.focusSummary, "Serves and Returns")
        XCTAssertTrue(progress.trainingNeedingFocus.isEmpty)
    }

    func testFocusRepairTargetsUseTheSamePlayerAndThirtyDayWindow() {
        let player = PlayerProfile()
        var recent = TrainingSession(playerID: player.id)
        recent.date = Date().addingTimeInterval(-7200)
        var older = recent; older.id = UUID(); older.date = Date().addingTimeInterval(-40 * 86400)
        var future = recent; future.id = UUID(); future.date = Date().addingTimeInterval(86400)
        var focused = recent; focused.id = UUID(); focused.focus = "Serve and return"
        var other = recent; other.id = UUID(); other.playerID = UUID()
        let progress = TennisPlayerProgress.build(player: player, matches: [], training: [recent, older, future, focused, other])
        XCTAssertEqual(progress.trainingNeedingFocus, [recent.id])
    }

    func testMultipleFocusSurvivesWatchEditingAndCoding() throws {
        var current = TrainingSession(playerID: UUID())
        current.workout = TennisWorkoutResult(durationSeconds: 159)
        var draft = current
        draft.focus = "Serve and return"; draft.additionalFocus = ["Footwork and court movement"]
        let edited = TennisWatchRecordEdits.training(draft, current: current)
        XCTAssertEqual(edited.additionalFocus, draft.additionalFocus)
        XCTAssertEqual(edited.workout, current.workout)
        XCTAssertEqual(try JSONDecoder().decode(TrainingSession.self, from: JSONEncoder().encode(edited)), edited)
    }
}
