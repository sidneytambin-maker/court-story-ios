import Foundation

struct TennisCoach: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var organisation = ""
    var notes = ""
    var playerID: UUID?
}

struct TennisVenue: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var town = ""
    var address = ""
    var notes = ""
    var usedForTraining = true
    var usedForMatches = true
    var summary: String { [name, town].filter { !$0.isBlank }.joined(separator: ", ") }
}

struct TennisLocation: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
}

struct TennisTournamentTemplate: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var venueID: UUID?
    var format: TournamentFormat = .other
}

struct TennisSetup: Codable, Equatable {
    var coaches: [TennisCoach] = []
    var venues: [TennisVenue] = []
    var locations: [TennisLocation] = []
    var tournamentTemplates: [TennisTournamentTemplate] = []
}

// IDs are authoritative. Legacy names remain only for older wire data and deleted profiles.
struct TennisActivityContext: Codable, Equatable {
    var coachIDs: [UUID] = []
    var coachID: UUID? {
        get { coachIDs.first }
        set { coachIDs = newValue.map { [$0] } ?? [] }
    }
    var coachName = ""
    var otherCoachName: String?
    var coachesNeedDetails: Bool?
    var participantIDs: [UUID] = []
    var participantNames: [String] = []
    var participantsNeedDetails: Bool?
    var venueID: UUID?
    var tournamentID: UUID?
    var customTournamentName: String?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case coachIDs, coachID, coachName, otherCoachName, coachesNeedDetails, participantIDs, participantNames
        case participantsNeedDetails, venueID, tournamentID, customTournamentName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacyID = try c.decodeIfPresent(UUID.self, forKey: .coachID)
        coachIDs = Self.unique(try c.decodeIfPresent([UUID].self, forKey: .coachIDs) ?? legacyID.map { [$0] } ?? [])
        coachName = try c.decodeIfPresent(String.self, forKey: .coachName) ?? ""
        otherCoachName = try c.decodeIfPresent(String.self, forKey: .otherCoachName)
        coachesNeedDetails = try c.decodeIfPresent(Bool.self, forKey: .coachesNeedDetails)
        participantIDs = Self.unique(try c.decodeIfPresent([UUID].self, forKey: .participantIDs) ?? [])
        participantNames = try c.decodeIfPresent([String].self, forKey: .participantNames) ?? []
        participantsNeedDetails = try c.decodeIfPresent(Bool.self, forKey: .participantsNeedDetails)
        venueID = try c.decodeIfPresent(UUID.self, forKey: .venueID)
        tournamentID = try c.decodeIfPresent(UUID.self, forKey: .tournamentID)
        customTournamentName = try c.decodeIfPresent(String.self, forKey: .customTournamentName)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.unique(coachIDs), forKey: .coachIDs)
        try c.encodeIfPresent(coachID, forKey: .coachID)
        try c.encode(coachName, forKey: .coachName)
        try c.encodeIfPresent(otherCoachName, forKey: .otherCoachName)
        try c.encodeIfPresent(coachesNeedDetails, forKey: .coachesNeedDetails)
        try c.encode(Self.unique(participantIDs), forKey: .participantIDs)
        try c.encode(participantNames, forKey: .participantNames)
        try c.encodeIfPresent(participantsNeedDetails, forKey: .participantsNeedDetails)
        try c.encodeIfPresent(venueID, forKey: .venueID)
        try c.encodeIfPresent(tournamentID, forKey: .tournamentID)
        try c.encodeIfPresent(customTournamentName, forKey: .customTournamentName)
    }

    func coachSummary(in coaches: [TennisCoach]) -> String {
        let names = Self.unique(coachIDs).compactMap { id in coaches.first { $0.id == id }?.name }
        if !coachIDs.isEmpty && names.count == Self.unique(coachIDs).count {
            return Self.names(names + [otherCoachName ?? ""])
        }
        if coachIDs.isEmpty, let otherCoachName { return otherCoachName }
        return coachName
    }

    var needsOtherCoachName: Bool { otherCoachName?.isBlank == true }

    mutating func clearCoaches() {
        coachIDs = []
        coachName = ""
        otherCoachName = nil
        coachesNeedDetails = false
    }

    func participantSummary(in players: [PlayerProfile]) -> String {
        let names = Self.unique(participantIDs).compactMap { id in players.first { $0.id == id }?.displayName }
        return Self.names(!participantIDs.isEmpty && names.count == Self.unique(participantIDs).count ? names : participantNames)
    }

    mutating func captureLegacyNames(coaches: [TennisCoach], players: [PlayerProfile]) {
        coachIDs = Self.unique(coachIDs)
        participantIDs = Self.unique(participantIDs)
        if !coachIDs.isEmpty { coachName = coachSummary(in: coaches) }
        let resolved = participantIDs.compactMap { id in players.first { $0.id == id }?.displayName }
        if !participantIDs.isEmpty && resolved.count == participantIDs.count { participantNames = resolved }
    }

    static func names(_ values: [String]) -> String {
        let names = values.filter { !$0.isBlank }
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    private static func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}

struct TennisWorkoutResult: Codable, Equatable {
    var workoutID: UUID?
    var durationSeconds: Double
    var averageHeartRate: Double?
    var activeEnergyKcal: Double?
    var peakHeartRate: Double?
    var distanceMeters: Double?
    var stepCount: Double?
}

struct TennisPracticeResult: Codable, Equatable {
    var kind: MatchKind = .singles
    var partnerID: UUID?
    var opponentID: UUID?
    var opponent2ID: UUID?
    var partnerName = ""
    var opponentName = ""
    var opponent2Name = ""
    var result: MatchResult = .draw
    var playerGames = 0
    var opponentGames = 0
}

enum TennisWatchPage: String, CaseIterable, Identifiable {
    case today = "Overview", track = "Track", live = "Live", recent = "Recent", score = "Score"
    var id: String { rawValue }
    var url: URL { URL(string: "tennistracker://watch/\(self == .today ? "today" : rawValue.lowercased())")! }
    static func destination(for url: URL) -> Self? {
        guard url.scheme == "tennistracker", url.host == "watch" else { return nil }
        if url.lastPathComponent == "start-training" { return .track }
        if url.lastPathComponent == "today" { return .today }
        return allCases.first { url.lastPathComponent == $0.rawValue.lowercased() }
    }
}

enum TennisSetEntry {
    static func requiredRows(format: MatchFormat, player: [Int], opponent: [Int]) -> Int {
        if format == .oneSet { return 1 }
        var wins = 0, losses = 0
        for index in 0..<min(player.count, opponent.count, format.maximumSetsToEnter) {
            if player[index] == 0 && opponent[index] == 0 {
                return max(format.defaultSetsToEnter, index + 1)
            }
            if player[index] > opponent[index] { wins += 1 }
            if player[index] < opponent[index] { losses += 1 }
            if wins == format.setsNeededToWin || losses == format.setsNeededToWin { return index + 1 }
        }
        return format.maximumSetsToEnter
    }
}
