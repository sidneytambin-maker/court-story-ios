import Foundation

enum TennisScheduling {
    static func nearbyTraining(in snapshot: TennisWatchSnapshot, now: Date = Date()) -> [TrainingSession] {
        guard let playerID = snapshot.selectedPlayerID ?? snapshot.players.first?.id else { return [] }
        return snapshot.trainingSessions.filter {
            $0.playerID == playerID && !snapshot.deletedRecordIDs.contains($0.id) && $0.hasStartTime
                && $0.actualStart == nil && $0.actualFinish == nil && abs($0.date.timeIntervalSince(now)) <= 15 * 60
        }.sorted {
            let first = abs($0.date.timeIntervalSince(now)), second = abs($1.date.timeIntervalSince(now))
            return first == second ? $0.id.uuidString < $1.id.uuidString : first < second
        }
    }

    static func fiveMinuteDate(_ date: Date, calendar: Calendar = .current) -> Date {
        let minute = calendar.component(.minute, from: date)
        let start = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        return start.addingTimeInterval(Double(((minute + 2) / 5) * 5 - minute) * 60)
    }
}
