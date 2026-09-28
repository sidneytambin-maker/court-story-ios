import Foundation

enum TennisTrainingLinks {
    static func changes(sessionID: UUID, playerID: UUID, matches: [MatchRecord], original: Set<UUID>, selected: Set<UUID>) -> [MatchRecord] {
        matches.compactMap { match in
            guard match.playerID == playerID else { return nil }
            var updated = match
            if selected.subtracting(original).contains(match.id) {
                updated.trainingSessionID = sessionID
            } else if original.subtracting(selected).contains(match.id), match.trainingSessionID == sessionID {
                updated.trainingSessionID = nil
            } else { return nil }
            return updated == match ? nil : updated
        }
    }
}
