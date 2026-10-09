import Foundation

enum CourtLibraryValidation {
    static func message(in data: AppData, validateLinks: Bool = true) -> String? {
        guard data.court.version == 1 else { return "This coaching library needs a newer version of Court Story." }
        let players = Set(data.players.map(\.id))
        let activityIDs = Set(data.matches.map(\.id) + data.trainingSessions.map(\.id) + data.tournaments.map(\.id))
        let extraIDs = data.court.observations.map(\.id) + data.court.drills.map(\.id) + data.court.media.map(\.id)
        if Set(extraIDs).count != extraIDs.count || !Set(extraIDs).isDisjoint(with: activityIDs.union(players)) {
            return "Coaching records contain duplicate identifiers."
        }
        if !Set(extraIDs).isDisjoint(with: data.court.deletedIDs) { return "Deleted coaching records cannot be restored as active records." }
        if let owner = data.court.ownerPlayerID, !players.contains(owner) { return "The library owner profile is missing." }
        if let owner = data.court.deviceOwnerPlayerID, !players.contains(owner) { return "The personal Health owner profile is missing." }
        if let athlete = data.court.activeAthleteID {
            guard let owner = data.court.ownerPlayerID,
                  data.court.containsAthlete(athlete, coachID: owner, players: data.players) else {
                return "Select an active athlete from this coach's roster."
            }
        }
        for player in data.players {
            let profile = player.court
            if profile.sports.isEmpty || Set(profile.sports.map(\.id)).count != profile.sports.count ||
                !profile.sports.contains(where: { $0.id == profile.selectedSportID }) { return "Each profile needs a valid selected sport." }
            if let coach = profile.coachOwnerID, coach == player.id || !players.contains(coach) { return "The roster coach reference is invalid." }
            for sport in profile.sports {
                if !sport.sport.isValid || sport.rules.validationMessage != nil || sport.access.validationMessage != nil {
                    return "Check the saved sport and access preferences."
                }
            }
        }
        func attribution(_ athlete: UUID, _ coach: UUID, _ sport: CourtSportSelection) -> Bool {
            data.court.containsAthlete(athlete, coachID: coach, players: data.players, includeArchived: true) && sport.isValid &&
                data.players.first(where: { $0.id == athlete })?.court.sports.contains(where: { $0.sport == sport }) == true
        }
        func linkedActivity(_ id: UUID?, athlete: UUID, sport: CourtSportSelection) -> Bool {
            guard validateLinks else { return true }
            guard let id else { return true }
            if data.deletedRecordIDs.contains(id) { return true }
            return data.matches.contains { $0.id == id && $0.playerID == athlete && $0.court.sport == sport } ||
                data.trainingSessions.contains { $0.id == id && $0.playerID == athlete && $0.court.sport == sport } ||
                data.tournaments.contains { $0.id == id && $0.playerID == athlete && $0.court.sport == sport }
        }
        for record in data.court.observations {
            if record.validationMessage != nil || !attribution(record.athleteID, record.coachID, record.sport) || !linkedActivity(record.linkedActivityID, athlete: record.athleteID, sport: record.sport) { return "An observation has an invalid athlete, activity or content." }
        }
        for record in data.court.drills {
            if record.validationMessage != nil || !attribution(record.athleteID, record.coachID, record.sport) || !linkedActivity(record.linkedActivityID, athlete: record.athleteID, sport: record.sport) { return "A measured drill has an invalid athlete, activity or measurement." }
        }
        if Set(data.court.media.map { $0.relativeFilename.lowercased() }).count != data.court.media.count {
            return "Each media record must have its own private file."
        }
        for record in data.court.media {
            if record.validationMessage != nil || !attribution(record.athleteID, record.coachID, record.sport) || !linkedActivity(record.activityID, athlete: record.athleteID, sport: record.sport) { return "A media record has an invalid athlete, activity or file reference." }
        }
        let records = data.matches.map { ($0.playerID, $0.court) } + data.trainingSessions.map { ($0.playerID, $0.court) }
            + data.tournaments.map { ($0.playerID, $0.court) }
        for (athlete, context) in records {
            if !context.sport.isValid || context.rules?.validationMessage != nil || context.access?.validationMessage != nil || context.score?.validationMessage != nil { return "An activity has invalid sport rules or scores." }
            if let score = context.score, score.sport != context.sport || score.rules != context.rules { return "The score must use this activity's saved sport and rules." }
            if let coach = context.enteredByCoachID, !attribution(athlete, coach, context.sport) { return "An activity's coaching attribution is invalid." }
        }
        for training in data.trainingSessions where training.workout != nil {
            if data.players.first(where: { $0.id == training.playerID })?.court.coachOwnerID != nil {
                return "Personal Health measurements cannot be attached to a coached player's training."
            }
        }
        return nil
    }
}

extension AppData {
    mutating func migrateCourtProfiles() {
        guard dataVersion < 12 else { return }
        for index in players.indices where players[index].courtProfile == nil {
            players[index].courtProfile = .legacy(players[index])
        }
        court.ownerPlayerID = selectedPlayerID ?? players.first?.id
        court.deviceOwnerPlayerID = court.ownerPlayerID
        dataVersion = 12
    }
}
