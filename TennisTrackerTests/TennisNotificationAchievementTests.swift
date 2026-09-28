import XCTest
import AVFoundation
@testable import TennisTracker

final class TennisNotificationAchievementTests: XCTestCase {
    func testAllActivityRoutesRoundTripWithExactRecordAndPurpose() throws {
        for kind in [TennisActivityRoute.Kind.training, .match, .tournament] {
            let id = UUID()
            let route = TennisActivityRoute(kind: kind, recordID: id)
            XCTAssertEqual(TennisActivityRoute(url: route.url), route)
        }
        for route in [TennisActivityRoute(kind: .training, recordID: UUID(), action: .reflection),
                      TennisActivityRoute(kind: .match, recordID: UUID(), action: .result),
                      TennisActivityRoute(kind: .match, recordID: UUID(), action: .live),
                      TennisActivityRoute(kind: .weekly, weekStart: Date(timeIntervalSince1970: 1_800_000_000)),
                      TennisActivityRoute(kind: .achievements)] {
            XCTAssertEqual(TennisActivityRoute(url: route.url), route)
        }
    }

    func testMalformedRoutesCannotOpenAnUnrelatedSession() {
        for text in ["https://training/\(UUID())", "tennistracker://training/not-a-record", "tennistracker://training",
                     "tennistracker://match/\(UUID())/reflection", "tennistracker://training/\(UUID())/result",
                     "tennistracker://weekly?start=nan", "tennistracker://weekly?start=-1"] {
            XCTAssertNil(TennisActivityRoute(url: URL(string: text)!), text)
        }
    }

    func testAlreadyDeliveredLegacyRemindersRetainTheirEditingPurpose() throws {
        let id = UUID()
        let training = try XCTUnwrap(TennisActivityRoute.notificationURL(userInfo: ["url": "tennistracker://training/\(id)"], identifier: "training-reflection-\(id)"))
        XCTAssertEqual(TennisActivityRoute(url: training)?.recordID, id)
        XCTAssertEqual(TennisActivityRoute(url: training)?.action, .reflection)
        let match = try XCTUnwrap(TennisActivityRoute.notificationURL(userInfo: ["url": "tennistracker://match/\(id)"], identifier: "match-result-\(id)"))
        XCTAssertEqual(TennisActivityRoute(url: match)?.action, .result)
        XCTAssertNil(TennisActivityRoute.notificationURL(userInfo: [:], identifier: "training-reflection"))
    }

    @MainActor func testColdLaunchInboxIsConsumedOnceAndWarmRouterOpensExactDestination() throws {
        let suite = "notification-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let route = TennisActivityRoute(kind: .training, recordID: UUID(), action: .reflection)
        TennisNotificationInbox.enqueue(route.url, defaults: defaults)
        let url = try XCTUnwrap(TennisNotificationInbox.take(defaults: defaults))
        XCTAssertEqual(url, route.url)
        XCTAssertNil(TennisNotificationInbox.take(defaults: defaults))
        let router = AppRouter(); router.open(url)
        XCTAssertEqual(router.selectedTab, "training")
        XCTAssertEqual(router.activityRoute, route)
        let next = TennisActivityRoute(kind: .match, recordID: UUID(), action: .result)
        router.open(next.url)
        XCTAssertEqual(router.selectedTab, "matches"); XCTAssertEqual(router.activityRoute, next)
    }

    func testFollowUpsAreScheduledAheadWithoutNeedingAnEndTimeSave() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var data = AppData(); let playerID = UUID()
        data.settings.postSessionRemindersEnabled = true; data.settings.matchResultRemindersEnabled = true
        var session = TrainingSession(playerID: playerID); session.date = now.addingTimeInterval(86400)
        var match = MatchRecord(playerID: playerID); match.status = .scheduled
        match.date = session.date; match.hasStartTime = true
        data.trainingSessions = [session]; data.matches = [match]
        let requests = TennisNotificationPlanner.plannedRequests(data: data, now: now)
        XCTAssertEqual(requests.count, 2)
        let reflection = try XCTUnwrap(requests.first { $0.identifier.hasPrefix("training-reflection-") })
        XCTAssertEqual(TennisActivityRoute(url: reflection.deepLink)?.action, .reflection)
        XCTAssertEqual(TennisActivityRoute(url: reflection.deepLink)?.recordID, session.id)
        XCTAssertGreaterThan(reflection.fireDate, session.expectedEndDate)
        XCTAssertEqual(TennisActivityRoute(url: requests.first { $0.identifier.hasPrefix("match-result-") }!.deepLink)?.action, .result)
    }

    func testReflectionUsesActualFinishAndDoesNotNagAfterNotesOrDuringTracking() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var data = AppData(); data.settings.postSessionRemindersEnabled = true
        var session = TrainingSession(playerID: UUID())
        session.date = now.addingTimeInterval(-7200); session.actualStart = session.date
        session.actualFinish = now.addingTimeInterval(-60)
        data.trainingSessions = [session]
        let reflection = try XCTUnwrap(TennisNotificationPlanner.plannedRequests(data: data, now: now).first)
        XCTAssertEqual(reflection.fireDate, session.actualFinish!.addingTimeInterval(Double(data.settings.postSessionDelayMinutes * 60)))
        data.trainingSessions[0].notes = "Worked on my return"
        XCTAssertTrue(TennisNotificationPlanner.plannedRequests(data: data, now: now).isEmpty)
        data.trainingSessions[0].notes = ""; data.trainingSessions[0].actualFinish = nil
        XCTAssertTrue(TennisNotificationPlanner.plannedRequests(data: data, now: now).isEmpty)
    }

    func testWeeklyReminderHasFixedMondayToSundayRangeNotRollingSevenDays() throws {
        var data = AppData(); data.settings.weeklySummaryEnabled = true
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let planned = try XCTUnwrap(TennisNotificationPlanner.plannedRequests(data: data, now: now).first)
        let route = try XCTUnwrap(TennisActivityRoute(url: planned.deepLink))
        let start = try XCTUnwrap(route.weekStart)
        XCTAssertEqual(Calendar.current.component(.weekday, from: start), 2)
        XCTAssertEqual(TennisReportingWeek.interval(containing: start).end, TennisReportingWeek.interval(containing: planned.fireDate).start)
        XCTAssertTrue(planned.body.contains(TennisReportingWeek.summary(containing: start)))
    }

    func testReflectionMergePreservesConcurrentHealthTimingPeopleLinksAndIdentity() throws {
        var session = TrainingSession(playerID: UUID())
        var draft = TennisReflectionDraft(session: session)
        draft.focus = "Serve and return"; draft.additionalFocus = ["Footwork"]
        draft.outcome = "More confident returns"; draft.notes = "Practise a shorter backswing"
        session.revision = 8; session.actualFinish = Date(); session.trackedOnWatch = true
        session.workout = TennisWorkoutResult(workoutID: UUID(), durationSeconds: 159)
        session.context.coachIDs = [UUID()]; session.context.tournamentID = UUID()
        let updated = try XCTUnwrap(draft.applying(to: session))
        XCTAssertEqual(updated.id, session.id); XCTAssertEqual(updated.context, session.context)
        XCTAssertEqual(updated.actualFinish, session.actualFinish); XCTAssertEqual(updated.workout, session.workout)
        XCTAssertEqual(updated.trackedOnWatch, true); XCTAssertEqual(updated.revision, 8)
        XCTAssertEqual(updated.additionalFocus, ["Footwork"]); XCTAssertEqual(updated.sessionOutcome, draft.outcome)
        XCTAssertNil(draft.applying(to: TrainingSession(playerID: session.playerID)))
    }

    func testResultReminderCannotOverwriteAnActiveMatchOrUnrelatedChanges() throws {
        var match = MatchRecord(playerID: UUID()); match.status = .scheduled
        var draft = TennisNotificationResult.draft(match)
        draft.result = .win; draft.yourSetsWon = 1; draft.setScores = "6-4"
        match.venue = "Updated court"; match.trainingSessionID = UUID(); match.notes = "Keep notes"
        let updated = try XCTUnwrap(TennisNotificationResult.applying(draft, to: match))
        XCTAssertEqual(updated.id, match.id); XCTAssertEqual(updated.trainingSessionID, match.trainingSessionID)
        XCTAssertEqual(updated.venue, "Updated court"); XCTAssertEqual(updated.notes, "Keep notes")
        XCTAssertEqual(updated.status, .completed); XCTAssertEqual(updated.result, .win)
        match.status = .inProgress
        XCTAssertNil(TennisNotificationResult.applying(draft, to: match))
    }

    func testTwentyTwoUniqueAchievementsIncludeFirstsAndClearLockedTargets() {
        let badges = TennisAchievement.build(records: [], playerID: UUID())
        XCTAssertEqual(badges.count, 22); XCTAssertEqual(Set(badges.map(\.id)).count, 22)
        XCTAssertTrue(badges.allSatisfy { !$0.earned && $0.progress == 0 && $0.target > 0 && !$0.requirement.isEmpty && !$0.celebration.isEmpty })
        for id in ["training.1", "training.10", "match.1", "match.10", "tournament.1", "watchTraining.1"] {
            XCTAssertTrue(badges.contains { $0.id == id })
        }
    }

    func testAchievementsIgnoreOtherPlayersFutureActiveAndDuplicateSessions() {
        let playerID = UUID(), now = Date()
        var done = TrainingSession(playerID: playerID); done.date = now.addingTimeInterval(-7200)
        done.focus = "Serve and return"; done.notes = "Improved"; done.trackedOnWatch = true
        var future = done; future.id = UUID(); future.date = now.addingTimeInterval(86400)
        var active = done; active.id = UUID(); active.actualStart = now
        var other = done; other.id = UUID(); other.playerID = UUID()
        let raw = TennisAchievementRecord.collect(matches: [], training: [done, done, future, active, other], tournaments: [], now: now)
        let records = TennisAchievementRecord.merge(history: [], current: raw, deleted: [])
        let badges = TennisAchievement.build(records: records, playerID: playerID)
        XCTAssertEqual(badges.first { $0.id == "training.10" }?.progress, 1)
        XCTAssertEqual(badges.first { $0.id == "watchTraining.1" }?.earned, true)
        XCTAssertEqual(badges.first { $0.id == "focus.1" }?.earned, true)
        XCTAssertEqual(badges.first { $0.id == "reflection.1" }?.earned, true)
    }

    func testWatchAllTimeProgressSurvivesCacheLimitAndOfflineEditsAndDeletions() throws {
        let now = Date(); var data = AppData(); let playerID = UUID(); data.selectedPlayerID = playerID
        for index in 0..<40 {
            var session = TrainingSession(playerID: playerID)
            session.date = now.addingTimeInterval(Double(-100 - index) * 86400)
            data.trainingSessions.append(session)
        }
        var snapshot = TennisWatchSnapshot(data: data, now: now)
        XCTAssertTrue(snapshot.trainingSessions.isEmpty)
        XCTAssertEqual(snapshot.achievements.first { $0.id == "training.50" }?.progress, 40)
        snapshot.deletedRecordIDs.insert(data.trainingSessions[0].id)
        var local = TrainingSession(playerID: playerID); local.date = now.addingTimeInterval(-7200); local.trackedOnWatch = true
        snapshot.trainingSessions.append(local)
        XCTAssertEqual(snapshot.achievements.first { $0.id == "training.50" }?.progress, 40)
        XCTAssertEqual(snapshot.achievements.first { $0.id == "watchTraining.1" }?.earned, true)
        let decoded = try JSONDecoder.tennisTracker.decode(TennisWatchSnapshot.self, from: JSONEncoder.tennisTracker.encode(snapshot))
        XCTAssertEqual(decoded.achievements, snapshot.achievements)
        XCTAssertEqual(TennisWatchSnapshot(data: data, now: now, including: data.trainingSessions[0].id).trainingSessions.first?.id, data.trainingSessions[0].id)
    }

    func testLinkedPracticeMatchIsNotAwardedTwiceAcrossHistoryCacheBoundary() {
        let id = UUID(), now = Date(); var session = TrainingSession(playerID: id)
        session.date = now.addingTimeInterval(-100 * 86400); session.practiceResult = TennisPracticeResult(kind: .doubles, result: .win)
        let history = TennisAchievementRecord.collect(matches: [], training: [session], tournaments: [], now: now)
        var match = MatchRecord(playerID: id); match.status = .completed; match.matchType = .doubles
        match.date = now.addingTimeInterval(-86400); match.trainingSessionID = session.id; match.result = .win
        let records = TennisAchievementRecord.merge(history: history, current: TennisAchievementRecord.collect(matches: [match], training: [], tournaments: [], now: now), deleted: [])
        let badges = TennisAchievement.build(records: records, playerID: id)
        XCTAssertEqual(badges.first { $0.id == "match.10" }?.progress, 1)
        XCTAssertEqual(badges.first { $0.id == "doublesWin.1" }?.progress, 1)
        XCTAssertEqual(badges.first { $0.id == "training.10" }?.progress, 1)
    }

    func testUnknownWatchOriginDoesNotInventAnAchievementAndOldDataDecodes() throws {
        var session = TrainingSession(playerID: UUID()); session.date = Date().addingTimeInterval(-7200)
        let data = try JSONEncoder.tennisTracker.encode(session)
        let decoded = try JSONDecoder.tennisTracker.decode(TrainingSession.self, from: data)
        XCTAssertNil(decoded.trackedOnWatch)
        XCTAssertFalse(TennisAchievementRecord.collect(matches: [], training: [decoded], tournaments: []).first!.metrics.contains("watchTraining"))
        XCTAssertEqual(TennisWatchActivityFactory.trainingSession(playerID: session.playerID).trackedOnWatch, true)
    }

    func testRequestedOlderActivitySurvivesNormalSyncButNeverDefeatsDeletion() {
        var data = AppData(); let id = UUID()
        var session = TrainingSession(playerID: id); session.date = Date().addingTimeInterval(-100 * 86400)
        data.trainingSessions = [session]
        let requested = TennisWatchSnapshot(data: data, including: session.id)
        XCTAssertEqual(requested.requestedActivityID, session.id); XCTAssertEqual(requested.requestedActivityFound, true)
        var next = TennisWatchSnapshot(data: data)
        XCTAssertTrue(next.trainingSessions.isEmpty)
        next.retainOpenActivities([session.id], from: requested)
        XCTAssertEqual(next.trainingSessions.first?.id, session.id)
        var deleted = TennisWatchSnapshot(data: data); deleted.deletedRecordIDs.insert(session.id)
        deleted.retainOpenActivities([session.id], from: requested)
        XCTAssertTrue(deleted.trainingSessions.isEmpty)
        XCTAssertEqual(TennisWatchSnapshot(data: data, including: UUID()).requestedActivityFound, false)
    }

    func testAchievementFeedbackDoesNotReplayAndHonoursDisabledMilestoneSound() {
        var session = TrainingSession(playerID: UUID()); session.date = Date().addingTimeInterval(-7200)
        let records = TennisAchievementRecord.collect(matches: [], training: [session], tournaments: [])
        let before = TennisAchievement.earnedIDs(records: records, playerID: session.playerID)
        XCTAssertEqual(TennisAchievement.feedback(before: [], records: records, playerID: session.playerID, settings: TennisSoundSettings(), otherwise: .completion), .milestone)
        XCTAssertEqual(TennisAchievement.feedback(before: before, records: records, playerID: session.playerID, settings: TennisSoundSettings(), otherwise: .save), .save)
        var settings = TennisSoundSettings(); settings.milestonesEnabled = false
        XCTAssertEqual(TennisAchievement.feedback(before: [], records: records, playerID: session.playerID, settings: settings, otherwise: .completion), .completion)
    }

    func testFiveDifferentSoundResourcesDecodeAndSettingsSurvivePhoneWatchRoundTrip() throws {
        XCTAssertEqual(TennisSound.allCases.count, 5)
        var contents = Set<Data>()
        for sound in TennisSound.allCases {
            let url = try XCTUnwrap(Bundle.main.url(forResource: sound.filename, withExtension: nil), sound.filename)
            let bytes = try Data(contentsOf: url); contents.insert(bytes)
            let player = try AVAudioPlayer(data: bytes)
            XCTAssertGreaterThan(player.duration, 0.1); XCTAssertLessThan(player.duration, 2)
            var data = AppData(); data.settings.sounds.selected = sound
            data.settings.sounds.savesEnabled = true; data.settings.sounds.reminders = .silent
            let decoded = try JSONDecoder.tennisTracker.decode(TennisWatchSnapshot.self, from: JSONEncoder.tennisTracker.encode(TennisWatchSnapshot(data: data)))
            XCTAssertEqual(decoded.settings.sounds, data.settings.sounds)
        }
        XCTAssertEqual(contents.count, 5)
    }

    func testSoundMigrationAndQuietDefaults() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(old.sounds.selected, .bounce); XCTAssertFalse(old.sounds.allows(.save))
        let unknown = try JSONDecoder().decode(TennisSoundSettings.self, from: Data("{\"selected\":\"future-sound\",\"reminders\":\"future-mode\"}".utf8))
        XCTAssertEqual(unknown.selected, .bounce); XCTAssertEqual(unknown.reminders, .tennis)
        var silent = unknown; silent.reminders = .silent
        XCTAssertNil(silent.notificationSound())
        silent.completionsEnabled = false; silent.milestonesEnabled = false
        XCTAssertFalse(silent.allows(.completion)); XCTAssertFalse(silent.allows(.milestone))
    }
}
