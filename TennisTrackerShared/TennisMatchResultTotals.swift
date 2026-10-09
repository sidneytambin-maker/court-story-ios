import Foundation

struct TennisMatchResultTotals: Equatable {
    var singles = TennisResultTotals()
    var doubles = TennisResultTotals()

    static func metric(kind: MatchKind, result: MatchResult, stoppedWithoutWinner: Bool = false) -> String {
        prefix(kind) + "Result" + (stoppedWithoutWinner ? "Stopped" : result.rawValue)
    }

    static func build(records: [TennisAchievementRecord], playerID: UUID?) -> Self {
        guard let playerID else { return Self() }
        var totals = Self()
        var seen = Set<UUID>()
        for record in records where record.playerID == playerID && seen.insert(record.id).inserted {
            // Older snapshots have only achievement metrics. Never mix those with newer result metrics.
            let hasResults = record.metrics.contains { $0.hasPrefix("singlesResult") || $0.hasPrefix("doublesResult") }
            for kind in MatchKind.allCases {
                let key = prefix(kind) + (hasResults ? "Result" : "")
                if record.metrics.contains(key + "Stopped") {
                    if kind == .singles { totals.singles.stopped += 1 }
                    else { totals.doubles.stopped += 1 }
                    break
                }
                guard let result = MatchResult.allCases.first(where: { record.metrics.contains(key + $0.rawValue) }) else { continue }
                if kind == .singles { totals.singles.record(result) }
                else { totals.doubles.record(result) }
                break
            }
        }
        return totals
    }

    private static func prefix(_ kind: MatchKind) -> String {
        kind == .singles ? "singles" : "doubles"
    }
}
