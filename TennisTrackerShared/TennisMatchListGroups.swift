import Foundation

enum TennisMatchListGroup: String, CaseIterable, Identifiable {
    case inProgress, upcoming, history

    var id: String { rawValue }
    var status: MatchStatus {
        switch self {
        case .inProgress: return .inProgress
        case .upcoming: return .scheduled
        case .history: return .completed
        }
    }
    var title: String {
        switch self {
        case .inProgress: return "In progress"
        case .upcoming: return "Scheduled matches"
        case .history: return "Match history"
        }
    }
    var symbol: String {
        switch self {
        case .inProgress: return "play.circle"
        case .upcoming: return "calendar"
        case .history: return "checkmark.circle"
        }
    }
}

struct TennisMatchListGroups {
    private let matches: [MatchRecord]
    private let calendar: Calendar

    init(matches: [MatchRecord], calendar: Calendar = .current) {
        self.matches = TennisMatchChronology.ordered(matches, calendar: calendar)
        self.calendar = calendar
    }

    subscript(group: TennisMatchListGroup) -> [MatchRecord] {
        // Dates order records within a status; they never decide whether a match is finished.
        matches.filter { $0.status == group.status }
    }

    func nextUpcomingMatch(now: Date = Date()) -> MatchRecord? {
        let today = calendar.startOfDay(for: now)
        return self[.upcoming].first {
            $0.hasStartTime ? $0.date >= now : calendar.startOfDay(for: $0.date) >= today
        }
    }

    func recentHistory(limit: Int) -> [MatchRecord] {
        let history = self[.history]
        let recent = Set(history.filter { !$0.needsDetails }.suffix(max(0, limit)).map(\.id))
        return history.filter { $0.needsDetails || recent.contains($0.id) }
    }
}

enum TennisMatchChronology {
    static func ordered(_ matches: [MatchRecord], calendar: Calendar = .current) -> [MatchRecord] {
        matches.sorted {
            let firstDay = calendar.startOfDay(for: $0.date)
            let secondDay = calendar.startOfDay(for: $1.date)
            if firstDay != secondDay { return firstDay < secondDay }
            if $0.hasStartTime != $1.hasStartTime { return $0.hasStartTime }
            if $0.hasStartTime {
                let firstMinute = calendar.component(.hour, from: $0.date) * 60 + calendar.component(.minute, from: $0.date)
                let secondMinute = calendar.component(.hour, from: $1.date) * 60 + calendar.component(.minute, from: $1.date)
                if firstMinute != secondMinute { return firstMinute < secondMinute }
            }
            // Unspecified hours and hidden seconds must not reorder an otherwise equal displayed date/time.
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
