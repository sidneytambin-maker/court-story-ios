import Foundation

extension TennisWatchSyncCommand {
    var recordID: UUID? {
        switch self {
        case .court(let value): return value.id
        case .upsertMatch(let value): return value.id
        case .upsertTraining(let value): return value.id
        case .upsertTournament(let value): return value.id
        case .deleteRecord(let value): return value.id
        default: return nil
        }
    }
}

enum TennisWatchReconciliation {
    static func reconcile(incoming: TennisWatchSnapshot, pending: [TennisWatchSyncCommand], localDeletedIDs: Set<UUID> = []) -> (snapshot: TennisWatchSnapshot, pending: [TennisWatchSyncCommand]) {
        var snapshot = incoming
        snapshot.deletedRecordIDs.formUnion(localDeletedIDs)
        var unacknowledged: [TennisWatchSyncCommand] = []
        for command in pending {
            var pendingCommand = command
            if case .deleteRecord = command {} else if let id = command.recordID, snapshot.deletedRecordIDs.contains(id) { continue }
            let acknowledged: Bool
            switch command {
            case .court(let mutation):
                var library = snapshot.courtLibrary
                acknowledged = mutation.isAcknowledged(in: library)
                if !acknowledged {
                    _ = mutation.apply(to: &library)
                    snapshot.applyCourtLibrary(library)
                }
            case .deleteRecord(let deletion):
                acknowledged = incoming.deletedRecordIDs.contains(deletion.id)
                snapshot.delete(deletion)
            case .upsertMatch(let record):
                acknowledged = snapshot.matches.contains { $0.id == record.id && TennisRecordConflictResolver.shouldReplace(incomingRevision: $0.revision, incomingModifiedAt: $0.modifiedAt, existingRevision: record.revision, existingModifiedAt: record.modifiedAt) }
                if !acknowledged { snapshot.matches.removeAll { $0.id == record.id }; snapshot.matches.insert(record, at: 0) }
            case .upsertTraining(let record):
                if let index = snapshot.trainingSessions.firstIndex(where: { $0.id == record.id }) {
                    let received = snapshot.trainingSessions[index]
                    let merged = TennisRecordConflictResolver.mergeTraining(incoming: received, existing: record)
                    acknowledged = merged == received
                    snapshot.trainingSessions[index] = merged
                    pendingCommand = .upsertTraining(merged)
                } else {
                    acknowledged = false
                    snapshot.trainingSessions.insert(record, at: 0)
                }
            case .upsertTournament(let record):
                acknowledged = snapshot.tournaments.contains { $0.id == record.id && TennisRecordConflictResolver.shouldReplace(incomingRevision: $0.revision, incomingModifiedAt: $0.modifiedAt, existingRevision: record.revision, existingModifiedAt: record.modifiedAt) }
                if !acknowledged { snapshot.tournaments.removeAll { $0.id == record.id }; snapshot.tournaments.insert(record, at: 0) }
            default: acknowledged = false
            }
            if !acknowledged { unacknowledged.append(pendingCommand) }
        }
        snapshot.removeDeletedRecords()
        return (snapshot, unacknowledged)
    }
}
