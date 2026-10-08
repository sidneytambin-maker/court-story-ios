import XCTest
@testable import TennisTracker

@MainActor
private final class MockWorkoutClient: TennisWorkoutClient {
    var available = true
    var permission = true
    var workoutAuthorization: TennisWorkoutAuthorization = .notDetermined
    var isWorkoutRunning = true
    var isWorkoutPaused = false
    var workoutStartedAt: Date?
    var onHealthStateChange: ((TennisWorkoutState, String) -> Void)?
    var begins = 0
    var finishes = 0
    var permissionRequests = 0
    var discarded = 0
    var recoveries = 0
    var permissionResponse: (@MainActor () async -> Bool)?
    var beginResponse: (@MainActor () async throws -> Void)?
    var finishResponse: (@MainActor () async -> TennisWorkoutResult)?
    var result = TennisWorkoutResult(durationSeconds: 600)
    func requestPermission() async throws -> Bool {
        permissionRequests += 1
        if let permissionResponse { return await permissionResponse() }
        workoutAuthorization = permission ? .authorized : .denied
        return permission
    }
    func discardForLibraryChange() { discarded += 1 }
    var begunActivityID: UUID?
    var canRecover = false
    var failStart = false
    var failFinish = false
    func begin(activityID: UUID, at date: Date) async throws {
        if let beginResponse { try await beginResponse() }
        if failStart { throw NSError(domain: "TestWorkout", code: 1) }
        begins += 1; begunActivityID = activityID
    }
    func finish(at date: Date) async throws -> TennisWorkoutResult {
        finishes += 1
        if failFinish { throw NSError(domain: "TestWorkout", code: 2) }
        if let finishResponse { return await finishResponse() }
        return result
    }
    func recover(activityID: UUID) async throws -> Bool { recoveries += 1; return canRecover }
}

final class TennisWorkoutTests: XCTestCase {
    @MainActor
    func testLibraryChangeCancelsPendingHealthPermissionWithoutStartingWorkout() async {
        let client = MockWorkoutClient()
        let coordinator = TennisWorkoutCoordinator(client: client)
        client.permissionResponse = {
            coordinator.discardForLibraryChange()
            return true
        }
        await coordinator.start(useHealth: true)
        XCTAssertEqual(client.discarded, 1)
        XCTAssertEqual(client.begins, 0)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.activityID)
    }

    @MainActor
    func testLibraryChangeCannotAttachLateHealthResultToNewLibrary() async {
        let client = MockWorkoutClient()
        let coordinator = TennisWorkoutCoordinator(client: client)
        await coordinator.start(useHealth: true)
        client.finishResponse = {
            coordinator.discardForLibraryChange()
            return TennisWorkoutResult(workoutID: UUID(), durationSeconds: 100, averageHeartRate: 120)
        }
        let result = await coordinator.finish()
        XCTAssertNil(result)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.activityID)
        XCTAssertEqual(client.discarded, 1)
    }

    @MainActor
    func testWorkoutUsesTrainingIDAndRecoveryDoesNotStartAnotherWorkout() async {
        let client = MockWorkoutClient()
        let id = UUID()
        let coordinator = TennisWorkoutCoordinator(client: client)
        await coordinator.start(useHealth: true, activityID: id)
        XCTAssertEqual(client.begunActivityID, id)
        let restored = TennisWorkoutCoordinator(client: client)
        client.canRecover = true
        await restored.restore(activityID: id, startedAt: Date())
        XCTAssertEqual(restored.state, .recording)
        XCTAssertEqual(client.begins, 1)
    }

    @MainActor
    func testRestartWithoutHealthRetainsElapsedTime() async {
        let client = MockWorkoutClient()
        let coordinator = TennisWorkoutCoordinator(client: client)
        let start = Date(timeIntervalSince1970: 100)
        await coordinator.restore(activityID: UUID(), startedAt: start)
        let result = await coordinator.finish(at: start.addingTimeInterval(900))
        XCTAssertEqual(result?.durationSeconds, 900)
        XCTAssertNil(result?.workoutID)
        XCTAssertEqual(client.begins, 0)
    }

    @MainActor
    func testHealthFailuresRetainTrainingWithoutInventedMetrics() async {
        for failStart in [true, false] {
            let client = MockWorkoutClient()
            client.failStart = failStart; client.failFinish = !failStart
            let coordinator = TennisWorkoutCoordinator(client: client)
            let start = Date(timeIntervalSince1970: 100)
            await coordinator.start(useHealth: true, at: start)
            if failStart {
                XCTAssertEqual(coordinator.state, .startFailed)
                let prematureFinish = await coordinator.finish()
                XCTAssertNil(prematureFinish)
                await coordinator.start(useHealth: false, at: start)
            }
            let result = await coordinator.finish(at: start.addingTimeInterval(600))
            XCTAssertEqual(result?.durationSeconds, 600)
            XCTAssertNil(result?.workoutID)
            XCTAssertNil(result?.averageHeartRate)
            XCTAssertNil(result?.activeEnergyKcal)
        }
    }
    @MainActor
    func testDeclinedPermissionRequiresExplicitTimingFallback() async {
        let client = MockWorkoutClient(); client.permission = false
        let coordinator = TennisWorkoutCoordinator(client: client)
        let start = Date(timeIntervalSince1970: 100)
        await coordinator.start(useHealth: true, at: start)
        XCTAssertEqual(coordinator.state, .startFailed)
        XCTAssertNil(coordinator.activityID)
        XCTAssertNil(coordinator.startedAt)
        XCTAssertTrue(coordinator.message.contains("Workout saving"))
        XCTAssertEqual(client.begins, 0)
        let prematureFinish = await coordinator.finish()
        XCTAssertNil(prematureFinish)
        await coordinator.start(useHealth: false, at: start)
        let result = await coordinator.finish(at: start.addingTimeInterval(600))
        XCTAssertEqual(result?.durationSeconds, 600)
        XCTAssertNil(result?.workoutID)
        XCTAssertNil(result?.averageHeartRate)
        XCTAssertEqual(client.finishes, 0)
    }

    @MainActor
    func testGrantedPermissionStartsAndEndsOneWorkout() async {
        let client = MockWorkoutClient()
        client.result.workoutID = UUID()
        let coordinator = TennisWorkoutCoordinator(client: client)
        await coordinator.start(useHealth: true)
        await coordinator.start(useHealth: true)
        XCTAssertEqual(coordinator.state, .recording)
        XCTAssertEqual(client.begins, 1)
        let result = await coordinator.finish()
        XCTAssertEqual(result?.workoutID, client.result.workoutID)
        XCTAssertEqual(client.finishes, 1)
        XCTAssertEqual(coordinator.state, .finished)
        let repeated = await coordinator.finish()
        XCTAssertNil(repeated)
    }

    @MainActor
    func testNoConsentNeverRequestsHealthPermission() async {
        let client = MockWorkoutClient()
        let coordinator = TennisWorkoutCoordinator(client: client)
        await coordinator.start(useHealth: false)
        XCTAssertEqual(client.permissionRequests, 0)
        XCTAssertEqual(client.begins, 0)
    }

    @MainActor
    func testUnavailableCapabilityKeepsTrainingFunctional() async {
        let client = MockWorkoutClient(); client.available = false
        let coordinator = TennisWorkoutCoordinator(client: client)
        await coordinator.start(useHealth: true)
        XCTAssertEqual(coordinator.state, .startFailed)
        XCTAssertEqual(client.permissionRequests, 0)
        await coordinator.start(useHealth: false)
        XCTAssertEqual(coordinator.state, .recordingWithoutHealth)
    }

    func testStartConfirmationRequiresBothSessionAndBuilderInEitherOrder() {
        var confirmation = TennisWorkoutStartConfirmation()
        XCTAssertFalse(confirmation.isReady)
        confirmation.sessionIsRunning = true
        XCTAssertFalse(confirmation.isReady)
        confirmation.collectionStarted = true
        XCTAssertTrue(confirmation.isReady)
        confirmation.sessionIsRunning = false
        XCTAssertFalse(confirmation.isReady)
        confirmation = TennisWorkoutStartConfirmation()
        confirmation.collectionStarted = true
        XCTAssertFalse(confirmation.isReady)
        confirmation.sessionIsRunning = true
        XCTAssertTrue(confirmation.isReady)
    }

    func testAuthorizedDefaultRespectsAnExplicitOptOut() {
        XCTAssertTrue(TennisWorkoutAuthorization.authorized.useHealthByDefault(preference: nil))
        XCTAssertFalse(TennisWorkoutAuthorization.authorized.useHealthByDefault(preference: false))
        XCTAssertTrue(TennisWorkoutAuthorization.notDetermined.useHealthByDefault(preference: nil))
        XCTAssertFalse(TennisWorkoutAuthorization.unavailable.useHealthByDefault(preference: nil))
        XCTAssertTrue(TennisWorkoutAuthorization.denied.useHealthByDefault(preference: true))
    }

    @MainActor
    func testAlreadyAuthorizedChecksCurrentTypesAndStartsWithoutWaitingForMetrics() async {
        let client = MockWorkoutClient()
        client.workoutAuthorization = .authorized
        client.result = TennisWorkoutResult(durationSeconds: 600)
        let coordinator = TennisWorkoutCoordinator(client: client)
        let started = await coordinator.start(useHealth: true)
        XCTAssertTrue(started)
        XCTAssertEqual(client.permissionRequests, 1)
        XCTAssertEqual(client.begins, 1)
        XCTAssertEqual(coordinator.state, .recording)
        XCTAssertFalse(coordinator.message.contains("permission"))
        let result = await coordinator.finish()
        XCTAssertNil(result?.averageHeartRate)
        XCTAssertNil(result?.activeEnergyKcal)
    }

    @MainActor
    func testCompletedPermissionRequestIsNotAWriteGrant() async {
        let client = MockWorkoutClient()
        client.permissionResponse = { true }
        let coordinator = TennisWorkoutCoordinator(client: client)
        let started = await coordinator.start(useHealth: true)
        XCTAssertFalse(started)
        XCTAssertEqual(client.begins, 0)
        XCTAssertEqual(coordinator.state, .startFailed)
        XCTAssertTrue(coordinator.message.contains("not been confirmed"))
        XCTAssertFalse(coordinator.message.contains("turned off"))
    }

    @MainActor
    func testKnownWriteDenialDoesNotRepeatPermissionSheet() async {
        let client = MockWorkoutClient()
        client.workoutAuthorization = .denied
        let coordinator = TennisWorkoutCoordinator(client: client)
        await coordinator.start(useHealth: true)
        XCTAssertEqual(client.permissionRequests, 0)
        XCTAssertEqual(client.begins, 0)
        XCTAssertEqual(coordinator.state, .startFailed)
        client.workoutAuthorization = .authorized
        let retried = await coordinator.start(useHealth: true)
        XCTAssertTrue(retried)
        XCTAssertEqual(client.begins, 1)
    }

    @MainActor
    func testPendingStartupNeverReportsRecordingAndIgnoresDuplicateStart() async {
        let client = MockWorkoutClient()
        let coordinator = TennisWorkoutCoordinator(client: client)
        client.beginResponse = {
            XCTAssertEqual(coordinator.state, .starting)
            let duplicate = await coordinator.start(useHealth: true)
            XCTAssertFalse(duplicate)
            let prematureFinish = await coordinator.finish()
            XCTAssertNil(prematureFinish)
        }
        await coordinator.start(useHealth: true)
        XCTAssertEqual(coordinator.state, .recording)
        XCTAssertEqual(client.begins, 1)
    }

    @MainActor
    func testInterruptedStartCannotBecomeRecordingAfterBeginReturns() async {
        let client = MockWorkoutClient()
        client.isWorkoutRunning = false
        let coordinator = TennisWorkoutCoordinator(client: client)
        let started = await coordinator.start(useHealth: true)
        XCTAssertFalse(started)
        XCTAssertEqual(coordinator.state, .startFailed)
    }

    @MainActor
    func testStartTimeoutIsRetryableAndDoesNotCreateARecording() async {
        let client = MockWorkoutClient()
        client.workoutAuthorization = .authorized
        client.beginResponse = { throw TennisWorkoutFailure.startTimedOut }
        let coordinator = TennisWorkoutCoordinator(client: client)
        let started = await coordinator.start(useHealth: true)
        XCTAssertFalse(started)
        XCTAssertEqual(coordinator.state, .startFailed)
        XCTAssertNil(coordinator.startedAt)
        XCTAssertNil(coordinator.activityID)
        XCTAssertTrue(coordinator.message.contains("did not confirm"))
        client.beginResponse = nil
        let retried = await coordinator.start(useHealth: true)
        XCTAssertTrue(retried)
        XCTAssertEqual(coordinator.state, .recording)
        XCTAssertEqual(client.permissionRequests, 2)
    }

    @MainActor
    func testCancelAuthorizationIgnoresLateGrantAndAllowsAnotherStart() async {
        let client = MockWorkoutClient()
        let coordinator = TennisWorkoutCoordinator(client: client)
        client.permissionResponse = {
            coordinator.cancelStart()
            client.workoutAuthorization = .authorized
            return true
        }
        let cancelled = await coordinator.start(useHealth: true)
        XCTAssertFalse(cancelled)
        XCTAssertEqual(client.begins, 0)
        XCTAssertEqual(coordinator.state, .idle)
        client.permissionResponse = nil
        let retried = await coordinator.start(useHealth: true)
        XCTAssertTrue(retried)
        XCTAssertEqual(client.begins, 1)
    }

    @MainActor
    func testCoachedAthleteRecoveryCannotAttachWatchOwnersHealth() async {
        let client = MockWorkoutClient()
        client.canRecover = true
        let coordinator = TennisWorkoutCoordinator(client: client)
        await coordinator.restore(activityID: UUID(), startedAt: Date(), useHealth: false)
        XCTAssertEqual(client.recoveries, 0)
        XCTAssertEqual(coordinator.state, .recordingWithoutHealth)
        let saved = await coordinator.finish()
        XCTAssertNil(saved?.workoutID)
        XCTAssertEqual(client.finishes, 0)
    }

    @MainActor
    func testFinishFailureClearsRecordingStateAndLateCallbacksCannotReviveIt() async {
        let client = MockWorkoutClient()
        client.failFinish = true
        let coordinator = TennisWorkoutCoordinator(client: client)
        await coordinator.start(useHealth: true)
        _ = await coordinator.finish()
        XCTAssertEqual(coordinator.state, .finished)
        XCTAssertTrue(coordinator.message.contains("could not be saved"))
        client.onHealthStateChange?(.recording, "Late session callback")
        XCTAssertEqual(coordinator.state, .finished)
        XCTAssertFalse(coordinator.message.contains("Late"))
    }

    func testLegacyHealthStatusDecodesWithoutAssumingAuthorization() throws {
        let status = try JSONDecoder().decode(TennisWatchHealthStatus.self,
            from: Data(#"{"access":"Workout saving allowed","enabledByDefault":true,"reportedAt":0}"#.utf8))
        XCTAssertNil(status.workoutAuthorization)
        XCTAssertTrue(status.enabledByDefault)
    }

    @MainActor
    func testLibraryReplacementWhileBeginningDoesNotReportRecording() async {
        let client = MockWorkoutClient()
        let coordinator = TennisWorkoutCoordinator(client: client)
        client.beginResponse = { coordinator.discardForLibraryChange() }
        let started = await coordinator.start(useHealth: true)
        XCTAssertFalse(started)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.activityID)
    }

    @MainActor
    func testPauseResumeAndInterruptionUpdateSharedStateWithoutNewHealthMetrics() async {
        let client = MockWorkoutClient()
        let coordinator = TennisWorkoutCoordinator(client: client)
        let start = Date(timeIntervalSince1970: 100)
        await coordinator.start(useHealth: true, at: start)
        client.onHealthStateChange?(.paused, "Health workout paused.")
        XCTAssertEqual(coordinator.state, .paused)
        client.onHealthStateChange?(.recording, "Health workout recording.")
        XCTAssertEqual(coordinator.state, .recording)
        client.onHealthStateChange?(.recordingWithoutHealth, "Health recording stopped.")
        XCTAssertEqual(coordinator.state, .recordingWithoutHealth)
        XCTAssertEqual(coordinator.message, "Health recording stopped.")
        let result = await coordinator.finish(at: start.addingTimeInterval(600))
        XCTAssertEqual(result?.durationSeconds, 600)
        XCTAssertNil(result?.averageHeartRate)
        XCTAssertEqual(client.finishes, 0)
    }

    @MainActor
    func testRecoveredPausedWorkoutCanFinishWithoutClaimingRecording() async {
        let client = MockWorkoutClient()
        client.canRecover = true
        client.isWorkoutPaused = true
        let coordinator = TennisWorkoutCoordinator(client: client)
        await coordinator.restore(activityID: UUID(), startedAt: Date())
        XCTAssertEqual(coordinator.state, .paused)
        XCTAssertTrue(coordinator.message.contains("paused"))
        _ = await coordinator.finish()
        XCTAssertEqual(client.finishes, 1)
    }

    @MainActor
    func testConfirmedHealthStartTimeExcludesPermissionWait() async {
        let client = MockWorkoutClient()
        client.workoutStartedAt = Date(timeIntervalSince1970: 160)
        let coordinator = TennisWorkoutCoordinator(client: client)
        await coordinator.start(useHealth: true, at: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(coordinator.startedAt, client.workoutStartedAt)
    }

    func testComplicationRoutesLiveTrainingAndScore() {
        var snapshot = TennisWatchSnapshot()
        snapshot.trainingSessions = [TennisWatchActivityFactory.trainingSession(playerID: UUID())]
        XCTAssertEqual(TennisGlance.make(snapshot: snapshot).destination, .live)
        var player = PlayerProfile(); player.name = "Alex"
        var match = TennisWatchActivityFactory.match(player: player, kind: .doubles)
        match.partnerName = "Jo"; match.opponentName = "Sam"; match.opponent2Name = "Kim"
        snapshot.matches = [match]
        let glance = TennisGlance.make(snapshot: snapshot)
        XCTAssertEqual(glance.destination, .score)
        for name in ["Alex", "Jo", "Sam", "Kim"] { XCTAssertTrue(glance.accessibilitySummary.contains(name)) }
    }

    func testStaleComplicationDoesNotClaimLiveMatch() {
        var snapshot = TennisWatchSnapshot()
        var match = TennisWatchActivityFactory.match(player: PlayerProfile(), kind: .singles)
        match.modifiedAt = Date(timeIntervalSince1970: 100)
        snapshot.matches = [match]
        let glance = TennisGlance.make(snapshot: snapshot, now: Date(timeIntervalSince1970: 100000))
        XCTAssertTrue(glance.isStale)
        XCTAssertEqual(glance.title, "Saved match")
    }

    func testPracticeResultIsNotACompetitiveMatch() {
        var data = AppData()
        var session = TrainingSession(playerID: UUID())
        session.trainingType = .matchPlay
        session.practiceResult = TennisPracticeResult(result: .win, playerGames: 6, opponentGames: 4)
        data.trainingSessions = [session]
        XCTAssertTrue(data.matches.isEmpty)
        XCTAssertEqual(data.trainingSessions[0].practiceResult?.playerGames, 6)
    }
}
