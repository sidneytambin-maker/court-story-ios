import XCTest
@testable import TennisTracker

final class CourtIntegrationRouteTests: XCTestCase {
    func testResultReminderPreservesOfficialNonTennisScoreAndCurrentMetadata() throws {
        var current = MatchRecord(playerID: UUID())
        current.status = .scheduled; current.court.sport = CourtSportSelection(sport: .badminton)
        current.configureNewCourtMatch()
        var draft = TennisNotificationResult.draft(current)
        var score = draft.makeCourtScore()
        XCTAssertNil(score.recordResult([CourtScoreRound(points: [21, 15]), CourtScoreRound(points: [21, 18])]))
        draft.applyCourtScore(score)
        current.notes = "Keep this newer note"; current.trainingSessionID = UUID()
        let saved = try XCTUnwrap(TennisNotificationResult.applying(draft, to: current))
        XCTAssertEqual(saved.court.score, score)
        XCTAssertEqual(saved.court.rules, score.rules)
        XCTAssertEqual(saved.notes, current.notes)
        XCTAssertEqual(saved.trainingSessionID, current.trainingSessionID)
        XCTAssertEqual(saved.result, .win)
        current.court.sport = .tennis
        XCTAssertNil(TennisNotificationResult.applying(draft, to: current))
    }

    func testResultReminderRejectsUnfinishedLiveDraftAndKeepsStoppedRecordedOutcome() throws {
        var current = MatchRecord(playerID: UUID())
        current.status = .scheduled; current.court.sport = CourtSportSelection(sport: .tableTennis)
        current.configureNewCourtMatch()
        var draft = TennisNotificationResult.draft(current)
        var score = draft.makeCourtScore(); score.awardRally(to: 0); draft.applyCourtScore(score)
        XCTAssertNil(TennisNotificationResult.applying(draft, to: current))
        score.stopWithoutWinner(); draft.applyCourtScore(score)
        let saved = try XCTUnwrap(TennisNotificationResult.applying(draft, to: current))
        XCTAssertTrue(saved.stoppedWithoutWinner)
        XCTAssertEqual(saved.setScores, "1-0 unfinished")
    }

    func testBasicModeSchedulesResultsButNotAdvancedReflectionAndRetainsNotes() {
        let now = Date()
        var data = CourtDemoLibrary.make(role: .player, mode: .basic, now: now)
        var training = data.trainingSessions[0]
        training.date = now.addingTimeInterval(86400); training.actualStart = nil; training.actualFinish = nil
        training.notes = ""; training.sessionOutcome = ""
        data.trainingSessions = [training]
        data.settings.postSessionRemindersEnabled = true
        XCTAssertFalse(TennisNotificationPlanner.plannedRequests(data: data, now: now).contains { $0.identifier.hasPrefix("training-reflection-") })
        data.settings.trackingMode = .standard
        XCTAssertTrue(TennisNotificationPlanner.plannedRequests(data: data, now: now).contains { $0.identifier.hasPrefix("training-reflection-") })
    }

    func testComplicationsFilterBothSportAndAthleteAndSpeakActualLiveNumericScore() {
        let now = Date()
        var data = CourtDemoLibrary.make(role: .player, now: now)
        let playerID = data.players[0].id
        data.players[0].court.selectedSportID = CourtSport.badminton.rawValue
        data.matches = []; data.trainingSessions = []; data.tournaments = []
        var otherSport = MatchRecord(playerID: playerID)
        otherSport.date = now.addingTimeInterval(-300); otherSport.actualFinish = now.addingTimeInterval(-60)
        otherSport.status = .completed; otherSport.result = .win; data.matches.append(otherSport)
        var active = otherSport; active.id = UUID(); active.status = .inProgress; active.actualFinish = nil
        active.court.sport = CourtSportSelection(sport: .badminton); active.configureNewCourtMatch()
        var score = active.makeCourtScore(); score.awardRally(to: 0); score.awardRally(to: 1); score.awardRally(to: 0)
        active.applyCourtScore(score); data.matches.append(active)
        let snapshot = TennisWatchSnapshot(data: data, now: now)
        let live = TennisGlance.make(kind: .current, snapshot: snapshot, now: now)
        XCTAssertEqual(live.detail, "2-1")
        XCTAssertTrue(live.accessibilitySummary.contains("Badminton"))
        XCTAssertFalse(live.accessibilitySummary.contains("score not recorded"))
        XCTAssertTrue(TennisGlance.make(kind: .week, snapshot: snapshot, now: now).accessibilitySummary.contains("0 completed matches"))
        XCTAssertEqual(snapshot.achievements.first { $0.id == "match.1" }?.progress, 0)
    }

    func testOfflinePowerRecordIsPreservedAfterPhoneSwitchesToBasicButCannotBeCreatedInBasic() throws {
        var data = CourtDemoLibrary.make()
        var drill = try XCTUnwrap(data.court.drills.first)
        drill.id = UUID(); drill.revision += 1
        data.settings.trackingMode = .basic
        let mutation = CourtWatchMutation.drill(drill)
        XCTAssertFalse(mutation.apply(to: &data))
        XCTAssertTrue(mutation.apply(to: &data, importingSavedRecord: true))
        XCTAssertTrue(data.court.drills.contains { $0.id == drill.id })
        data.court.deletedIDs.insert(drill.id)
        XCTAssertFalse(mutation.apply(to: &data, importingSavedRecord: true))
    }
}
