#if DEBUG && targetEnvironment(simulator)
import Foundation

enum TennisNotificationTestSupport {
    static var mode: String? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("-test-notification=") }.map { String($0.dropFirst("-test-notification=".count)) }
    }
    static func route(training: [TrainingSession], matches: [MatchRecord], tournaments: [TournamentRecord]) -> TennisActivityRoute? {
        switch mode {
        case "reflection": return training.first.map { TennisActivityRoute(kind: .training, recordID: $0.id, action: .reflection) }
        case "result": return matches.first.map { TennisActivityRoute(kind: .match, recordID: $0.id, action: .result) }
        case "tournament": return tournaments.first.map { TennisActivityRoute(kind: .tournament, recordID: $0.id) }
        case "missing": return TennisActivityRoute(kind: .training, recordID: UUID(uuidString: "00000000-0000-0000-0000-000000000029")!)
        case "weekly": return TennisActivityRoute(kind: .weekly, weekStart: TennisReportingWeek.interval(containing: Date()).start)
        default: return nil
        }
    }
}
#endif
