import Foundation

struct TennisRecordDeletion: Codable, Equatable {
    enum Kind: String, Codable { case training, match, tournament }
    var id: UUID
    var kind: Kind
    var includeLinkedMatches = false

    func apply(matches: inout [MatchRecord], training: inout [TrainingSession],
               tournaments: inout [TournamentRecord], deletedIDs: inout Set<UUID>) {
        deletedIDs.insert(id)
        if kind == .tournament && includeLinkedMatches {
            deletedIDs.formUnion(matches.filter { $0.tournamentID == id }.map(\.id))
        }
        Self.removeDeleted(matches: &matches, training: &training, tournaments: &tournaments, deletedIDs: deletedIDs)
    }

    // IDs remain tombstoned across reconnects, delayed transfers and old editors.
    static func removeDeleted(matches: inout [MatchRecord], training: inout [TrainingSession],
                              tournaments: inout [TournamentRecord], deletedIDs: Set<UUID>) {
        matches.removeAll { deletedIDs.contains($0.id) }
        training.removeAll { deletedIDs.contains($0.id) }
        tournaments.removeAll { deletedIDs.contains($0.id) }
        for index in matches.indices {
            if let id = matches[index].tournamentID, deletedIDs.contains(id) { matches[index].tournamentID = nil }
            if let id = matches[index].trainingSessionID, deletedIDs.contains(id) { matches[index].trainingSessionID = nil }
        }
        for index in training.indices {
            if let id = training[index].context.tournamentID, deletedIDs.contains(id) { training[index].context.tournamentID = nil }
        }
    }
}

extension TennisWatchSnapshot {
    mutating func delete(_ deletion: TennisRecordDeletion) {
        deletion.apply(matches: &matches, training: &trainingSessions, tournaments: &tournaments, deletedIDs: &deletedRecordIDs)
    }
    mutating func removeDeletedRecords() {
        TennisRecordDeletion.removeDeleted(matches: &matches, training: &trainingSessions, tournaments: &tournaments, deletedIDs: deletedRecordIDs)
    }
}

extension AppData {
    mutating func delete(_ deletion: TennisRecordDeletion) {
        deletion.apply(matches: &matches, training: &trainingSessions, tournaments: &tournaments, deletedIDs: &deletedRecordIDs)
    }
    mutating func removeDeletedRecords() {
        TennisRecordDeletion.removeDeleted(matches: &matches, training: &trainingSessions, tournaments: &tournaments, deletedIDs: deletedRecordIDs)
    }
}
