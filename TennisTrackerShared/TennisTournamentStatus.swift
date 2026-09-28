import Foundation

extension TournamentRecord {
    var statusText: String {
        isCompleted && finalResult == .entered ? TournamentResult.completed.rawValue : finalResult.rawValue
    }

    var completionActionTitle: String {
        isCompleted ? "Mark Tournament Entered" : "Mark Tournament Complete"
    }

    var completionActionSymbol: String {
        isCompleted ? "arrow.uturn.backward" : "checkmark.circle"
    }

    var statusSymbol: String {
        switch finalResult {
        case .inProgress: return "play.circle"
        case .withdrawn: return "minus.circle"
        default: return isCompleted ? "checkmark.circle.fill" : "calendar"
        }
    }

    var completionAnnouncement: String {
        "Tournament \(name.fallback("unnamed tournament")) marked \(finalResult == .completed ? "complete" : "entered")."
    }

    func togglingCompletion(now: Date = Date()) -> TournamentRecord {
        var updated = self
        updated.finalResult = isCompleted ? .entered : .completed
        updated.hasExplicitStatus = true
        if updated.finalResult == .completed, finalResult == .inProgress,
           let start = actualStart, actualFinish == nil {
            updated.actualFinish = max(start, now)
        }
        return TennisRecordConflictResolver.prepareLocalTournament(updated, now: now)
    }
}
