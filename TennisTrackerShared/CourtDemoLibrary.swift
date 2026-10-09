import Foundation

// Fictional, deterministic examples for native regression tests and private test backups.
// Never merged into a person's existing library or enabled during normal launch.
enum CourtDemoLibrary {
    static func make(role: CourtRole = .coach, mode: TrackingMode = .power, now: Date = Date()) -> AppData {
        var data = AppData()
        data.libraryID = UUID(uuidString: "D0000000-0000-4000-8000-000000000001")!
        data.onboardingCompleted = true
        data.settings.trackingMode = mode
        var owner = PlayerProfile(); owner.id = UUID(uuidString: "D0000000-0000-4000-8000-000000000010")!
        owner.name = role == .coach ? "Demo Coach Alex" : "Demo Player Alex"
        owner.court = CourtProfile()
        owner.court.sports[0].role = role
        owner.court.sports[0].primaryGoal = "Build a consistent second serve"
        owner.court.sports.append(CourtSportPreferences(sport: CourtSportSelection(sport: .badminton)))
        let custom = CourtSportSelection(sport: .custom, customName: "Goalball")
        var customPreferences = CourtSportPreferences(sport: custom)
        customPreferences.rules.target = 10; customPreferences.rules.winBy = 1; customPreferences.rules.roundsToWin = 1
        customPreferences.rules.service = .manual
        owner.court.sports.append(customPreferences)
        data.players = [owner]; data.selectedPlayerID = owner.id
        data.court.ownerPlayerID = owner.id; data.court.deviceOwnerPlayerID = owner.id
        let athlete: PlayerProfile
        if role == .coach {
            var player = PlayerProfile(); player.id = UUID(uuidString: "D0000000-0000-4000-8000-000000000020")!
            player.name = "Demo Player Morgan"; player.court = CourtProfile(); player.court.coachOwnerID = owner.id
            player.court.sports[0].access.preferences = [.visuallyImpaired]; player.court.sports[0].access.classification = "B1"
            player.court.sports[0].primaryGoal = "Return deep through the middle"
            player.court.sports[0].reviewDate = now.addingTimeInterval(-86400)
            player.court.sports.append(CourtSportPreferences(sport: CourtSportSelection(sport: .badminton)))
            player.court.sports.append(customPreferences)
            data.players.append(player); athlete = player
        } else { athlete = owner }
        for (index, sport) in athlete.court.sports.enumerated() {
            var person = athlete; person.court.selectedSportID = sport.id
            var training = TrainingSession(playerID: athlete.id)
            training.id = UUID(uuidString: "D0000000-0000-4000-8000-0000000001\(String(format: "%02d", index))")!
            training.court = CourtActivity(player: person, coachID: role == .coach ? owner.id : nil)
            training.date = now.addingTimeInterval(Double(-4 + index) * 86400)
            training.actualStart = training.date; training.actualFinish = training.date.addingTimeInterval(1839)
            training.durationMinutes = 31
            training.focus = sport.sport.sport.focuses.first ?? ""
            training.court.plan = CourtSessionPlan(objective: "Repeat a clear movement pattern", drills: "Three sets of ten controlled attempts", equipment: "Standard equipment for this sport", adaptations: "Agree cues with the player", successMeasure: "Seven of ten accurate attempts", review: "Fictional demonstration only")
            data.trainingSessions.append(training)
        }
        var planned = TrainingSession(playerID: athlete.id)
        planned.id = UUID(uuidString: "D0000000-0000-4000-8000-000000000200")!
        planned.date = TennisScheduling.fiveMinuteDate(now.addingTimeInterval(86400)); planned.hasStartTime = true
        planned.court = CourtActivity(player: athlete, coachID: role == .coach ? owner.id : nil)
        planned.focus = "Serve and return"; data.trainingSessions.append(planned)
        var customMatch = MatchRecord(playerID: athlete.id)
        customMatch.id = UUID(uuidString: "D0000000-0000-4000-8000-000000000300")!
        customMatch.date = now.addingTimeInterval(-86400); customMatch.status = .completed
        customMatch.court.sport = custom; customMatch.court.rules = customPreferences.rules
        customMatch.court.enteredByCoachID = role == .coach ? owner.id : nil
        var score = CourtScoreSession(sport: custom, rules: customPreferences.rules, sides: [CourtScoreSide(name: "Demo Amber team", members: ["Alex", "Morgan", "Robin"]), CourtScoreSide(name: "Demo Green team", members: ["Jamie", "Casey", "Taylor"])])
        _ = score.recordResult([CourtScoreRound(points: [10, 7])])
        customMatch.playerName = score.sides[0].name; customMatch.opponentName = score.sides[1].name
        customMatch.applyCourtScore(score); data.matches.append(customMatch)
        if role == .coach {
            var observation = CourtObservation(athleteID: athlete.id, coachID: owner.id, sport: .tennis)
            observation.id = UUID(uuidString: "D0000000-0000-4000-8000-000000000400")!
            observation.date = now.addingTimeInterval(-86400)
            observation.focus = "Returning"; observation.happened = "Demo observation: deeper returns during the final drill"
            observation.interpretation = "The agreed cue may have helped"; observation.playerPerspective = "The cue felt clearer"
            observation.nextAction = "Repeat ten returns with the same cue"
            data.court.observations = [observation]
            var drill = CourtMeasuredDrill(athleteID: athlete.id, coachID: owner.id, sport: .tennis)
            drill.id = UUID(uuidString: "D0000000-0000-4000-8000-000000000500")!
            drill.date = now.addingTimeInterval(-86400); drill.name = "Demo return accuracy"
            drill.successfulAttempts = 7; drill.totalAttempts = 10; drill.setup = "Cross-court target"; drill.conditions = "Indoor, controlled feed"
            data.court.drills = [drill]
        }
        return data
    }
}
