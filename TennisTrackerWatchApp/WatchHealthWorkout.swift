import Foundation
import HealthKit
import Combine

@MainActor
final class WatchHealthWorkout: NSObject, ObservableObject, TennisWorkoutClient, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var starting: CheckedContinuation<Void, Error>?
    private var startTimeout: Task<Void, Never>?
    private var startConfirmation = TennisWorkoutStartConfirmation()
    private var ending: CheckedContinuation<TennisWorkoutResult, Error>?
    private var finishTimeout: Task<Void, Never>?
    private var finishing = false
    private var generation = UUID()
    var onHealthStateChange: ((TennisWorkoutState, String) -> Void)?
    var isWorkoutPaused: Bool { session?.state == .paused }
    var isWorkoutRunning: Bool {
        startConfirmation.collectionStarted && (session?.state == .running || session?.state == .paused)
    }
    var workoutStartedAt: Date? { session?.startDate }
    @Published private(set) var latestHeartRate: Double?
    @Published private(set) var activeEnergy: Double?
    @Published private(set) var distanceMeters: Double?
    @Published private(set) var stepCount: Double?
    @Published private(set) var statusMessage = ""

    var activeTrainingID: UUID? {
        UserDefaults.standard.string(forKey: "activeHealthTrainingID").flatMap(UUID.init(uuidString:))
    }

    var pendingWorkoutIDs: [UUID] {
        (UserDefaults.standard.stringArray(forKey: "pendingHealthTrainingIDs") ?? []).compactMap(UUID.init(uuidString:))
    }

    func acknowledgeSavedWorkout(_ id: UUID) {
        UserDefaults.standard.set(pendingWorkoutIDs.filter { $0 != id }.map(\.uuidString), forKey: "pendingHealthTrainingIDs")
        if activeTrainingID == id { UserDefaults.standard.removeObject(forKey: "activeHealthTrainingID") }
    }

    var accessDescription: String { workoutAuthorization.description }

    var workoutAuthorization: TennisWorkoutAuthorization {
        guard available else { return .unavailable }
        switch healthStore.authorizationStatus(for: .workoutType()) {
        case .sharingAuthorized: return .authorized
        case .sharingDenied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    var available: Bool {
        Bundle.main.object(forInfoDictionaryKey: "TennisHealthEnabled") as? Bool == true && HKHealthStore.isHealthDataAvailable()
    }

    func clearMetrics() {
        latestHeartRate = nil
        activeEnergy = nil
        distanceMeters = nil
        stepCount = nil
        statusMessage = ""
    }

    func discardForLibraryChange() {
        generation = UUID()
        failWorkout(TennisWorkoutFailure.notRunning)
        clearMetrics()
    }

    func requestPermission() async throws -> Bool {
        guard available else { return false }
        if workoutAuthorization == .authorized { return true }
        if workoutAuthorization == .denied { return false }
        let workout = HKObjectType.workoutType()
        let heart = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        let distance = HKQuantityType(.distanceWalkingRunning)
        let steps = HKQuantityType(.stepCount)
        let read: Set<HKObjectType> = [workout, heart, energy, distance, steps]
        do {
            try await healthStore.requestAuthorization(toShare: [workout, heart, energy, distance, steps], read: read)
        } catch { throw TennisWorkoutFailure.permissionRequestFailed }
        // Request completion is not a grant. Only workout write access gates startup.
        return healthStore.authorizationStatus(for: workout) == .sharingAuthorized
    }

    func begin(activityID: UUID, at date: Date) async throws {
        let date = max(date, Date())
        guard available else { throw TennisWorkoutFailure.unavailable }
        guard workoutAuthorization == .authorized else {
            throw workoutAuthorization == .denied ? TennisWorkoutFailure.savingDenied : TennisWorkoutFailure.permissionNotDetermined
        }
        guard session == nil else { throw TennisWorkoutFailure.alreadyRunning }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .tennis
        configuration.locationType = .unknown
        let session: HKWorkoutSession
        do { session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration) }
        catch { throw startFailure(for: error) }
        let builder = session.associatedWorkoutBuilder()
        session.delegate = self
        builder.delegate = self
        builder.dataSource = dataSource(configuration: configuration)
        self.session = session
        self.builder = builder
        finishing = false
        startConfirmation = TennisWorkoutStartConfirmation()
        latestHeartRate = nil
        activeEnergy = nil
        distanceMeters = nil
        stepCount = nil
        statusMessage = "Starting tennis workout."
        UserDefaults.standard.set(activityID.uuidString, forKey: "activeHealthTrainingID")
        UserDefaults.standard.set(Array(Set(pendingWorkoutIDs + [activityID])).map(\.uuidString), forKey: "pendingHealthTrainingIDs")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            starting = continuation
            startTimeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 20_000_000_000) }
                catch { return }
                guard let self, self.session === session, self.starting != nil else { return }
                self.failWorkout(TennisWorkoutFailure.startTimedOut)
            }
            session.startActivity(with: date)
            Task { @MainActor in
                do {
                    try await builder.addMetadata([HKMetadataKeyExternalUUID: activityID.uuidString])
                    guard self.session === session, self.builder === builder else { return }
                    try await builder.beginCollection(at: date)
                    guard self.session === session, self.builder === builder else { return }
                    self.startConfirmation.collectionStarted = true
                    self.confirmStartedWorkout()
                } catch {
                    guard self.session === session else { return }
                    self.failWorkout(self.startFailure(for: error))
                }
            }
        }
    }

    func recover(activityID: UUID) async throws -> Bool {
        guard available, activeTrainingID == activityID else { return false }
        let token = generation
        if let session {
            return builder?.startDate != nil && (session.state == .running || session.state == .paused)
        }
        guard let recovered = try await healthStore.recoverActiveWorkoutSession(),
              recovered.state == .running || recovered.state == .paused else { return false }
        guard generation == token, activeTrainingID == activityID else {
            recovered.associatedWorkoutBuilder().discardWorkout()
            recovered.end()
            return false
        }
        session = recovered
        builder = recovered.associatedWorkoutBuilder()
        recovered.delegate = self
        builder?.delegate = self
        builder?.dataSource = dataSource(configuration: recovered.workoutConfiguration)
        guard builder?.startDate != nil else {
            failWorkout(TennisWorkoutFailure.interrupted)
            return false
        }
        finishing = false
        startConfirmation.collectionStarted = true
        startConfirmation.sessionIsRunning = recovered.state == .running
        statusMessage = recovered.state == .paused ? "Health workout paused." : "Health workout recovered and recording."
        return true
    }

    func savedWorkout(activityID: UUID) async throws -> TennisWorkoutResult? {
        guard available else { return nil }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [activityID.uuidString]),
            HKQuery.predicateForObjects(from: HKSource.default())
        ])
        let workout: HKWorkout? = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first as? HKWorkout) }
            }
            healthStore.execute(query)
        }
        guard let workout else { return nil }
        return TennisWorkoutResult(workoutID: workout.uuid, durationSeconds: workout.duration,
            averageHeartRate: workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
            activeEnergyKcal: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
            peakHeartRate: workout.statistics(for: HKQuantityType(.heartRate))?.maximumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
            distanceMeters: workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()),
            stepCount: workout.statistics(for: HKQuantityType(.stepCount))?.sumQuantity()?.doubleValue(for: .count()))
    }

    func finish(at date: Date) async throws -> TennisWorkoutResult {
        guard let session, builder != nil, starting == nil, ending == nil,
              session.state == .running || session.state == .paused || session.state == .stopped else {
            throw TennisWorkoutFailure.notRunning
        }
        return try await withCheckedThrowingContinuation { continuation in
            ending = continuation
            statusMessage = "Saving tennis workout."
            if session.state == .stopped {
                Task { await self.saveEndedWorkout(at: session.endDate ?? date) }
            } else { session.stopActivity(with: date) }
            finishTimeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 30_000_000_000) }
                catch { return }
                guard let self, self.ending != nil else { return }
                self.failWorkout(TennisWorkoutFailure.saveTimedOut)
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            self.startConfirmation.sessionIsRunning = toState == .running
            switch toState {
            case .running:
                if self.starting != nil { self.confirmStartedWorkout() }
                else if self.ending == nil {
                    self.statusMessage = "Health workout recording. Measurements appear when available."
                    self.onHealthStateChange?(.recording, self.statusMessage)
                }
            case .paused:
                self.latestHeartRate = nil
                self.statusMessage = "Health workout paused. Session timing continues."
                self.onHealthStateChange?(.paused, self.statusMessage)
            case .stopped:
                if self.ending != nil { await self.saveEndedWorkout(at: date) }
                else { self.failWorkout(self.starting == nil ? TennisWorkoutFailure.interrupted : TennisWorkoutFailure.startFailed) }
            case .ended:
                self.failWorkout(self.starting == nil ? TennisWorkoutFailure.interrupted : TennisWorkoutFailure.startFailed)
            default: break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            self.failWorkout(self.starting == nil ? TennisWorkoutFailure.interrupted : self.startFailure(for: error))
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            guard self.builder === workoutBuilder, self.session?.state == .running else { return }
            if let type = HKQuantityType.quantityType(forIdentifier: .heartRate),
               let quantity = workoutBuilder.statistics(for: type)?.mostRecentQuantity() {
                self.latestHeartRate = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            }
            if let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
               let quantity = workoutBuilder.statistics(for: type)?.sumQuantity() {
                self.activeEnergy = quantity.doubleValue(for: .kilocalorie())
            }
            self.distanceMeters = workoutBuilder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
            self.stepCount = workoutBuilder.statistics(for: HKQuantityType(.stepCount))?.sumQuantity()?.doubleValue(for: .count())
        }
    }

    private func saveEndedWorkout(at date: Date) async {
        guard let builder, !finishing else { return }
        finishing = true
        do {
            try await builder.endCollection(at: date)
            guard self.builder === builder else { return }
            let heartType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
            let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
            let average = builder.statistics(for: heartType)?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            let energy = builder.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
            let peak = builder.statistics(for: heartType)?.maximumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            let distance = builder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
            let steps = builder.statistics(for: HKQuantityType(.stepCount))?.sumQuantity()?.doubleValue(for: .count())
            let workout = try await builder.finishWorkout()
            guard self.builder === builder else { return }
            // A successful save may return no sample while the Watch is locked.
            ending?.resume(returning: TennisWorkoutResult(workoutID: workout?.uuid, durationSeconds: workout?.duration ?? builder.elapsedTime,
                averageHeartRate: average, activeEnergyKcal: energy, peakHeartRate: peak, distanceMeters: distance, stepCount: steps))
            statusMessage = workout == nil ? "Health finished saving. Workout link pending until available." : "Tennis workout saved."
        } catch {
            guard self.builder === builder else { return }
            failWorkout(error)
            return
        }
        finishTimeout?.cancel()
        finishTimeout = nil
        ending = nil
        UserDefaults.standard.removeObject(forKey: "activeHealthTrainingID")
        let previousSession = session
        self.session = nil; self.builder = nil
        previousSession?.end()
    }

    private func failWorkout(_ error: Error) {
        let wasStarting = starting != nil
        let wasSaving = ending != nil
        let activityID = activeTrainingID
        startTimeout?.cancel()
        startTimeout = nil
        starting?.resume(throwing: error)
        starting = nil
        statusMessage = wasStarting ? error.localizedDescription
            : wasSaving ? "Session timing kept. Health workout save was not confirmed."
            : TennisWorkoutFailure.interrupted.localizedDescription
        finishTimeout?.cancel()
        finishTimeout = nil
        ending?.resume(throwing: error)
        ending = nil
        let previousSession = session
        builder?.discardWorkout()
        builder = nil
        session = nil
        UserDefaults.standard.removeObject(forKey: "activeHealthTrainingID")
        previousSession?.end()
        latestHeartRate = nil; activeEnergy = nil; distanceMeters = nil; stepCount = nil
        if wasStarting, let activityID { acknowledgeSavedWorkout(activityID) }
        onHealthStateChange?(.recordingWithoutHealth, statusMessage)
    }

    private func confirmStartedWorkout() {
        guard startConfirmation.isReady, session?.state == .running, let starting else { return }
        startTimeout?.cancel()
        startTimeout = nil
        self.starting = nil
        statusMessage = "Health workout recording. Measurements appear when available."
        starting.resume()
    }

    private func startFailure(for error: Error) -> TennisWorkoutFailure {
        guard let healthError = error as? HKError else { return .startFailed }
        switch healthError.code {
        case .errorAuthorizationDenied:
            // A quantity write denial does not imply denial of workout saving or read access.
            return workoutAuthorization == .denied ? .savingDenied : .startFailed
        case .errorAuthorizationNotDetermined:
            return workoutAuthorization == .notDetermined ? .permissionNotDetermined : .startFailed
        case .errorAnotherWorkoutSessionStarted: return .alreadyRunning
        case .errorHealthDataUnavailable, .errorHealthDataRestricted: return .unavailable
        default: return .startFailed
        }
    }

    private func dataSource(configuration: HKWorkoutConfiguration) -> HKLiveWorkoutDataSource {
        let source = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        // Use actual Watch samples in this workout, never daily totals or estimated steps.
        let watchSamples = HKQuery.predicateForObjects(from: Set([HKDevice.local()]))
        source.enableCollection(for: HKQuantityType(.distanceWalkingRunning), predicate: watchSamples)
        source.enableCollection(for: HKQuantityType(.stepCount), predicate: watchSamples)
        return source
    }
}
