import Foundation
import Combine

@MainActor
protocol TennisWorkoutClient: AnyObject {
    var available: Bool { get }
    var workoutAuthorization: TennisWorkoutAuthorization { get }
    var isWorkoutRunning: Bool { get }
    var isWorkoutPaused: Bool { get }
    var workoutStartedAt: Date? { get }
    var onHealthStateChange: ((TennisWorkoutState, String) -> Void)? { get set }
    func requestPermission() async throws -> Bool
    func begin(activityID: UUID, at date: Date) async throws
    func finish(at date: Date) async throws -> TennisWorkoutResult
    func recover(activityID: UUID) async throws -> Bool
    func discardForLibraryChange()
}

extension TennisWorkoutClient {
    func recover(activityID: UUID) async throws -> Bool { false }
    func discardForLibraryChange() {}
}

enum TennisWorkoutState: Equatable {
    case idle, authorizing, starting, startFailed, recording, paused, recordingWithoutHealth, finishing, finished
}

@MainActor
final class TennisWorkoutCoordinator: ObservableObject {
    @Published private(set) var state: TennisWorkoutState = .idle
    @Published private(set) var message = ""
    private let client: TennisWorkoutClient
    private(set) var startedAt: Date?
    private var generation = UUID()
    private(set) var activityID: UUID?

    init(client: TennisWorkoutClient) {
        self.client = client
        client.onHealthStateChange = { [weak self] state, message in
            guard let self, self.state == .recording || self.state == .paused else { return }
            self.state = state
            self.message = message
        }
    }

    func discardForLibraryChange() {
        generation = UUID()
        client.discardForLibraryChange()
        startedAt = nil; activityID = nil; state = .idle; message = ""
    }

    func cancelStart() {
        guard state == .authorizing || state == .starting else { return }
        discardForLibraryChange()
        message = "Workout start cancelled. No session was recorded."
    }

    @discardableResult
    func start(useHealth: Bool, activityID: UUID = UUID(), at date: Date = Date()) async -> Bool {
        guard state == .idle || state == .finished || state == .startFailed else { return false }
        generation = UUID()
        let token = generation
        startedAt = date
        self.activityID = activityID
        guard useHealth else {
            state = .recordingWithoutHealth
            message = "Session timing started without Health."
            return true
        }
        state = .authorizing
        message = "Checking Health workout access."
        do {
            guard client.available else { throw TennisWorkoutFailure.unavailable }
            switch client.workoutAuthorization {
            case .denied: throw TennisWorkoutFailure.savingDenied
            case .unavailable: throw TennisWorkoutFailure.unavailable
            case .authorized, .notDetermined:
                // HealthKit decides whether any of the current types need a sheet.
                // Existing workout write access does not cover newly requested types.
                let allowed = try await client.requestPermission()
                guard token == generation else { return false }
                guard allowed, client.workoutAuthorization == .authorized else {
                    throw client.workoutAuthorization == .denied
                        ? TennisWorkoutFailure.savingDenied : TennisWorkoutFailure.permissionNotDetermined
                }
            }
            state = .starting
            message = "Starting Health workout."
            try await client.begin(activityID: activityID, at: date)
            guard token == generation else { return false }
            guard client.isWorkoutRunning else { throw TennisWorkoutFailure.startFailed }
            startedAt = client.workoutStartedAt ?? date
            state = client.isWorkoutPaused ? .paused : .recording
            message = client.isWorkoutPaused ? "Health workout paused." : "Health workout recording. Measurements appear when available."
            return true
        } catch {
            guard token == generation else { return false }
            state = .startFailed
            message = (error as? TennisWorkoutFailure)?.errorDescription ?? TennisWorkoutFailure.startFailed.localizedDescription
            startedAt = nil
            self.activityID = nil
            return false
        }
    }

    func restore(activityID: UUID, startedAt: Date, useHealth: Bool = true) async {
        guard state == .idle || state == .finished else { return }
        let token = generation
        self.activityID = activityID
        self.startedAt = startedAt
        state = .authorizing
        do {
            let recovered = useHealth && client.available ? try await client.recover(activityID: activityID) : false
            guard token == generation else { return }
            if recovered { self.startedAt = client.workoutStartedAt ?? startedAt }
            state = recovered ? (client.isWorkoutPaused ? .paused : .recording) : .recordingWithoutHealth
            message = recovered ? (client.isWorkoutPaused ? "Health workout recovered paused." : "Health workout recovered and recording.")
                : "Training restored without an active Health workout."
        } catch {
            guard token == generation else { return }
            state = .recordingWithoutHealth
            message = "Health workout recovery failed. Tennis tracking continues."
        }
    }

    func finish(at date: Date = Date()) async -> TennisWorkoutResult? {
        guard state == .recording || state == .paused || state == .recordingWithoutHealth else { return nil }
        let token = generation
        let hasHealth = state == .recording || state == .paused
        state = .finishing
        defer { if token == generation { state = .finished } }
        if hasHealth {
            do {
                let result = try await client.finish(at: date)
                guard token == generation else { return nil }
                message = result.workoutID == nil
                    ? "Health finished saving. Workout link pending until available."
                    : "Tennis workout saved."
                return result
            } catch {
                guard token == generation else { return nil }
                message = "Training saved. The Health workout could not be saved."
            }
        } else { message = "Training saved without Health data." }
        return TennisWorkoutResult(durationSeconds: max(0, date.timeIntervalSince(startedAt ?? date)))
    }
}

struct TennisMotionSample: Codable, Equatable {
    var timestamp: TimeInterval
    var accelerationX: Double
    var accelerationY: Double
    var accelerationZ: Double
    var rotationX: Double
    var rotationY: Double
    var rotationZ: Double
}

struct TennisLabeledMotionSession: Codable, Equatable {
    var activityID: UUID
    var trainingType: TrainingType
    var startedAt: Date
    var samples: [TennisMotionSample]
    // A training label is supplied by the player, never an inferred stroke classification.
    var labelSource = "Player-selected training type"
}
