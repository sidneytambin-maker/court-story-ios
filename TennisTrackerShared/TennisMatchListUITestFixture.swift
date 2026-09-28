#if DEBUG && targetEnvironment(simulator)
import Foundation

enum TennisMatchListUITestFixture {
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppData {
        var data = AppData()
        var player = PlayerProfile()
        player.name = "Morgan Example"
        data.players = [player]
        data.selectedPlayerID = player.id
        data.onboardingCompleted = true
        if let argument = arguments.first(where: { $0.hasPrefix("-match-list-mode=") }),
           let mode = TrackingMode(rawValue: String(argument.dropFirst("-match-list-mode=".count))) {
            data.settings.trackingMode = mode
        }
        let now = Date()
        func match(_ name: String, status: MatchStatus, days: Int) -> MatchRecord {
            var match = MatchRecord(playerID: player.id)
            match.playerName = player.name
            match.opponentName = name
            match.status = status
            match.date = Calendar.current.date(byAdding: .day, value: days, to: now)!
            match.hasStartTime = true
            match.venue = "Example Centre Court"
            match.location = "Example Town"
            return match
        }
        data.matches = [
            match("Future Scheduled", status: .scheduled, days: 4),
            match("Past Scheduled", status: .scheduled, days: -4),
            match("Live Opponent", status: .inProgress, days: -1),
            match("Future Result", status: .completed, days: 8),
            match("Past Result", status: .completed, days: -8)
        ]
        data.matches[0].customTournamentName = "Example Nationals"
        data.matches[0].matchType = .doubles
        data.matches[0].matchPosition = .semiFinal
        data.matches[0].partnerName = "Taylor Example"
        data.matches[0].opponent2Name = "Casey Example"
        // An unfinished review must stay in history, not duplicate itself under Needs Details.
        data.matches[3].needsDetails = true
        if arguments.contains("-match-list-time-order") {
            var later = match("Later 1400", status: .scheduled, days: 1)
            later.date = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: later.date)!
            var earlier = match("Earlier 1205", status: .scheduled, days: 1)
            earlier.date = Calendar.current.date(bySettingHour: 12, minute: 5, second: 0, of: earlier.date)!
            data.matches = [later, earlier]
        }
        if arguments.contains("-match-list-scheduled-only") { data.matches.removeAll { $0.status != .scheduled } }
        if arguments.contains("-match-list-finished-only") { data.matches.removeAll { $0.status != .completed } }
        if arguments.contains("-match-list-empty") { data.matches = [] }
        return data
    }
}
#endif
