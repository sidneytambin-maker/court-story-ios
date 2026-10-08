import Foundation

// HealthKit exposes write authorization only. Missing samples cannot reveal read permission.
enum TennisWorkoutAuthorization: String, Codable, Equatable {
    case unavailable, notDetermined, denied, authorized

    var description: String {
        switch self {
        case .unavailable: return "Unavailable on this Watch"
        case .notDetermined: return "Workout saving not yet requested"
        case .denied: return "Workout saving not allowed"
        case .authorized: return "Workout saving allowed"
        }
    }

    func useHealthByDefault(preference: Bool?) -> Bool {
        preference ?? (self != .unavailable)
    }
}

struct TennisWorkoutStartConfirmation {
    var sessionIsRunning = false
    var collectionStarted = false
    var isReady: Bool { sessionIsRunning && collectionStarted }
}

enum TennisWorkoutFailure: LocalizedError {
    case unavailable, savingDenied, permissionNotDetermined, permissionRequestFailed
    case alreadyRunning, notRunning, startFailed, startTimedOut, interrupted, saveTimedOut

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Health workouts are unavailable on this Watch. You can start without Health."
        case .savingDenied:
            return "Workout saving is turned off for Court Story. Allow Workouts in Health permissions, then retry, or start without Health."
        case .permissionNotDetermined:
            return "Workout saving permission has not been confirmed. Retry to review Health access, or start without Health."
        case .permissionRequestFailed:
            return "Health access could not be requested. Unlock your Watch and retry, or start without Health."
        case .alreadyRunning:
            return "Another Health workout is active. End that workout, then retry."
        case .notRunning, .interrupted:
            return "Health recording stopped. Session timing continues without new Health measurements."
        case .startFailed:
            return "The Health workout could not start. Unlock your Watch, check for another active workout and retry, or start without Health."
        case .startTimedOut:
            return "Health did not confirm that recording started. Retry, or start without Health."
        case .saveTimedOut:
            return "Health did not confirm the workout save. Your session timing is kept; the Health link will be checked again."
        }
    }
}
