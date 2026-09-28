import Foundation

enum TennisTrainingDurationSource: String, Codable {
    case recorded, manual
}

extension TrainingSession {
    var effectiveDurationSeconds: TimeInterval {
        if durationSource == .manual, durationMinutes > 0 { return Double(durationMinutes) * 60 }
        if let seconds = workout?.durationSeconds, seconds.isFinite, seconds >= 0 { return seconds }
        if let start = actualStart, let finish = actualFinish {
            let seconds = finish.timeIntervalSince(start)
            if seconds.isFinite { return max(0, seconds) }
        }
        return Double(max(0, durationMinutes)) * 60
    }

    mutating func setManualDuration(minutes: Int, at date: Date = Date()) {
        guard minutes > 0 else { return }
        durationMinutes = minutes
        if actualStart != nil || actualFinish != nil || workout != nil {
            durationSource = .manual
            durationEditedAt = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        } else {
            durationSource = .recorded
            durationEditedAt = nil
        }
    }

    mutating func retainManualDuration(from other: TrainingSession) {
        guard id == other.id, other.durationSource == .manual, other.durationMinutes > 0 else { return }
        if durationSource == .manual, durationMinutes > 0,
           (durationEditedAt ?? modifiedAt) >= (other.durationEditedAt ?? other.modifiedAt) { return }
        durationMinutes = other.durationMinutes
        durationSource = .manual
        durationEditedAt = other.durationEditedAt ?? other.modifiedAt
    }

    mutating func migrateLegacyDuration() {
        // Watch completion stored ceil(elapsed / 60), independently of Health's active duration.
        // Allow a minute of rounding drift before inferring an existing saved correction.
        guard durationMinutes > 0, let start = actualStart, let finish = actualFinish else { return }
        let elapsed = finish.timeIntervalSince(start)
        guard elapsed.isFinite, elapsed >= 0,
              abs(Double(durationMinutes) - max(1, ceil(elapsed / 60))) > 1 else { return }
        setManualDuration(minutes: durationMinutes, at: modifiedAt)
    }
}
