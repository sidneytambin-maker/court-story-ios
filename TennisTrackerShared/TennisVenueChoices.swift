import Foundation

struct TennisVenueChoice: Identifiable, Codable, Equatable {
    var venueID: UUID?
    var name: String
    var location: String
    var id: String { Self.key(name, location) }
    var summary: String { [name, location].filter { !$0.isBlank }.joined(separator: ", ") }

    static func key(_ name: String, _ location: String) -> String {
        [name, location].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_GB")) }.joined(separator: "|")
    }

    static func build(setup: TennisSetup, matches: [MatchRecord], training: [TrainingSession], tournaments: [TournamentRecord]) -> [Self] {
        let saved = setup.venues.map { Self(venueID: $0.id, name: $0.name, location: $0.town) }
        let history = matches.map { Self(venueID: $0.venueID, name: $0.venue, location: $0.location) }
            + training.map { Self(venueID: $0.context.venueID, name: $0.venue, location: $0.location) }
            + tournaments.map { Self(venueID: $0.venueID, name: $0.venue, location: $0.location) }
        return unique(saved + history)
    }

    static func unique(_ choices: [Self]) -> [Self] {
        var seen = Set<String>()
        return choices.filter { !$0.name.isBlank && seen.insert($0.id).inserted }
            .sorted { $0.summary.localizedStandardCompare($1.summary) == .orderedAscending }
    }
}

extension TennisWatchSnapshot {
    var availableVenueChoices: [TennisVenueChoice] {
        TennisVenueChoice.unique(TennisVenueChoice.build(setup: setup, matches: matches, training: trainingSessions, tournaments: tournaments) + knownVenues)
    }
}
