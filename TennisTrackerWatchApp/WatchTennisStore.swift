import Foundation
import Combine
import Accessibility
import WidgetKit
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif

@MainActor
final class WatchTennisStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var snapshot = TennisWatchSnapshot.empty
    @Published var activeTraining: TrainingSession?
    @Published var activeMatch: MatchRecord?
    @Published var scoreState = TennisScoreState()
    @Published var lastAnnouncement = "Court Story ready."
    @Published var lastSyncStatus = "Waiting for iPhone data."
    @Published var page: TennisWatchPage = .today
    @Published var completedTraining: TrainingSession?
    @Published var activeTournamentID: UUID?
    let healthClient: WatchHealthWorkout
    private let workoutClient: TennisWorkoutClient
    lazy var workoutCoordinator = TennisWorkoutCoordinator(client: workoutClient)
    @Published var workoutMessage = ""
    @Published var isPreparingWorkout = false
    @Published var isFinishingWorkout = false
    @Published var pendingHealthStart: TrainingSession?
    #if DEBUG && targetEnvironment(simulator)
    @Published private(set) var nativeHealthReadback = ""
    #endif
    private var workoutStartID: UUID?
    private var workoutObservation: AnyCancellable?
    private let pendingHealthDraftKey = "pendingHealthTrainingDraft"
    private struct PendingHealthDraft: Codable {
        var libraryID: UUID?
        var training: TrainingSession
    }

    var defaultUseHealth: Bool {
        guard let player = selectedPlayer else { return false }
        return defaultUseHealth(for: player.id)
    }

    private func defaultUseHealth(for playerID: UUID) -> Bool {
        guard mayUseHealth(for: playerID) else { return false }
        return workoutAccess.useHealthByDefault(
            preference: UserDefaults.standard.object(forKey: "trackTrainingAsWorkout") as? Bool)
    }

    func setDefaultUseHealth(_ enabled: Bool) {
        objectWillChange.send()
        UserDefaults.standard.set(enabled, forKey: "trackTrainingAsWorkout")
        sendHealthStatus()
    }

    var workoutAccess: TennisWorkoutAuthorization { workoutClient.workoutAuthorization }

    var workoutStartHint: String {
        defaultUseHealth ? "Starts timing and an Apple Health workout. Requests any Health access that has not yet been decided."
            : "Starts session timing only. Health is off for this profile. You can review Health access from Menu."
    }

    func reviewHealthAccess() async -> String {
        guard let player = selectedPlayer, mayUseHealth(for: player.id) else { return "Health access is only for the Watch owner's activity." }
        do {
            let allowed = try await workoutClient.requestPermission()
            sendHealthStatus()
            objectWillChange.send()
            return allowed ? "Workout saving is allowed. Your next workout can use Apple Health." : workoutAccess.description
        } catch { return error.localizedDescription }
    }

    private let snapshotKey = "snapshotData"
    private let commandKey = "commandData"
    private let localSnapshotKey = "watchSnapshot"
    private let queuedCommandsKey = "queuedWatchCommands"
    private var queuedCommands: [TennisWatchSyncCommand] = []
    private var libraryFence = TennisWatchLibraryFence()
    private var pointHistory: [TennisScoreSnapshot] = []
    private var isRestoringWorkout = false
    var openNotificationRecordIDs = Set<UUID>()

    override init() {
        let health = WatchHealthWorkout()
        healthClient = health
        #if DEBUG && targetEnvironment(simulator)
        workoutClient = WatchWorkoutTestClient.makeIfRequested() ?? health
        #else
        workoutClient = health
        #endif
        super.init()
        workoutObservation = workoutCoordinator.$message.sink { [weak self] message in
            self?.workoutMessage = message
        }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-watch") {
            var data = AppData()
            var player = PlayerProfile(); player.name = "Alex"
            data.players = [player]
            data.setup.coaches = [TennisCoach(name: "Chris"), TennisCoach(name: "Sarah")]
            data.selectedPlayerID = player.id
            if ProcessInfo.processInfo.arguments.contains("-watch-manual-match") {
                var opponent = PlayerProfile(); opponent.name = "Sam"
                data.players.append(opponent)
            }
            if ProcessInfo.processInfo.arguments.contains("-watch-venue-regression") {
                data = TennisRegressionFixtures.venueAndDashboard()
            }
            if ProcessInfo.processInfo.arguments.contains("-watch-scheduled-training") {
                var training = TrainingSession(playerID: player.id)
                training.date = Date().addingTimeInterval(600)
                training.hasStartTime = true
                training.context.coachIDs = [data.setup.coaches[0].id]
                data.trainingSessions = [training]
                UserDefaults.standard.set(ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-watch-health=") }), forKey: "trackTrainingAsWorkout")
            }
            if ProcessInfo.processInfo.arguments.contains("-watch-completed-training") {
                var training = TrainingSession(playerID: player.id)
                training.actualStart = Date(timeIntervalSince1970: 1000)
                training.actualFinish = Date(timeIntervalSince1970: 1159)
                training.durationMinutes = 3
                training.needsDetails = true
                training.workout = TennisWorkoutResult(durationSeconds: 159, averageHeartRate: 72, activeEnergyKcal: 4,
                    peakHeartRate: 90, distanceMeters: 123, stepCount: 201)
                data.trainingSessions = [training]
                completedTraining = training
            }
            if ProcessInfo.processInfo.arguments.contains("-watch-active-match") {
                var match = MatchRecord(playerID: player.id)
                match.playerName = "Alex"
                match.opponentName = "Sam"
                match.actualStart = Date()
                match.status = .inProgress
                match.liveScore = scoreState.snapshot
                data.matches = [match]
                activeMatch = match
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-tournament-outcome") {
                data = TennisTournamentUITestFixture.make()
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-tournament-summary") {
                data = TennisTournamentSummaryUITestFixture.make()
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-match-list") {
                data = TennisMatchListUITestFixture.make()
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-court-coach") { data = CourtDemoLibrary.make() }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-court-welcome") {
                data = AppData()
                if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-setup") {
                    CourtSetupDraft.clear("Watch")
                    if ProcessInfo.processInfo.arguments.contains("-ui-testing-named-setup") {
                        var draft = CourtSetupDraft()
                        draft.player.name = "Demo Wrist Player"
                        draft.persist("Watch")
                    }
                }
            }
            if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-watch-mode=") }),
               let mode = TrackingMode(rawValue: String(argument.dropFirst("-watch-mode=".count))) {
                data.settings.trackingMode = mode
            }
            snapshot = TennisWatchSnapshot(data: data)
            if let route = TennisNotificationTestSupport.route(training: snapshot.trainingSessions, matches: snapshot.matches, tournaments: snapshot.tournaments) {
                TennisNotificationInbox.enqueue(route.url)
            }
            if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-watch-page=") }),
               let destination = TennisWatchPage(rawValue: String(argument.dropFirst("-watch-page=".count))) { page = destination }
            return
        }
        #endif
        loadLocalState()
    }

    var selectedPlayer: PlayerProfile? {
        if let id = snapshot.selectedPlayerID {
            guard var player = snapshot.players.first(where: { $0.id == id && !$0.isArchived }) else { return nil }
            if player.court.sports.contains(where: { $0.sport == courtSport }) { player.court.selectedSportID = courtSport.id }
            return player
        }
        return snapshot.players.first { !$0.isArchived }
    }

    var upcomingTournament: TournamentRecord? {
        scopedSnapshot.tournaments
            .filter { !$0.isCompleted }
            .sorted { $0.date < $1.date }
            .first
    }

    var needsDetailsCount: Int {
        scopedSnapshot.matches.filter(\.needsDetails).count
        + scopedSnapshot.trainingSessions.filter(\.needsDetails).count
        + scopedSnapshot.tournaments.filter(\.needsDetails).count
    }

    var recentSummary: [String] {
        let matches = snapshot.matches.prefix(3).map { TennisSummaryFormatter.match($0, tournaments: snapshot.tournaments, style: .short) }
        let training = snapshot.trainingSessions.prefix(3).map { trainingSummary($0, style: .short) }
        return Array((matches + training).prefix(5))
    }

    func trainingSummary(_ session: TrainingSession, style: TennisSummaryStyle = .long, now: Date = Date()) -> String {
        TennisSummaryFormatter.training(session, style: style, now: now, coaches: snapshot.setup.coaches, players: snapshot.players)
    }

    func activate() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-watch") { return }
        #endif
        persistSnapshot()
        restoreWorkoutIfNeeded()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        send(.requestSnapshot)
    }

    func sendHealthStatus() {
        guard let libraryID = snapshot.libraryID else { return }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let status = TennisWatchHealthStatus(access: workoutAccess.description,
            enabledByDefault: defaultUseHealth, reportedAt: Date(), workoutAuthorization: workoutAccess)
        guard let data = try? JSONEncoder.tennisTracker.encode(status) else { return }
        try? WCSession.default.updateApplicationContext(["healthStatusData": data, "libraryID": libraryID.uuidString])
    }

    @discardableResult
    func trackTrainingSession(type: TrainingType = .singlesPractice, focus: String = "", additionalFocus: [String] = [], context: TennisActivityContext = TennisActivityContext(), venue: String = "", location: String = "", useHealth: Bool? = nil) -> Bool {
        guard let playerID = selectedPlayer?.id else {
            announce("Set up a player on iPhone first.")
            return false
        }
        var session = TennisWatchActivityFactory.trainingSession(playerID: playerID, type: type)
        if let player = selectedPlayer { session.court = CourtActivity(player: player, coachID: capturingCoachID) }
        session.focus = focus
        session.additionalFocus = additionalFocus
        session.context = context
        session.venue = venue
        session.location = location
        return prepareTrainingStart(session, useHealth: useHealth ?? defaultUseHealth)
    }

    func finishTrainingSession() {
        guard !isPreparingWorkout else { announce("Waiting for Health workout startup to finish."); return }
        guard let activeTraining else {
            announce("No training session in progress.")
            return
        }
        let finishDate = Date()
        let beforeAchievements = TennisAchievement.earnedIDs(records: snapshot.achievementRecords, playerID: activeTraining.playerID)
        let finished = TennisWatchActivityFactory.finishTrainingSession(activeTraining, finishDate: finishDate)
        self.activeTraining = nil
        completedTraining = finished
        mergeTraining(finished)
        send(.upsertTraining(finished))
        sound(TennisAchievement.feedback(before: beforeAchievements, records: snapshot.achievementRecords, playerID: finished.playerID,
            settings: snapshot.settings.sounds, otherwise: .completion))
        haptic(.success)
        announce("Training finished. " + TennisDurationFormatter.training(finished) + ".")
        finishWorkout(for: finished.id, at: finishDate)
    }

    func recordMatch(kind: MatchKind, tournament: TournamentRecord? = nil) {
        guard let player = selectedPlayer else {
            announce("Set up a player on iPhone first.")
            return
        }
        var match = TennisWatchActivityFactory.match(player: player, kind: kind, tournament: tournament)
        match.court = CourtActivity(player: player, coachID: capturingCoachID)
        match.configureNewCourtMatch()
        match.applyCourtScore(match.makeCourtScore())
        pointHistory = []
        persistPointHistory()
        activeMatch = match
        page = .score
        scoreState = TennisScoreState(snapshot: match.liveScore ?? TennisScoreState().snapshot)
        mergeMatch(match)
        send(.upsertMatch(match))
        haptic(.start)
        announce("Match scoring ready.")
    }

    func trackTournament() {
        guard let playerID = selectedPlayer?.id else {
            announce("Set up a player on iPhone first.")
            return
        }
        let tournament = TennisWatchActivityFactory.tournament(playerID: playerID)
        mergeTournament(tournament)
        send(.upsertTournament(tournament))
        haptic(.success)
        announce("Tournament created. Complete tournament details on iPhone.")
    }

    func resume(_ match: MatchRecord) {
        if activeMatch?.id != match.id || activeMatch?.liveScore != match.liveScore {
            pointHistory = []
            persistPointHistory()
        }
        activeMatch = match
        page = .score
        scoreState = TennisScoreState(snapshot: match.liveScore ?? TennisScoreState().snapshot)
        announce("Resumed match scoring.")
    }

    func beginMatch(_ match: MatchRecord) {
        guard !snapshot.deletedRecordIDs.contains(match.id) else { announce("This match was deleted."); return }
        var match = match
        if snapshot.matches.contains(where: { $0.id == match.id }) {
            match.actualStart = match.actualStart ?? Date()
        } else { match.actualStart = Date() }
        match.actualFinish = nil
        match.status = .inProgress
        if match.usesCourtScoring {
            match.applyCourtScore(match.makeCourtScore())
            if saveCourtMatch(match) { page = .score }
            return
        }
        match.liveScore = match.liveScore ?? TennisScoreState().snapshot
        match = TennisRecordConflictResolver.prepareLocalMatch(match)
        mergeMatch(match)
        send(.upsertMatch(match))
        resume(match)
    }

    @discardableResult
    func beginTraining(_ planned: TrainingSession, useHealth: Bool? = nil) -> Bool {
        guard !snapshot.deletedRecordIDs.contains(planned.id), planned.actualStart == nil, planned.actualFinish == nil else {
            announce("This session has already started or was deleted."); return false
        }
        return prepareTrainingStart(planned, useHealth: useHealth ?? defaultUseHealth(for: planned.playerID))
    }

    func retryHealthStart() {
        guard let pendingHealthStart, !isPreparingWorkout else { return }
        prepareTrainingStart(pendingHealthStart, useHealth: true)
    }

    func startPendingTrainingWithoutHealth() {
        guard let pendingHealthStart, !isPreparingWorkout else { return }
        prepareTrainingStart(pendingHealthStart, useHealth: false)
    }

    func cancelPendingTrainingStart() {
        guard pendingHealthStart != nil else { return }
        workoutStartID = nil
        workoutCoordinator.cancelStart()
        isPreparingWorkout = false
        pendingHealthStart = nil
        UserDefaults.standard.removeObject(forKey: pendingHealthDraftKey)
        workoutCoordinator.discardForLibraryChange()
        workoutMessage = "Workout start cancelled. No session was recorded."
        announce(workoutMessage)
    }

    @discardableResult
    private func prepareTrainingStart(_ draft: TrainingSession, useHealth: Bool) -> Bool {
        guard activeTraining == nil, !isPreparingWorkout, !isRestoringWorkout, !isFinishingWorkout else {
            page = .live
            announce(activeTraining != nil ? "A workout is already in progress. End it on the Live screen before starting another."
                : isFinishingWorkout ? "Saving your previous workout. Please wait for the save confirmation."
                : isRestoringWorkout ? "Checking your previous workout. Please try Start Workout again when this finishes."
                : "Workout startup is already in progress. Its status is on the Live screen.")
            return false
        }
        guard !snapshot.deletedRecordIDs.contains(draft.id),
              !snapshot.trainingSessions.contains(where: { $0.id == draft.id && ($0.actualStart != nil || $0.actualFinish != nil) }) else {
            pendingHealthStart = nil
            announce("This session has already started or was deleted.")
            return false
        }
        let useHealth = useHealth && mayUseHealth(for: draft.playerID)
        healthClient.courtSport = draft.court.sport.sport
        healthClient.clearMetrics()
        workoutMessage = useHealth ? "Checking Health workout access." : "Starting session timing."
        var session = draft
        session.trackedOnWatch = true
        session.actualStart = Date()
        session.actualFinish = nil
        // Preserve the draft across a crash between HealthKit startup and snapshot persistence.
        var pendingDraft = draft
        pendingDraft.actualStart = nil; pendingDraft.actualFinish = nil
        pendingHealthStart = pendingDraft
        if useHealth, let data = try? JSONEncoder.tennisTracker.encode(PendingHealthDraft(libraryID: snapshot.libraryID, training: pendingDraft)) {
            UserDefaults.standard.set(data, forKey: pendingHealthDraftKey)
        } else { UserDefaults.standard.removeObject(forKey: pendingHealthDraftKey) }
        isPreparingWorkout = true
        let requestID = UUID()
        workoutStartID = requestID
        let libraryID = snapshot.libraryID
        page = .live
        announce(workoutMessage)
        Task {
            guard snapshot.libraryID == libraryID, workoutStartID == requestID else { return }
            let started = await workoutCoordinator.start(useHealth: useHealth, activityID: session.id, at: session.actualStart ?? session.date)
            guard snapshot.libraryID == libraryID, workoutStartID == requestID else { return }
            workoutStartID = nil
            isPreparingWorkout = false
            workoutMessage = workoutCoordinator.message
            guard !snapshot.deletedRecordIDs.contains(session.id),
                  !snapshot.trainingSessions.contains(where: { $0.id == session.id && ($0.actualStart != nil || $0.actualFinish != nil) }) else {
                workoutCoordinator.discardForLibraryChange()
                UserDefaults.standard.removeObject(forKey: pendingHealthDraftKey)
                pendingHealthStart = nil
                announce("This session changed on iPhone. Review it before starting.")
                return
            }
            guard started else {
                var pending = draft
                pending.actualStart = nil; pending.actualFinish = nil
                pendingHealthStart = pending
                UserDefaults.standard.removeObject(forKey: pendingHealthDraftKey)
                announce(workoutMessage)
                sendHealthStatus()
                return
            }
            session.actualStart = workoutCoordinator.startedAt ?? session.actualStart
            session = TennisRecordConflictResolver.prepareLocalTraining(session)
            pendingHealthStart = nil
            activeTraining = session
            completedTraining = nil
            mergeTraining(session)
            UserDefaults.standard.removeObject(forKey: pendingHealthDraftKey)
            send(.upsertTraining(session))
            page = .live
            haptic(.start)
            announce(workoutMessage)
            sendHealthStatus()
            finishRemotelyCompletedWorkoutIfNeeded()
        }
        return true
    }

    func restoreWorkoutIfNeeded() {
        sendHealthStatus()
        guard pendingHealthStart == nil, !isRestoringWorkout, !isPreparingWorkout, !isFinishingWorkout else { return }
        isRestoringWorkout = true
        let libraryID = snapshot.libraryID
        Task {
            guard snapshot.libraryID == libraryID else { return }
            defer { if snapshot.libraryID == libraryID { isRestoringWorkout = false } }
            let savedDraft = UserDefaults.standard.data(forKey: pendingHealthDraftKey)
                .flatMap { try? JSONDecoder.tennisTracker.decode(PendingHealthDraft.self, from: $0) }
            let draft = savedDraft.flatMap { $0.libraryID == snapshot.libraryID ? $0.training : nil }
            let tracked = healthClient.activeTrainingID.flatMap { id in
                snapshot.trainingSessions.first { $0.id == id } ?? (draft?.id == id ? draft : nil)
            } ?? activeTraining ?? draft
            if let tracked, workoutCoordinator.state == .idle || workoutCoordinator.state == .finished {
                isPreparingWorkout = true
                await workoutCoordinator.restore(activityID: tracked.id, startedAt: tracked.actualStart ?? tracked.date,
                    useHealth: mayUseHealth(for: tracked.playerID))
                guard snapshot.libraryID == libraryID else { return }
                isPreparingWorkout = false
                workoutMessage = workoutCoordinator.message
                if tracked.actualStart == nil, tracked.actualFinish == nil, !snapshot.deletedRecordIDs.contains(tracked.id),
                   workoutCoordinator.state == .recording || workoutCoordinator.state == .paused {
                    var restored = tracked
                    restored.trackedOnWatch = true
                    restored.actualStart = workoutCoordinator.startedAt ?? tracked.actualStart
                    restored = TennisRecordConflictResolver.prepareLocalTraining(restored)
                    activeTraining = restored
                    mergeTraining(restored)
                    send(.upsertTraining(restored))
                } else if tracked.actualStart == nil {
                    workoutCoordinator.discardForLibraryChange()
                    workoutMessage = "Health recording could not be recovered. The session has not started. Retry, or start without Health."
                    pendingHealthStart = tracked
                }
            } else if let id = healthClient.activeTrainingID, snapshot.deletedRecordIDs.contains(id),
                      workoutCoordinator.state == .idle || workoutCoordinator.state == .finished {
                await workoutCoordinator.restore(activityID: id, startedAt: Date())
                guard snapshot.libraryID == libraryID else { return }
            }
            UserDefaults.standard.removeObject(forKey: pendingHealthDraftKey)
            finishRemotelyCompletedWorkoutIfNeeded()
            for id in healthClient.pendingWorkoutIDs {
                guard let training = snapshot.trainingSessions.first(where: { $0.id == id }), training.actualFinish != nil else { continue }
                if training.workout?.workoutID != nil { healthClient.acknowledgeSavedWorkout(id); continue }
                if let result = try? await healthClient.savedWorkout(activityID: id) {
                    guard snapshot.libraryID == libraryID else { return }
                    attachWorkout(result, to: id)
                    healthClient.acknowledgeSavedWorkout(id)
                }
                guard snapshot.libraryID == libraryID else { return }
            }
        }
    }

    private func finishRemotelyCompletedWorkoutIfNeeded() {
        if let id = workoutCoordinator.activityID, snapshot.deletedRecordIDs.contains(id),
           !isPreparingWorkout, !isFinishingWorkout,
           workoutCoordinator.state == .recording || workoutCoordinator.state == .paused || workoutCoordinator.state == .recordingWithoutHealth {
            finishWorkout(for: id, at: Date())
            return
        }
        guard !isPreparingWorkout, !isFinishingWorkout,
              let id = workoutCoordinator.activityID,
              let training = snapshot.trainingSessions.first(where: { $0.id == id }),
              let finishDate = training.actualFinish,
              workoutCoordinator.state == .recording || workoutCoordinator.state == .paused || workoutCoordinator.state == .recordingWithoutHealth else { return }
        finishWorkout(for: id, at: finishDate)
    }

    private func finishWorkout(for id: UUID, at date: Date) {
        guard !isFinishingWorkout else { return }
        isFinishingWorkout = true
        let libraryID = snapshot.libraryID
        Task {
            guard snapshot.libraryID == libraryID else { return }
            defer { if snapshot.libraryID == libraryID { isFinishingWorkout = false } }
            if let result = await workoutCoordinator.finish(at: date) {
                guard snapshot.libraryID == libraryID else { return }
                attachWorkout(result, to: id)
                if result.workoutID != nil { healthClient.acknowledgeSavedWorkout(id) }
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("-ui-testing-watch"),
                   ProcessInfo.processInfo.arguments.contains("-watch-health=real") {
                    nativeHealthReadback = "Saved workout was not found in HealthKit."
                    for _ in 0..<5 {
                        if let saved = try? await healthClient.savedWorkout(activityID: id),
                           let workoutID = result.workoutID, saved.workoutID == workoutID {
                            nativeHealthReadback = "Saved workout independently found in HealthKit."
                            break
                        }
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                }
                #endif
            }
            guard snapshot.libraryID == libraryID else { return }
            workoutMessage = workoutCoordinator.message
            if let training = snapshot.trainingSessions.first(where: { $0.id == id }) {
                announce(trainingSummary(training, style: .detailed) + " " + workoutMessage)
            }
        }
    }

    private func attachWorkout(_ result: TennisWorkoutResult, to id: UUID) {
        guard var training = snapshot.trainingSessions.first(where: { $0.id == id }) else { return }
        guard mayUseHealth(for: training.playerID) else { return }
        // A delayed save must not replace a previously confirmed Health relationship.
        guard training.workout?.workoutID == nil else { return }
        training.workout = result
        training = TennisRecordConflictResolver.prepareLocalTraining(training)
        if completedTraining?.id == id { completedTraining = training }
        mergeTraining(training)
        send(.upsertTraining(training))
    }

    func beginTournament(_ tournament: TournamentRecord) {
        guard !snapshot.deletedRecordIDs.contains(tournament.id) else { announce("This tournament was deleted."); return }
        guard activeTournamentID == nil || activeTournamentID == tournament.id else { page = .live; return }
        var tournament = tournament
        tournament.actualStart = tournament.actualStart ?? Date()
        tournament.actualFinish = nil
        tournament.finalResult = .inProgress
        tournament.hasExplicitStatus = true
        tournament = TennisRecordConflictResolver.prepareLocalTournament(tournament)
        activeTournamentID = tournament.id
        UserDefaults.standard.set(tournament.id.uuidString, forKey: "activeTournamentID")
        mergeTournament(tournament)
        send(.upsertTournament(tournament))
        page = .live
    }

    func finishTournament() {
        guard var tournament = snapshot.tournaments.first(where: { $0.id == activeTournamentID }) else { return }
        let beforeAchievements = TennisAchievement.earnedIDs(records: snapshot.achievementRecords, playerID: tournament.playerID)
        tournament.finalResult = .completed
        tournament.hasExplicitStatus = true
        if let start = tournament.actualStart { tournament.actualFinish = max(start, Date()) }
        tournament = TennisRecordConflictResolver.prepareLocalTournament(tournament)
        mergeTournament(tournament)
        send(.upsertTournament(tournament))
        activeTournamentID = nil
        UserDefaults.standard.removeObject(forKey: "activeTournamentID")
        announce("Tournament tracking finished.")
        sound(TennisAchievement.feedback(before: beforeAchievements, records: snapshot.achievementRecords, playerID: tournament.playerID,
            settings: snapshot.settings.sounds, otherwise: .completion))
    }

    func savePracticeResult(_ result: TennisPracticeResult) {
        guard var training = completedTraining else { return }
        training.practiceResult = result
        training = TennisRecordConflictResolver.prepareLocalTraining(training)
        completedTraining = training
        mergeTraining(training)
        send(.upsertTraining(training))
        announce("Saved practice result with training.")
    }

    func markTrainingComplete(_ id: UUID) {
        guard var training = snapshot.trainingSessions.first(where: { $0.id == id }) else { return }
        training.markDetailsComplete()
        training = TennisRecordConflictResolver.prepareLocalTraining(training)
        if completedTraining?.id == id { completedTraining = training }
        mergeTraining(training)
        send(.upsertTraining(training))
        announce("Marked complete. Saved on Watch and queued for iPhone.")
    }

    func deleteActivity(_ deletion: TennisRecordDeletion) {
        guard !isPreparingWorkout && !isFinishingWorkout else { announce("Wait for the workout to finish saving."); return }
        if activeTraining?.id == deletion.id {
            activeTraining = nil
            finishWorkout(for: deletion.id, at: Date())
        }
        if completedTraining?.id == deletion.id { completedTraining = nil }
        if activeMatch?.id == deletion.id { activeMatch = nil; pointHistory = []; persistPointHistory() }
        if activeTournamentID == deletion.id {
            activeTournamentID = nil
            UserDefaults.standard.removeObject(forKey: "activeTournamentID")
        }
        snapshot.delete(deletion)
        if let id = activeMatch?.id, snapshot.deletedRecordIDs.contains(id) { activeMatch = nil; pointHistory = []; persistPointHistory() }
        queuedCommands.removeAll {
            if case .deleteRecord = $0 { return false }
            return $0.recordID.map(snapshot.deletedRecordIDs.contains) ?? false
        }
        send(.deleteRecord(deletion))
        persistSnapshot()
        announce("Deleted on Watch. The deletion will sync to iPhone.")
    }

    @discardableResult
    func updateTrainingDetails(_ draft: TrainingSession, durationWasEdited: Bool = false, original: TrainingSession? = nil) -> Bool {
        guard let current = snapshot.trainingSessions.first(where: { $0.id == draft.id }), !snapshot.deletedRecordIDs.contains(draft.id) else {
            announce("This session is no longer available. Your unsaved changes are still shown."); return false
        }
        let beforeAchievements = TennisAchievement.earnedIDs(records: snapshot.achievementRecords, playerID: draft.playerID)
        let updated = TennisWatchRecordEdits.training(draft, current: current, durationWasEdited: durationWasEdited, original: original)
        if activeTraining?.id == updated.id { activeTraining = updated }
        if completedTraining?.id == updated.id { completedTraining = updated }
        mergeTraining(updated); send(.upsertTraining(updated))
        announce("Training details saved on Watch.")
        sound(TennisAchievement.feedback(before: beforeAchievements, records: snapshot.achievementRecords, playerID: draft.playerID,
            settings: snapshot.settings.sounds, otherwise: .save))
        return true
    }

    @discardableResult
    func savePlannedTraining(_ draft: TrainingSession) -> Bool {
        guard !snapshot.deletedRecordIDs.contains(draft.id), !snapshot.trainingSessions.contains(where: { $0.id == draft.id }),
              draft.actualStart == nil, draft.actualFinish == nil, draft.workout == nil,
              snapshot.players.contains(where: { $0.id == draft.playerID && !$0.isArchived }) else {
            announce("This practice plan is no longer available to save. Your draft is retained."); return false
        }
        var candidate = snapshot.courtLibrary
        candidate.trainingSessions.append(draft)
        if let error = CourtLibraryValidation.message(in: candidate, validateLinks: false) { announce(error); return false }
        let saved = TennisRecordConflictResolver.prepareLocalTraining(draft)
        mergeTraining(saved); send(.upsertTraining(saved))
        announce("Practice planned for \(saved.date.fullTennisDate). Saved on Watch.")
        sound(.save)
        return true
    }

    func updateMatchDetails(_ draft: MatchRecord, original: MatchRecord? = nil) {
        guard let current = snapshot.matches.first(where: { $0.id == draft.id }) else { return }
        let updated = TennisWatchRecordEdits.match(draft, current: current, original: original)
        if activeMatch?.id == updated.id { activeMatch = updated }
        mergeMatch(updated); send(.upsertMatch(updated))
        announce("Match details saved on Watch.")
        sound(.save)
    }

    func updateTrainingLinks(_ session: TrainingSession, original: Set<UUID>, selected: Set<UUID>) {
        guard snapshot.trainingSessions.contains(where: { $0.id == session.id }), !snapshot.deletedRecordIDs.contains(session.id) else { return }
        for match in TennisTrainingLinks.changes(sessionID: session.id, playerID: session.playerID, matches: snapshot.matches, original: original, selected: selected) {
            let updated = TennisRecordConflictResolver.prepareLocalMatch(match)
            if activeMatch?.id == updated.id { activeMatch = updated }
            mergeMatch(updated); send(.upsertMatch(updated))
        }
    }

    func saveRecordedMatch(_ draft: MatchRecord) {
        guard !snapshot.deletedRecordIDs.contains(draft.id), TennisManualMatchEntry.validationMessage(for: draft) == nil else { return }
        let beforeAchievements = TennisAchievement.earnedIDs(records: snapshot.achievementRecords, playerID: draft.playerID)
        let wasCompleted = snapshot.matches.first { $0.id == draft.id }?.status == .completed
        var recorded = draft
        if recorded.matchType == .singles {
            recorded.partnerID = nil; recorded.partnerName = ""
            recorded.opponent2ID = nil; recorded.opponent2Name = ""
        }
        recorded.status = .completed
        recorded.liveScore = nil
        recorded.needsDetails = recorded.yourSetsWon + recorded.opponentSetsWon == 0 && recorded.setScores.isBlank
        recorded = TennisRecordConflictResolver.prepareLocalMatch(recorded)
        mergeMatch(recorded); send(.upsertMatch(recorded))
        announce("Match result saved on Watch. " + TennisSummaryFormatter.match(recorded))
        sound(TennisAchievement.feedback(before: beforeAchievements, records: snapshot.achievementRecords, playerID: draft.playerID,
            settings: snapshot.settings.sounds, otherwise: wasCompleted ? .save : .completion))
    }

    func toggleTournamentCompletion(_ id: UUID) {
        guard !snapshot.deletedRecordIDs.contains(id),
              let current = snapshot.tournaments.first(where: { $0.id == id }) else { return }
        let updated = current.togglingCompletion()
        mergeTournament(updated)
        send(.upsertTournament(updated))
        if activeTournamentID == id {
            activeTournamentID = nil
            UserDefaults.standard.removeObject(forKey: "activeTournamentID")
        }
        announce(updated.completionAnnouncement)
        sound(updated.finalResult == .completed ? .completion : .save)
    }

    func saveTournamentRecord(_ draft: TournamentRecord) {
        guard !draft.name.isBlank, !snapshot.deletedRecordIDs.contains(draft.id) else { return }
        let beforeAchievements = TennisAchievement.earnedIDs(records: snapshot.achievementRecords, playerID: draft.playerID)
        let saved = TennisRecordConflictResolver.prepareLocalTournament(draft)
        mergeTournament(saved); send(.upsertTournament(saved))
        announce("Tournament saved on Watch.")
        sound(TennisAchievement.feedback(before: beforeAchievements, records: snapshot.achievementRecords, playerID: draft.playerID,
            settings: snapshot.settings.sounds, otherwise: .save))
    }

    func updateTournamentDetails(_ draft: TournamentRecord) {
        guard let current = snapshot.tournaments.first(where: { $0.id == draft.id }) else { return }
        let updated = TennisWatchRecordEdits.tournament(draft, current: current)
        mergeTournament(updated); send(.upsertTournament(updated))
        announce("Tournament details saved on Watch.")
        sound(.save)
    }

    func markMatchComplete(_ id: UUID) {
        guard var draft = snapshot.matches.first(where: { $0.id == id }), draft.status == .completed else { return }
        draft.needsDetails = false
        updateMatchDetails(draft)
    }

    func markTournamentComplete(_ id: UUID) {
        guard var draft = snapshot.tournaments.first(where: { $0.id == id }), draft.isCompleted else { return }
        draft.needsDetails = false
        updateTournamentDetails(draft)
    }

    func recordPoint(_ winner: PointWinner) {
        guard var match = activeMatch else {
            announce("No match in progress.")
            return
        }
        var scorer = scoringEngine(for: match)
        pointHistory.append(scoreState.snapshot)
        persistPointHistory()
        let message = scorer.awardPoint(to: winner)
        scoreState = scorer.state
        match.liveScore = scoreState.snapshot
        match.status = scoreState.isMatchComplete ? .completed : .inProgress
        match.yourSetsWon = scoreState.playerSets
        match.opponentSetsWon = scoreState.opponentSets
        match.setScores = scoreState.completedSetScores.joined(separator: ", ")
        if scoreState.isMatchComplete {
            match = TennisWatchActivityFactory.finishMatch(match, score: scoreState)
            activeMatch = nil
        } else {
            match = TennisRecordConflictResolver.prepareLocalMatch(match)
            activeMatch = match
        }
        mergeMatch(match)
        send(.upsertMatch(match))
        haptic(.click)
        announce(message)
    }

    func undoLastPoint() {
        guard var match = activeMatch else { return }
        guard let previous = pointHistory.popLast() else { announce("No point available to undo."); return }
        scoreState = TennisScoreState(snapshot: previous)
        persistPointHistory()
        match.liveScore = scoreState.snapshot
        match.yourSetsWon = scoreState.playerSets
        match.opponentSetsWon = scoreState.opponentSets
        match.setScores = scoreState.completedSetScores.joined(separator: ", ")
        match = TennisRecordConflictResolver.prepareLocalMatch(match)
        activeMatch = match
        mergeMatch(match)
        send(.upsertMatch(match))
        haptic(.retry)
        announce("Point undone. " + scoreState.spokenScore(playerName: match.playerTeam, opponentName: match.opponentSummary, suddenDeathDeuce: match.suddenDeathDeuce))
    }

    func saveMatchProgress() {
        guard var match = activeMatch else { return }
        match.liveScore = scoreState.snapshot
        match.status = .inProgress
        match = TennisRecordConflictResolver.prepareLocalMatch(match)
        activeMatch = match
        mergeMatch(match)
        send(.upsertMatch(match))
        haptic(.success)
        announce("Saved match progress.")
        sound(.save)
    }

    func startTieBreak() {
        guard var match = activeMatch else { return }
        guard !scoreState.isMatchComplete && !scoreState.isTiebreak else { return }
        var scorer = scoringEngine(for: match)
        pointHistory.append(scoreState.snapshot)
        persistPointHistory()
        announce(scorer.startTieBreak())
        scoreState = scorer.state
        match.liveScore = scoreState.snapshot
        match = TennisRecordConflictResolver.prepareLocalMatch(match)
        activeMatch = match
        mergeMatch(match)
        send(.upsertMatch(match))
        haptic(.click)
    }

    func finishMatch() {
        guard let match = activeMatch else { return }
        let beforeAchievements = TennisAchievement.earnedIDs(records: snapshot.achievementRecords, playerID: match.playerID)
        let finished = TennisWatchActivityFactory.finishMatch(match, score: scoreState)
        activeMatch = nil
        mergeMatch(finished)
        send(.upsertMatch(finished))
        haptic(.success)
        page = .recent
        announce(TennisSummaryFormatter.match(finished, tournaments: snapshot.tournaments))
        sound(TennisAchievement.feedback(before: beforeAchievements, records: snapshot.achievementRecords, playerID: match.playerID,
            settings: snapshot.settings.sounds, otherwise: .completion))
    }

    func markDetailsComplete() {
        if let match = snapshot.matches.first(where: \.needsDetails) {
            send(.markMatchDetailsComplete(match.id))
            announce("Marked match details complete.")
            return
        }
        if let session = snapshot.trainingSessions.first(where: \.needsDetails) {
            send(.markTrainingDetailsComplete(session.id))
            announce("Marked training details complete.")
            return
        }
        if let tournament = snapshot.tournaments.first(where: \.needsDetails) {
            send(.markTournamentDetailsComplete(tournament.id))
            announce("Marked tournament details complete.")
        }
    }

    func send(_ command: TennisWatchSyncCommand) {
        if let id = command.recordID { queuedCommands.removeAll { $0.recordID == id } }
        queuedCommands.append(command)
        persistQueue()
        flushQueue()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let received = session.receivedApplicationContext["snapshotData"] as? Data
        Task { @MainActor in
            if let received { self.applySnapshotData(received, authoritative: true) }
            self.flushQueue()
            self.sendHealthStatus()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.send(.requestSnapshot) }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard error != nil, let data = userInfoTransfer.userInfo["commandData"] as? Data,
              let envelope = try? JSONDecoder.tennisTracker.decode(TennisWatchCommandEnvelope.self, from: data) else { return }
        Task { @MainActor in
            guard envelope.libraryID == self.snapshot.libraryID else { return }
            self.queuedCommands.append(envelope.command)
            self.persistQueue()
            self.lastSyncStatus = "Saved on Watch. Waiting to sync with iPhone."
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in self.applySnapshotData(messageData) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = session.receivedApplicationContext[snapshotKey] as? Data else { return }
        Task { @MainActor in self.applySnapshotData(data, authoritative: true) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[snapshotKey] as? Data else { return }
        Task { @MainActor in self.applySnapshotData(data) }
    }

    private func scoringEngine(for match: MatchRecord) -> TennisScoringEngine {
        TennisScoringEngine(
            playerName: match.playerTeam,
            opponentName: match.opponentSummary,
            suddenDeathDeuce: match.suddenDeathDeuce,
            tieBreakRule: match.tieBreakRule,
            tieBreakTarget: match.tieBreakTarget,
            tieBreakWinByTwo: match.tieBreakWinByTwo,
            setsNeededToWin: match.matchFormat.setsNeededToWin,
            snapshot: scoreState.snapshot
        )
    }

    private func flushQueue() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let pending = queuedCommands
        queuedCommands.removeAll { $0.recordID == nil }
        persistQueue()
        for command in pending {
            if case .court = command, snapshot.courtProtocolVersion < 2 { continue }
            let envelope = TennisWatchCommandEnvelope(libraryID: snapshot.libraryID, command: command)
            guard let data = try? JSONEncoder.tennisTracker.encode(envelope) else { continue }
            if session.isReachable {
                session.sendMessageData(data, replyHandler: nil, errorHandler: { _ in
                    session.transferUserInfo(["commandData": data])
                })
            } else {
                session.transferUserInfo([commandKey: data])
            }
        }
    }

    private func applySnapshotData(_ data: Data, authoritative: Bool = false) {
        guard var incoming = try? JSONDecoder.tennisTracker.decode(TennisWatchSnapshot.self, from: data) else { return }
        guard libraryFence.accept(incoming.libraryID, authoritative: authoritative) else { return }
        if snapshot.libraryID != incoming.libraryID {
            workoutCoordinator.discardForLibraryChange()
            workoutStartID = nil
            isPreparingWorkout = false; isFinishingWorkout = false; isRestoringWorkout = false
            workoutMessage = ""
            pendingHealthStart = nil
            queuedCommands = []
            openNotificationRecordIDs = []
            activeTraining = nil; activeMatch = nil; completedTraining = nil; activeTournamentID = nil
            pointHistory = []; scoreState = TennisScoreState()
            snapshot = .empty
            healthClient.clearMetrics()
            let defaults = UserDefaults.standard
            for key in ["pointHistory", "activeTournamentID", "activeHealthTrainingID", "pendingHealthTrainingIDs", pendingHealthDraftKey, "pendingIntentRoute", "trackTrainingAsWorkout"] {
                defaults.removeObject(forKey: key)
            }
            if WCSession.isSupported() {
                for transfer in WCSession.default.outstandingUserInfoTransfers { transfer.cancel() }
            }
        } else if incoming.generatedAt < snapshot.generatedAt { return }
        let previousAthleteID = snapshot.court.activeAthleteID
        if let encoded = try? JSONEncoder.tennisTracker.encode(libraryFence) { UserDefaults.standard.set(encoded, forKey: "watchLibraryFence") }
        incoming.retainOpenActivities(openNotificationRecordIDs, from: snapshot)
        let previousMatch = activeMatch
        let result = TennisWatchReconciliation.reconcile(incoming: incoming, pending: queuedCommands, localDeletedIDs: snapshot.deletedRecordIDs)
        snapshot = result.snapshot
        if let previousAthleteID, let owner = snapshot.court.ownerPlayerID,
           snapshot.court.containsAthlete(previousAthleteID, coachID: owner, players: snapshot.players),
           snapshot.players.first(where: { $0.id == previousAthleteID })?.court.sports.contains(where: { $0.sport == courtSport }) == true {
            snapshot.court.activeAthleteID = previousAthleteID
            snapshot.selectedPlayerID = previousAthleteID
        }
        queuedCommands = result.pending
        persistQueue()
        lastSyncStatus = "Updated from iPhone at \(Date().formatted(date: .omitted, time: .shortened))."
        send(.snapshotReceived(incoming.generatedAt))
        if let id = activeMatch?.id {
            activeMatch = snapshot.matches.first { $0.id == id && $0.status == .inProgress }
        } else {
            activeMatch = snapshot.matches.first { $0.status == MatchStatus.inProgress && ($0.liveScore != nil || $0.court.score != nil) }
        }
        activeTraining = snapshot.trainingSessions.first(where: \.isActive)
        if previousMatch?.id != activeMatch?.id || previousMatch?.liveScore != activeMatch?.liveScore {
            pointHistory = []
            persistPointHistory()
        }
        if let id = completedTraining?.id {
            completedTraining = snapshot.trainingSessions.first { $0.id == id }
        }
        if let id = activeTournamentID, !snapshot.tournaments.contains(where: { $0.id == id && $0.finalResult == .inProgress }) {
            activeTournamentID = nil
            UserDefaults.standard.removeObject(forKey: "activeTournamentID")
        }
        if activeMatch != nil {
            if let activeMatch {
                scoreState = TennisScoreState(snapshot: activeMatch.liveScore ?? TennisScoreState().snapshot)
            }
        }
        persistSnapshot()
        finishRemotelyCompletedWorkoutIfNeeded()
        sendHealthStatus()
    }

    private func mergeMatch(_ match: MatchRecord) {
        guard !snapshot.deletedRecordIDs.contains(match.id) else { return }
        snapshot.matches.removeAll { $0.id == match.id }
        snapshot.matches.insert(match, at: 0)
        persistSnapshot()
    }

    private func mergeTraining(_ session: TrainingSession) {
        guard !snapshot.deletedRecordIDs.contains(session.id) else { return }
        snapshot.trainingSessions.removeAll { $0.id == session.id }
        snapshot.trainingSessions.insert(session, at: 0)
        persistSnapshot()
    }

    private func mergeTournament(_ tournament: TournamentRecord) {
        guard !snapshot.deletedRecordIDs.contains(tournament.id) else { return }
        var updated = snapshot
        updated.tournaments.removeAll { $0.id == tournament.id }
        updated.tournaments.insert(tournament, at: 0)
        // Notification destinations must never observe the record temporarily missing.
        snapshot = updated
        persistSnapshot()
    }

    func announce(_ message: String) {
        lastAnnouncement = message
        #if os(watchOS)
        AccessibilityNotification.Announcement(message).post()
        #endif
    }

    private func sound(_ event: TennisFeedbackEvent) {
        #if os(watchOS)
        guard WKExtension.shared().applicationState == .active else { return }
        TennisSoundPlayer.shared.feedback(event, settings: snapshot.settings.sounds)
        #endif
    }

    private func haptic(_ type: WatchHaptic) {
        guard snapshot.settings.hapticsEnabled else { return }
        #if os(watchOS)
        let watchType: WKHapticType
        switch type {
        case .start:
            watchType = .start
        case .success:
            watchType = .success
        case .click:
            watchType = .click
        case .retry:
            watchType = .retry
        }
        WKInterfaceDevice.current().play(watchType)
        #else
        _ = type
        #endif
    }

    private func loadLocalState() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "watchLibraryFence"), let saved = try? JSONDecoder.tennisTracker.decode(TennisWatchLibraryFence.self, from: data) { libraryFence = saved }
        if let data = defaults.data(forKey: localSnapshotKey),
           let saved = try? JSONDecoder.tennisTracker.decode(TennisWatchSnapshot.self, from: data),
           libraryFence.canRestoreCachedLibrary(saved.libraryID) {
            snapshot = saved
            libraryFence.current = saved.libraryID
            if let data = defaults.data(forKey: "pointHistory"), let history = try? JSONDecoder.tennisTracker.decode([TennisScoreSnapshot].self, from: data) { pointHistory = history }
            activeTournamentID = defaults.string(forKey: "activeTournamentID").flatMap(UUID.init(uuidString:))
            activeTraining = saved.trainingSessions.first(where: \.isActive)
            activeMatch = saved.matches.first { $0.status == .inProgress && ($0.liveScore != nil || $0.court.score != nil) }
            if let activeMatch { scoreState = TennisScoreState(snapshot: activeMatch.liveScore ?? TennisScoreState().snapshot) }
            lastSyncStatus = "Saved iPhone data available."
        }
        if let data = defaults.data(forKey: queuedCommandsKey),
           let saved = try? JSONDecoder.tennisTracker.decode(TennisWatchCommandQueue.self, from: data),
           snapshot.libraryID != nil, saved.libraryID == snapshot.libraryID {
            queuedCommands = saved.commands
        }
        // Replay the persisted delete command if shutdown interrupted the snapshot write.
        for case .deleteRecord(let deletion) in queuedCommands { snapshot.delete(deletion) }
        snapshot.removeDeletedRecords()
        activeTraining = snapshot.trainingSessions.first(where: \.isActive)
        if let id = activeMatch?.id, snapshot.deletedRecordIDs.contains(id) {
            activeMatch = nil; pointHistory = []; persistPointHistory()
        }
        if let id = activeTournamentID, snapshot.deletedRecordIDs.contains(id) {
            activeTournamentID = nil
            defaults.removeObject(forKey: "activeTournamentID")
        }
    }

    private func persistSnapshot() {
        snapshot.removeDeletedRecords()
        guard let data = try? JSONEncoder.tennisTracker.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: localSnapshotKey)
        do {
            if try TennisSharedSnapshotFile.write(snapshot) {
                for kind in TennisGlanceKind.allCases { WidgetCenter.shared.reloadTimelines(ofKind: kind.widgetKind) }
            }
        } catch { lastSyncStatus = "Saved on Watch. Complication update could not be saved." }
    }

    private func persistQueue() {
        let queue = TennisWatchCommandQueue(libraryID: snapshot.libraryID, commands: queuedCommands)
        guard let data = try? JSONEncoder.tennisTracker.encode(queue) else { return }
        UserDefaults.standard.set(data, forKey: queuedCommandsKey)
    }

    private func persistPointHistory() {
        if let data = try? JSONEncoder.tennisTracker.encode(pointHistory) { UserDefaults.standard.set(data, forKey: "pointHistory") }
    }
}

extension WatchTennisStore {
    var workspaceOwner: PlayerProfile? {
        snapshot.players.first { $0.id == snapshot.court.ownerPlayerID && !$0.isArchived } ??
            snapshot.players.first { $0.id == snapshot.selectedPlayerID && !$0.isArchived }
    }
    var courtSport: CourtSportSelection { workspaceOwner?.court.selected.sport ?? .tennis }
    var courtRole: CourtRole { workspaceOwner?.court.selected.role ?? .player }
    var capturingCoachID: UUID? { courtRole == .coach && snapshot.court.activeAthleteID != nil ? workspaceOwner?.id : nil }
    var roster: [PlayerProfile] {
        guard let owner = workspaceOwner else { return [] }
        return snapshot.players.filter { $0.court.coachOwnerID == owner.id && !$0.isArchived && $0.court.sports.contains { $0.sport == courtSport } }
    }
    var scopedSnapshot: TennisWatchSnapshot {
        snapshot.scoped(playerID: selectedPlayer?.id, sport: courtSport)
    }
    func mayUseHealth(for playerID: UUID) -> Bool {
        snapshot.mayUseHealth(for: playerID)
    }
    @discardableResult
    func saveCourtMutation(_ mutation: CourtWatchMutation) -> Bool {
        guard snapshot.libraryID != nil, snapshot.courtProtocolVersion == 2 else {
            announce("Open the updated Court Story app on the paired iPhone to connect this workspace. Your draft is retained."); return false
        }
        var candidate = snapshot.courtLibrary
        guard mutation.apply(to: &candidate) else { announce("This record changed or is not available in the selected detail level."); return false }
        if let error = CourtLibraryValidation.message(in: candidate, validateLinks: false) { announce(error); return false }
        snapshot.applyCourtLibrary(candidate)
        persistSnapshot()
        send(.court(mutation))
        announce("Saved on Watch. Changes are queued for iPhone.")
        return true
    }
    func selectCourtAthlete(_ id: UUID?) {
        guard let owner = workspaceOwner, id == nil || roster.contains(where: { $0.id == id }) else { return }
        snapshot.selectedPlayerID = id ?? owner.id
        snapshot.court.activeAthleteID = id
        persistSnapshot()
        announce("Recording for \(selectedPlayer?.displayName ?? owner.displayName), \(courtSport.name).")
    }
    func selectCourtSport(_ id: String) {
        guard var owner = workspaceOwner, owner.court.sports.contains(where: { $0.id == id }) else { return }
        owner.court.selectedSportID = id
        owner.court.revision += 1; owner.court.modifiedAt = Date()
        if saveCourtMutation(.profile(owner)) { selectCourtAthlete(nil) }
    }
    func selectCourtRole(_ role: CourtRole) {
        guard var owner = workspaceOwner else { return }
        var preference = owner.court.selected; preference.role = role
        guard owner.court.update(preference) else { return }
        owner.court.revision += 1; owner.court.modifiedAt = Date()
        if saveCourtMutation(.profile(owner)) { selectCourtAthlete(nil) }
    }
    func makeCourtMatch() -> MatchRecord? {
        guard let player = selectedPlayer else { return nil }
        var match = TennisWatchActivityFactory.match(player: player, kind: snapshot.settings.defaultMatchType)
        match.court = CourtActivity(player: player, coachID: capturingCoachID)
        match.configureNewCourtMatch()
        match.status = .scheduled; match.liveScore = nil; match.actualStart = nil
        return match
    }
    @discardableResult
    func saveCourtMatch(_ value: MatchRecord, showAsActive: Bool = true) -> Bool {
        guard !snapshot.deletedRecordIDs.contains(value.id), let score = value.court.score else { return false }
        if showAsActive, let activeMatch, activeMatch.id != value.id {
            announce("Finish or close the current match before starting another.")
            return false
        }
        if let error = score.validationMessage { announce(error); return false }
        var library = snapshot.courtLibrary
        library.matches.removeAll { $0.id == value.id }; library.matches.append(value)
        if let error = CourtLibraryValidation.message(in: library, validateLinks: false) { announce(error); return false }
        let saved = TennisRecordConflictResolver.prepareLocalMatch(value)
        mergeMatch(saved)
        if showAsActive || activeMatch?.id == saved.id { activeMatch = saved }
        send(.upsertMatch(saved))
        if snapshot.settings.scoreAnnouncementMode == .automatic || saved.status == .completed { announce(score.summary) }
        return true
    }
}

private enum WatchHaptic {
    case start
    case success
    case click
    case retry
}
