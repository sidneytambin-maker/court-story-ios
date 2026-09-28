import Foundation

enum TennisMatchDetailEdits {
    static func roundAndSchedule(_ draft: MatchRecord, current: MatchRecord, original: MatchRecord? = nil) -> MatchRecord {
        var updated = current
        // Only changed editor fields may replace their unchanged baseline on the latest record.
        let baseline = original ?? (draft.revision == current.revision ? current : nil)
        guard let baseline, baseline.id == current.id, draft.id == current.id else { return updated }
        if draft.matchPosition != baseline.matchPosition, current.matchPosition == baseline.matchPosition {
            updated.matchPosition = draft.matchPosition
        }
        if current.status != .inProgress, baseline.status == current.status,
           sameScheduleDate(current.date, baseline.date), current.hasStartTime == baseline.hasStartTime,
           !sameScheduleDate(draft.date, baseline.date) || draft.hasStartTime != baseline.hasStartTime {
            updated.date = draft.date
            updated.hasStartTime = draft.hasStartTime
        }
        return updated
    }

    private static func sameScheduleDate(_ lhs: Date, _ rhs: Date) -> Bool {
        // Sync carries whole seconds; comparison must not treat a wire round trip as a concurrent edit.
        lhs.timeIntervalSince1970.rounded(.down) == rhs.timeIntervalSince1970.rounded(.down)
    }
}
