import XCTest
@testable import TennisTracker

final class TennisTrainingFocusTests: XCTestCase {
    func testNewSessionsNeverInferFocusFromType() {
        XCTAssertTrue(TrainingSession(playerID: UUID()).focus.isEmpty)
        XCTAssertGreaterThanOrEqual(TennisTrainingFocus.allCases.count, 10)
        XCTAssertEqual(Set(TennisTrainingFocus.allCases.map(\.rawValue)).count, TennisTrainingFocus.allCases.count)
        for type in TrainingType.allCases {
            XCTAssertEqual(TennisWatchActivityFactory.trainingSession(playerID: UUID(), type: type).focus, "")
        }
    }

    func testLegacyFocusAndMissingFocusDecodeWithoutGuessing() throws {
        let id = UUID()
        let missing = Data("{\"playerID\":\"\(id)\"}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(TrainingSession.self, from: missing).focus, "")
        var session = TrainingSession(playerID: id)
        session.focus = "Backhand return against wide serves"
        let decoded = try JSONDecoder().decode(TrainingSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(decoded, session)
        XCTAssertEqual(decoded.focus, session.focus)
    }

    func testChosenFocusSurvivesWatchEditFinishAndSyncWithoutChangingTypeOrID() throws {
        var current = TennisWatchActivityFactory.trainingSession(playerID: UUID(), type: .doublesPractice,
            startDate: Date(timeIntervalSince1970: 1000))
        var draft = current
        draft.focus = TennisTrainingFocus.serveAndReturn.rawValue
        current = TennisWatchActivityFactory.finishTrainingSession(current, finishDate: Date(timeIntervalSince1970: 1159))
        current.workout = TennisWorkoutResult(durationSeconds: 159, averageHeartRate: 72)
        let edited = TennisWatchRecordEdits.training(draft, current: current)
        XCTAssertEqual(edited.id, current.id)
        XCTAssertEqual(edited.trainingType, .doublesPractice)
        XCTAssertEqual(edited.actualFinish, current.actualFinish)
        XCTAssertEqual(edited.workout, current.workout)
        XCTAssertEqual(edited.focus, "Serve and return")
        let decoded = try JSONDecoder().decode(TrainingSession.self, from: JSONEncoder().encode(edited))
        XCTAssertEqual(decoded.focus, edited.focus)
        XCTAssertTrue(TennisSummaryFormatter.training(decoded, style: .short).contains("Focus: Serve and return"))
        XCTAssertTrue(TennisSummaryFormatter.training(decoded, style: .detailed).contains("2 minutes 39 seconds"))
    }

    func testProgressSeparatesSinglesDoublesPracticeAndScheduledRecords() {
        let player = PlayerProfile()
        let now = Date()
        func match(_ kind: MatchKind, _ result: MatchResult, status: MatchStatus = .completed) -> MatchRecord {
            var record = MatchRecord(playerID: player.id)
            record.matchType = kind; record.result = result; record.status = status
            return record
        }
        var practice = match(.singles, .loss)
        practice.trainingSessionID = UUID()
        var otherPlayer = match(.singles, .win)
        otherPlayer.playerID = UUID()
        let matches = [match(.singles, .win), match(.singles, .draw), match(.doubles, .loss), match(.doubles, .retired),
                       match(.singles, .win, status: .scheduled), match(.doubles, .win, status: .inProgress), practice, otherPlayer]
        var training = TrainingSession(playerID: player.id)
        training.date = now.addingTimeInterval(-7200)
        let noMatchTraining = training
        training.id = UUID()
        training.practiceResult = TennisPracticeResult(kind: .doubles, result: .draw)
        let progress = TennisPlayerProgress.build(player: player, matches: matches, training: [training, noMatchTraining], now: now)
        XCTAssertEqual(progress.singles.count, 3)
        XCTAssertEqual(progress.singles.wins, 1)
        XCTAssertEqual(progress.singles.draws, 1)
        XCTAssertEqual(progress.doubles.losses, 1)
        XCTAssertEqual(progress.doubles.retired, 1)
        XCTAssertEqual(progress.singlesPractice.count, 1)
        XCTAssertEqual(progress.doublesPractice.count, 1)
        XCTAssertEqual(progress.doublesPractice.draws, 1)
        let stats = TennisStatistics.build(matches: matches.filter { $0.playerID == player.id }, training: [], tournaments: [])
        XCTAssertEqual(stats.matchCount, 5)
        XCTAssertEqual(stats.winCount, 1)
        XCTAssertEqual(stats.drawCount, 1)
    }

    func testPracticeSummaryDoesNotDuplicateLinkedMatch() {
        let player = PlayerProfile()
        let now = Date()
        var training = TrainingSession(playerID: player.id)
        training.date = now.addingTimeInterval(-7200)
        training.practiceResult = TennisPracticeResult(kind: .singles, result: .win)
        var match = MatchRecord(playerID: player.id)
        match.trainingSessionID = training.id
        let progress = TennisPlayerProgress.build(player: player, matches: [match], training: [training], now: now)
        XCTAssertEqual(progress.singles.count, 1)
        XCTAssertEqual(progress.singlesPractice.count, 1)
    }

    func testFocusDashboardExcludesFutureRunningOldAndOtherPlayerTraining() {
        let player = PlayerProfile()
        let now = Date()
        var completed = TrainingSession(playerID: player.id)
        completed.trainingType = .doublesPractice
        completed.date = now.addingTimeInterval(-3600)
        completed.actualStart = completed.date
        completed.actualFinish = completed.date.addingTimeInterval(159)
        completed.focus = TennisTrainingFocus.serves.rawValue
        var noFocus = completed; noFocus.id = UUID(); noFocus.focus = ""
        var future = TrainingSession(playerID: player.id); future.date = now.addingTimeInterval(3600)
        var running = completed; running.id = UUID(); running.actualFinish = nil
        var other = completed; other.playerID = UUID()
        var old = completed; old.date = now.addingTimeInterval(-60 * 86400); old.actualStart = old.date; old.actualFinish = old.date.addingTimeInterval(159)
        let progress = TennisPlayerProgress.build(player: player, matches: [], training: [completed, noFocus, future, running, other, old], now: now)
        XCTAssertEqual(progress.focus.count, 2)
        XCTAssertEqual(progress.focus.first { $0.focus == "Serves" }?.seconds, 159)
        XCTAssertEqual(progress.focus.first { $0.focus == "No focus selected" }?.sessions, 1)
        XCTAssertEqual(progress.trainingTypes.first?.focus, "Doubles practice")
        XCTAssertEqual(progress.trainingTypes.first?.sessions, 2)
    }

    func testSuggestionsUseOnlyThePlayersExplicitGoalsAndCompletedMatchReview() {
        var player = PlayerProfile()
        XCTAssertTrue(TennisPlayerProgress.build(player: player, matches: [], training: []).suggestions.isEmpty)
        player.primaryGoal = "Improve second serve"
        player.coachingFocus = "Return depth"
        var match = MatchRecord(playerID: player.id)
        match.nextPracticeFocus = "Cross-court backhand"
        var scheduled = match; scheduled.id = UUID(); scheduled.status = .scheduled; scheduled.nextPracticeFocus = "Not a completed review"
        var other = match; other.playerID = UUID(); other.nextPracticeFocus = "Someone else's goal"
        let progress = TennisPlayerProgress.build(player: player, matches: [match, scheduled, other], training: [])
        XCTAssertEqual(progress.suggestions.map(\.detail), ["Improve second serve", "Return depth", "Cross-court backhand"])
    }

    func testScheduledSessionDoesNotCountAsTrainingBeforeItsEnd() {
        let now = Date()
        var session = TrainingSession(playerID: UUID())
        session.date = now.addingTimeInterval(-60)
        session.durationMinutes = 60
        XCTAssertFalse(session.isRecordedTraining(at: now))
        XCTAssertTrue(session.isRecordedTraining(at: session.expectedEndDate))
    }
}
