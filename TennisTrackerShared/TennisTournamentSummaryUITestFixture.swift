#if DEBUG && targetEnvironment(simulator)
import Foundation

enum TennisTournamentSummaryUITestFixture {
    static func make(now: Date = Date()) -> AppData {
        var data = AppData()
        var player = PlayerProfile(); player.name = "Morgan Example"
        data.players = [player]; data.selectedPlayerID = player.id; data.onboardingCompleted = true
        data.settings.trackingMode = .basic
        data.settings.showUpcomingTournaments = true
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now))!
        var tournament = TournamentRecord(playerID: player.id)
        tournament.name = "Example Scheduled Open"
        tournament.date = day; tournament.endDate = day
        tournament.finalResult = .entered; tournament.hasExplicitStatus = true
        data.tournaments = [tournament]
        data.matches = [12, 14].map { hour in
            var match = MatchRecord(playerID: player.id)
            match.playerName = player.name; match.opponentName = "Example Opponent \(hour)"
            match.status = .scheduled; match.tournamentID = tournament.id
            match.date = calendar.date(byAdding: .hour, value: hour, to: day)!
            match.hasStartTime = true
            return match
        }
        return data
    }
}
#endif
