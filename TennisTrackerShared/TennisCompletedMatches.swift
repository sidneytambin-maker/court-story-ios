import Foundation

struct TennisCompletedMatch: Equatable {
    let id: UUID
    let kind: MatchKind
    let result: MatchResult
    let date: Date
    let trainingSessionID: UUID?

    static func collect(matches: [MatchRecord], training: [TrainingSession], now: Date = Date()) -> [Self] {
        var seen = Set<UUID>()
        let completed = matches.filter { $0.status == .completed && seen.insert($0.id).inserted }
        var results = completed.map { Self(id: $0.id, kind: $0.matchType, result: $0.result, date: $0.date, trainingSessionID: $0.trainingSessionID) }
        let linkedSessions = Set(matches.compactMap(\.trainingSessionID))
        // A session-level legacy score is a match only when no linked match already represents it.
        for session in training where session.isRecordedTraining(at: now) && !linkedSessions.contains(session.id) {
            guard let practice = session.practiceResult, seen.insert(session.id).inserted else { continue }
            results.append(Self(id: session.id, kind: practice.kind, result: practice.result, date: session.actualStart ?? session.date, trainingSessionID: session.id))
        }
        return results
    }
}
