#if DEBUG && targetEnvironment(simulator)
import Foundation

// UI fault injection exercises the real store/coordinator and navigation. It is
// not evidence of sensor collection or a physical HealthKit save.
@MainActor
final class WatchWorkoutTestClient: TennisWorkoutClient {
    let mode: String
    var available = true
    var workoutAuthorization: TennisWorkoutAuthorization
    var isWorkoutRunning = false
    var isWorkoutPaused = false
    var workoutStartedAt: Date?
    var onHealthStateChange: ((TennisWorkoutState, String) -> Void)?
    private var attempts = 0
    private var generation = UUID()

    init(mode: String) {
        self.mode = mode
        workoutAuthorization = mode == "denied" ? .denied : mode == "new-access" ? .notDetermined : .authorized
    }

    static func makeIfRequested() -> (any TennisWorkoutClient)? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-ui-testing-watch"),
              let value = arguments.first(where: { $0.hasPrefix("-watch-health=") }) else { return nil }
        let mode = String(value.dropFirst("-watch-health=".count))
        if mode == "real" { return nil }
        return WatchWorkoutTestClient(mode: mode)
    }

    func requestPermission() async throws -> Bool {
        if workoutAuthorization == .denied { return false }
        workoutAuthorization = .authorized
        return true
    }

    func begin(activityID: UUID, at date: Date) async throws {
        attempts += 1
        if mode == "retry" && attempts == 1 { throw TennisWorkoutFailure.startTimedOut }
        let token = generation
        if mode == "pending" { try await Task.sleep(nanoseconds: 3_000_000_000) }
        guard generation == token else { throw CancellationError() }
        workoutStartedAt = date
        isWorkoutRunning = true
    }

    func finish(at date: Date) async throws -> TennisWorkoutResult {
        guard isWorkoutRunning else { throw TennisWorkoutFailure.notRunning }
        isWorkoutRunning = false
        if mode == "save-failure" { throw TennisWorkoutFailure.saveTimedOut }
        return TennisWorkoutResult(workoutID: UUID(), durationSeconds: max(0, date.timeIntervalSince(workoutStartedAt ?? date)))
    }

    func discardForLibraryChange() {
        generation = UUID()
        isWorkoutRunning = false
        workoutStartedAt = nil
    }
}
#endif
