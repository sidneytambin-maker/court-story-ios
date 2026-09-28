#if DEBUG && targetEnvironment(simulator)
import Foundation

enum TennisRegressionFixtures {
    static func manualDurationCorrection(alreadyCorrected: Bool = false) -> AppData {
        var data = AppData()
        var player = PlayerProfile(); player.name = "Alex"
        data.players = [player]; data.selectedPlayerID = player.id
        data.onboardingCompleted = true
        let finish = Date().addingTimeInterval(-600)
        let started = TennisWatchActivityFactory.trainingSession(playerID: player.id, startDate: finish.addingTimeInterval(-21_120))
        var training = TennisWatchActivityFactory.finishTrainingSession(started, finishDate: finish)
        training.focus = "Serve and return"
        training.workout = TennisWorkoutResult(workoutID: UUID(), durationSeconds: 21_120,
            averageHeartRate: 120, activeEnergyKcal: 900, peakHeartRate: 160, distanceMeters: 3000, stepCount: 4500)
        if alreadyCorrected {
            training.durationMinutes = 120
            training.migrateLegacyDuration()
        }
        data.trainingSessions = [training]
        return data
    }

    static func venueAndDashboard() -> AppData {
        var data = AppData()
        var player = PlayerProfile(); player.name = "Alex"
        data.players = [player]; data.selectedPlayerID = player.id
        data.setup.venues = [TennisVenue(name: "Training Court", town: "Town", usedForTraining: true, usedForMatches: false)]
        data.setup.coaches = [TennisCoach(name: "Chris")]
        data.setup.locations = [TennisLocation(name: "Saved Town")]
        var training = TrainingSession(playerID: player.id)
        training.date = Date().addingTimeInterval(-7200)
        training.trainingType = .oneToOneCoaching
        training.focus = TrainingType.oneToOneCoaching.rawValue
        training.context.coachIDs = [data.setup.coaches[0].id]
        training.practiceResult = TennisPracticeResult(kind: .doubles, result: .win)
        data.trainingSessions = [training]
        var historic = training; historic.id = UUID(); historic.practiceResult = nil
        historic.date = Date().addingTimeInterval(-100 * 86400)
        historic.venue = "History Court"; historic.location = "City"
        data.trainingSessions.append(historic)
        for result in [MatchResult.win, .loss, .loss] {
            var match = MatchRecord(playerID: player.id)
            match.matchType = .doubles; match.result = result; match.trainingSessionID = training.id
            match.playerName = "Alex"; match.partnerName = "Chris"; match.opponentName = "Sam"; match.opponent2Name = "Jo"
            data.matches.append(match)
        }
        var tournament = TournamentRecord(playerID: player.id); tournament.name = "Club Open"
        data.tournaments = [tournament]
        return data
    }
}
#endif
