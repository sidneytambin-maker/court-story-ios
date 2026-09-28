#if DEBUG && targetEnvironment(simulator)
import Foundation

enum TennisTournamentUITestFixture {
    static func make() -> AppData {
        var data = AppData()
        var player = PlayerProfile()
        player.name = "Morgan Example"
        data.players = [player]
        data.selectedPlayerID = player.id
        data.onboardingCompleted = true
        var tournament = TournamentRecord(playerID: player.id)
        tournament.name = "Meadow Cup"
        let today = Calendar.current.startOfDay(for: Date())
        tournament.date = Calendar.current.date(byAdding: .day, value: -2, to: today)!
        tournament.endDate = tournament.date
        tournament.stageReached = .roundRobin
        // Exercise legacy date-based completion while the raw status is still Entered.
        tournament.finalResult = .entered
        tournament.hasExplicitStatus = false
        data.tournaments = [tournament]
        return data
    }
}
#endif
