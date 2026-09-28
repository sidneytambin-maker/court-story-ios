import XCTest
@testable import TennisTracker

final class TennisWatchActivityPolishTests: XCTestCase {
    func testTrackedDurationKeepsSecondsWithoutRoundingToMinutes() {
        XCTAssertEqual(TennisDurationFormatter.text(seconds: 159.8), "2 minutes 39 seconds")
        XCTAssertEqual(TennisDurationFormatter.text(seconds: 3759), "1 hour 2 minutes 39 seconds")
        XCTAssertEqual(TennisDurationFormatter.text(seconds: 1), "1 second")
        XCTAssertEqual(TennisDurationFormatter.text(seconds: -10), "0 seconds")
        XCTAssertEqual(TennisDurationFormatter.text(seconds: .nan), "0 seconds")
        XCTAssertEqual(TennisDurationFormatter.compact(seconds: 159), "2:39")
    }

    func testTrainingSummaryUsesPreciseHealthOrTrackedDuration() {
        var training = TrainingSession(playerID: UUID())
        training.actualStart = Date(timeIntervalSince1970: 1000)
        training.actualFinish = Date(timeIntervalSince1970: 1159)
        training.durationMinutes = 3
        XCTAssertTrue(TennisSummaryFormatter.training(training).contains("2 minutes 39 seconds"))
        training.workout = TennisWorkoutResult(durationSeconds: 151)
        XCTAssertEqual(TennisDurationFormatter.training(training), "2 minutes 31 seconds")
        training.actualFinish = nil
        XCTAssertEqual(TennisDurationFormatter.training(training, now: Date(timeIntervalSince1970: 1011)), "11 seconds")
    }

    func testManualDurationDoesNotInventSecondPrecision() {
        var training = TrainingSession(playerID: UUID())
        training.durationMinutes = 65
        XCTAssertEqual(TennisDurationFormatter.training(training), "1 hour 5 minutes")
    }

    func testDashboardSumsActualSecondsAndExcludesFutureAndRunningTraining() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var training = TrainingSession(playerID: UUID())
        training.date = now.addingTimeInterval(-3600)
        training.actualStart = training.date
        training.actualFinish = training.date.addingTimeInterval(159)
        training.durationMinutes = 3
        training.workout = TennisWorkoutResult(durationSeconds: 159)
        var second = training; second.id = UUID()
        var future = TrainingSession(playerID: training.playerID)
        future.date = now.addingTimeInterval(3600)
        var running = training; running.id = UUID(); running.actualFinish = nil
        let stats = TennisStatistics.build(matches: [], training: [training, second, future, running], tournaments: [], today: now)
        XCTAssertEqual(stats.trainingCountLast30Days, 2)
        XCTAssertEqual(stats.trainingSecondsLast30Days, 318)
        XCTAssertEqual(stats.trainingMinutesLast30Days, 5)
        XCTAssertEqual(TennisDurationFormatter.text(seconds: stats.trainingSecondsLast30Days), "5 minutes 18 seconds")
    }

    func testInvalidWorkoutDurationFallsBackToActualTimingForTotals() {
        var training = TrainingSession(playerID: UUID())
        training.actualStart = Date(timeIntervalSince1970: 1000)
        training.actualFinish = Date(timeIntervalSince1970: 1159)
        training.workout = TennisWorkoutResult(durationSeconds: .nan)
        XCTAssertEqual(TennisDurationFormatter.trainingSeconds(training), 159)
        training.actualStart = nil; training.actualFinish = nil
        training.durationMinutes = 65
        XCTAssertEqual(TennisDurationFormatter.trainingSeconds(training), 3900)
    }

    func testFitnessSummaryContainsOnlyAvailableActualMetrics() {
        let result = TennisWorkoutResult(durationSeconds: 159, averageHeartRate: 72, activeEnergyKcal: 4,
            peakHeartRate: 90, distanceMeters: 123, stepCount: 201)
        XCTAssertEqual(result.fitnessSummary, "Average heart rate 72 beats per minute. Peak heart rate 90 beats per minute. Active energy 4 calories. Distance 123 metres. 201 steps.")
        XCTAssertEqual(TennisWorkoutResult(durationSeconds: 3).fitnessSummary, "Distance unavailable. Steps unavailable.")
        XCTAssertFalse(TennisWorkoutResult(durationSeconds: 3, activeEnergyKcal: 0).fitnessSummary.contains("0 steps"))
    }

    func testOldWorkoutRecordsDecodeWithoutNewMetricFields() throws {
        let result = try JSONDecoder().decode(TennisWorkoutResult.self, from: Data("{\"durationSeconds\":159,\"averageHeartRate\":72}".utf8))
        XCTAssertNil(result.distanceMeters)
        XCTAssertNil(result.stepCount)
        XCTAssertNil(result.peakHeartRate)
        XCTAssertEqual(result.durationSeconds, 159)
    }

    func testTrainingEditPreservesWorkoutSavedWhileEditorWasOpen() {
        var current = TrainingSession(playerID: UUID())
        var draft = current
        draft.notes = "Useful practice"
        draft.trainingType = .doublesPractice
        draft.needsDetails = false
        current.actualStart = Date(timeIntervalSince1970: 1000)
        current.actualFinish = Date(timeIntervalSince1970: 1159)
        current.workout = TennisWorkoutResult(workoutID: UUID(), durationSeconds: 159, averageHeartRate: 72)
        current.revision = 8
        let saved = TennisWatchRecordEdits.training(draft, current: current)
        XCTAssertEqual(saved.id, current.id)
        XCTAssertEqual(saved.workout, current.workout)
        XCTAssertEqual(saved.actualFinish, current.actualFinish)
        XCTAssertGreaterThan(saved.revision, current.revision)
        XCTAssertEqual(saved.notes, "Useful practice")
        XCTAssertEqual(saved.trainingType, .doublesPractice)
        XCTAssertFalse(saved.needsDetails)
    }

    func testMatchEditPreservesLiveScoreAndTrackedTimes() {
        var current = MatchRecord(playerID: UUID())
        var draft = current
        draft.opponentName = "Sam"
        current.status = .inProgress
        current.actualStart = Date()
        current.liveScore = TennisScoreState().snapshot
        current.revision = 4
        let saved = TennisWatchRecordEdits.match(draft, current: current)
        XCTAssertEqual(saved.liveScore, current.liveScore)
        XCTAssertEqual(saved.status, .inProgress)
        XCTAssertEqual(saved.actualStart, current.actualStart)
        XCTAssertEqual(saved.opponentName, "Sam")
    }

    func testTournamentEditCannotUndoConcurrentFinish() {
        var current = TournamentRecord(playerID: UUID())
        var draft = current
        draft.name = "Local tennis"
        draft.endDate = draft.date.addingTimeInterval(-86400)
        current.finalResult = .completed
        current.actualFinish = Date()
        let saved = TennisWatchRecordEdits.tournament(draft, current: current)
        XCTAssertEqual(saved.actualFinish, current.actualFinish)
        XCTAssertEqual(saved.finalResult, .completed)
        XCTAssertGreaterThanOrEqual(saved.endDate, saved.date)
    }

    func testTrackedMatchAndTournamentTimesSurviveCoding() throws {
        let start = Date(timeIntervalSince1970: 1000)
        var match = MatchRecord(playerID: UUID())
        match.actualStart = start; match.actualFinish = start.addingTimeInterval(159)
        let restoredMatch = try JSONDecoder.tennisTracker.decode(MatchRecord.self, from: JSONEncoder.tennisTracker.encode(match))
        XCTAssertEqual(restoredMatch.actualFinish, match.actualFinish)
        XCTAssertTrue(TennisSummaryFormatter.match(restoredMatch).contains("2 minutes 39 seconds"))
        var tournament = TournamentRecord(playerID: UUID())
        tournament.actualStart = start; tournament.actualFinish = start.addingTimeInterval(159)
        let restoredTournament = try JSONDecoder.tennisTracker.decode(TournamentRecord.self, from: JSONEncoder.tennisTracker.encode(tournament))
        XCTAssertEqual(restoredTournament.actualStart, start)
        XCTAssertTrue(TennisSummaryFormatter.tournament(restoredTournament).contains("2 minutes 39 seconds"))
    }

    func testFiveComplicationsHaveStableDistinctIdentities() {
        XCTAssertEqual(Set(TennisGlanceKind.allCases.map(\.widgetKind)).count, 5)
        XCTAssertEqual(TennisGlanceKind.current.widgetKind, "TennisTrackerComplication")
        XCTAssertEqual(Set(TennisGlanceKind.allCases.map(\.name)).count, 5)
    }

    func testNextEventIsIndependentOfCurrentTraining() {
        let now = Date()
        let player = UUID()
        var snapshot = TennisWatchSnapshot()
        snapshot.selectedPlayerID = player
        var current = TennisWatchActivityFactory.trainingSession(playerID: player, startDate: now.addingTimeInterval(-159))
        current.needsDetails = false
        var next = TrainingSession(playerID: player)
        next.date = now.addingTimeInterval(3600)
        snapshot.trainingSessions = [current, next]
        XCTAssertEqual(TennisGlance.make(kind: .current, snapshot: snapshot, now: now).destination, .live)
        XCTAssertEqual(TennisGlance.make(kind: .next, snapshot: snapshot, now: now).destination, .today)
    }

    func testWeeklyAndLatestComplicationsUsePreciseSavedRecords() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 12))!
        let player = UUID()
        var snapshot = TennisWatchSnapshot()
        snapshot.selectedPlayerID = player
        var training = TrainingSession(playerID: player)
        training.date = now.addingTimeInterval(-3600)
        training.actualStart = training.date
        training.actualFinish = training.date.addingTimeInterval(159)
        training.workout = TennisWorkoutResult(durationSeconds: 159, averageHeartRate: 72)
        var other = training; other.id = UUID(); other.playerID = UUID()
        snapshot.trainingSessions = [training, other]
        let week = TennisGlance.make(kind: .week, snapshot: snapshot, now: now)
        XCTAssertTrue(week.accessibilitySummary.contains("1 completed training session, 2 minutes 39 seconds"))
        let latest = TennisGlance.make(kind: .latest, snapshot: snapshot, now: now)
        XCTAssertTrue(latest.accessibilitySummary.contains("72 beats per minute"))
        XCTAssertEqual(latest.circularDetail, "2:39")
        XCTAssertEqual(latest.destination, .recent)
    }
}
