import Foundation

enum TennisBackupError: LocalizedError {
    case invalidFile, newerVersion, brokenRelationships, duplicateIDs, activeActivity, destinationNotEmpty, unreadableStore

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "This is not a complete Court Story backup. Nothing was imported."
        case .newerVersion: return "This library needs a newer version of Court Story. Nothing was changed."
        case .brokenRelationships: return "Some records in this backup refer to missing players, places or activities. Keep the original file for recovery. Nothing was imported."
        case .duplicateIDs: return "This backup contains duplicate record identifiers. Nothing was imported."
        case .activeActivity: return "Finish any tracked activity before creating a migration backup. Nothing was imported."
        case .destinationNotEmpty: return "Restore is available only before setting up a new library. Your existing records have not been replaced."
        case .unreadableStore: return "The current library is unavailable. It has not been erased."
        }
    }
}

enum TennisBackup {
    static func decodeStoredLibrary(_ bytes: Data) throws -> AppData {
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let version = object["dataVersion"] as? Int, version > 0,
              object["settings"] is [String: Any] else { throw TennisBackupError.invalidFile }
        guard version <= 11 else { throw TennisBackupError.newerVersion }
        for key in ["players", "matches", "trainingSessions", "tournaments"] { try requireIDs(object[key]) }
        if version >= 9 {
            guard let setup = object["setup"] as? [String: Any] else { throw TennisBackupError.invalidFile }
            for key in ["coaches", "venues", "locations", "tournamentTemplates"] { try requireIDs(setup[key]) }
        }
        if version >= 11 {
            guard let identifier = object["libraryID"] as? String, UUID(uuidString: identifier) != nil,
                  object["onboardingCompleted"] is Bool else { throw TennisBackupError.invalidFile }
        }
        return try JSONDecoder.tennisTracker.decode(AppData.self, from: bytes)
    }

    static func decode(_ bytes: Data) throws -> AppData {
        guard bytes.count <= 20_000_000,
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let version = object["dataVersion"] as? Int, version >= 10,
              let setup = object["setup"] as? [String: Any], object["settings"] is [String: Any],
              object["deletedRecordIDs"] is [String] else { throw TennisBackupError.invalidFile }
        guard version <= 11 else { throw TennisBackupError.newerVersion }
        // Legacy decoders supply defaults. A restore must not silently invent missing IDs or tables.
        for key in ["players", "matches", "trainingSessions", "tournaments"] {
            try requireIDs(object[key])
        }
        for key in ["coaches", "venues", "locations", "tournamentTemplates"] { try requireIDs(setup[key]) }
        let result = try JSONDecoder.tennisTracker.decode(AppData.self, from: bytes)
        try validate(result)
        return result
    }

    private static func requireIDs(_ value: Any?) throws {
        guard let rows = value as? [[String: Any]], rows.allSatisfy({ row in
            (row["id"] as? String).flatMap(UUID.init(uuidString:)) != nil
        }) else { throw TennisBackupError.invalidFile }
    }

    static func validate(_ value: AppData) throws {
        guard (10...11).contains(value.dataVersion), !value.players.isEmpty else { throw TennisBackupError.invalidFile }
        let players = Set(value.players.map(\.id))
        let matches = Set(value.matches.map(\.id))
        let training = Set(value.trainingSessions.map(\.id))
        let tournaments = Set(value.tournaments.map(\.id))
        let coaches = Set(value.setup.coaches.map(\.id))
        let venues = Set(value.setup.venues.map(\.id))
        let templates = Set(value.setup.tournamentTemplates.map(\.id))
        let groups = [value.players.map(\.id), value.matches.map(\.id), value.trainingSessions.map(\.id), value.tournaments.map(\.id),
                      value.setup.coaches.map(\.id), value.setup.venues.map(\.id), value.setup.locations.map(\.id), value.setup.tournamentTemplates.map(\.id)]
        let all = groups.flatMap { $0 }
        guard Set(all).count == all.count else { throw TennisBackupError.duplicateIDs }
        guard matches.union(training).union(tournaments).isDisjoint(with: value.deletedRecordIDs) else { throw TennisBackupError.invalidFile }
        func reference(_ id: UUID?, in ids: Set<UUID>) throws {
            if let id, !ids.contains(id) { throw TennisBackupError.brokenRelationships }
        }
        try reference(value.selectedPlayerID, in: players)
        for coach in value.setup.coaches { try reference(coach.playerID, in: players) }
        for template in value.setup.tournamentTemplates { try reference(template.venueID, in: venues) }
        for match in value.matches {
            guard match.status != .inProgress, match.actualStart == nil || match.actualFinish != nil else { throw TennisBackupError.activeActivity }
            for id in [match.playerID, match.partnerID, match.opponentID, match.opponent2ID] { try reference(id, in: players) }
            try reference(match.tournamentID, in: tournaments)
            try reference(match.trainingSessionID, in: training)
            try reference(match.venueID, in: venues)
        }
        for session in value.trainingSessions {
            guard !session.isActive else { throw TennisBackupError.activeActivity }
            try reference(session.playerID, in: players)
            for id in session.context.coachIDs { try reference(id, in: coaches) }
            for id in session.context.participantIDs { try reference(id, in: players) }
            try reference(session.context.venueID, in: venues)
            try reference(session.context.tournamentID, in: tournaments)
            if let result = session.practiceResult {
                for id in [result.partnerID, result.opponentID, result.opponent2ID] { try reference(id, in: players) }
            }
        }
        for tournament in value.tournaments {
            guard tournament.actualStart == nil || tournament.actualFinish != nil else { throw TennisBackupError.activeActivity }
            try reference(tournament.playerID, in: players)
            try reference(tournament.venueID, in: venues)
            try reference(tournament.templateID, in: templates)
        }
    }
}
