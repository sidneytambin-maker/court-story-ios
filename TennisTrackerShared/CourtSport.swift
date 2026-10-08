import Foundation

enum CourtSport: String, Codable, CaseIterable, Identifiable {
    case tennis = "Tennis"
    case padel = "Padel"
    case pickleball = "Pickleball"
    case badminton = "Badminton"
    case squash = "Squash"
    case tableTennis = "Table tennis"
    case racquetball = "Racquetball"
    case racketlon = "Racketlon"
    case beachTennis = "Beach tennis"
    case platformTennis = "Platform tennis"
    case custom = "Custom"

    var id: String { rawValue }
    var usesTennisGames: Bool { [.tennis, .padel, .beachTennis, .platformTennis].contains(self) }
    var allowsBouncePreference: Bool { ![.badminton, .beachTennis, .racketlon].contains(self) }

    var focuses: [String] {
        let shared = ["Movement and positioning", "Tactics", "Fitness", "Match confidence"]
        switch self {
        case .padel: return ["Serving", "Returning", "Wall play", "Lobs", "Bandeja", "Vibora", "Volleys", "Smashes"] + shared
        case .pickleball: return ["Serving", "Returning", "Dinking", "Third-shot drops", "Drives", "Volleys", "Resets", "Transition play"] + shared
        case .badminton: return ["Serving", "Returning", "Clears", "Drops", "Smashes", "Net play", "Footwork", "Defence"] + shared
        case .squash: return ["Serving", "Returning", "Drives", "Drops", "Boasts", "Lobs", "Volleying", "Length"] + shared
        case .racquetball: return ["Serving", "Returning", "Passing shots", "Ceiling shots", "Pinch shots", "Kill shots", "Court coverage"] + shared
        case .tableTennis: return ["Serving", "Receiving", "Forehand topspin", "Backhand topspin", "Pushes", "Blocks", "Spin variation", "Footwork"] + shared
        case .racketlon: return ["Table tennis", "Badminton", "Squash", "Tennis", "Transitions", "Aggregate strategy", "Serving", "Returning"] + shared
        case .custom: return ["Scoring", "Defending", "Accuracy", "Positioning", "Movement", "Communication", "Teamwork", "Tactics", "Fitness", "Confidence"]
        case .beachTennis: return ["Serving", "Returning", "Volleys", "Smashes", "Lobs", "Sand movement", "Partner communication"] + shared
        case .platformTennis: return ["Serving", "Returning", "Screen play", "Lobs", "Volleys", "Overheads", "Partner positioning"] + shared
        case .tennis: return ["Serving", "Returning", "Serve and return", "Forehand", "Backhand", "Volleys", "Rally consistency", "Approach shots"] + shared
        }
    }

    var surfaces: [String] {
        switch self {
        case .beachTennis: return ["Sand", "Other"]
        case .tableTennis: return ["Indoor table", "Outdoor table", "Other"]
        case .badminton, .squash, .racquetball: return ["Wooden sports floor", "Synthetic sports floor", "Rubber sports floor", "Other"]
        case .padel: return ["Artificial grass", "Synthetic court", "Other"]
        case .platformTennis: return ["Platform court", "Other"]
        case .custom, .racketlon: return ["Indoor court", "Outdoor court", "Wooden sports floor", "Synthetic sports floor", "Other"]
        case .tennis: return ["Hard court", "Clay", "Grass", "Carpet", "Artificial grass", "Artificial clay", "Indoor", "Other"]
        }
    }
}

struct CourtSportSelection: Codable, Equatable, Hashable, Identifiable {
    var sport: CourtSport = .tennis
    var customName = ""
    var name: String { sport == .custom ? customName.trimmingCharacters(in: .whitespacesAndNewlines) : sport.rawValue }
    var id: String { sport == .custom ? "custom:" + name.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_GB")) : sport.rawValue }
    var isValid: Bool { sport != .custom || (!name.isEmpty && name.count <= 80 && !CourtSport.allCases.contains { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame }) }
    static let tennis = CourtSportSelection()
}

enum CourtRole: String, Codable, CaseIterable, Identifiable {
    case player = "Player"
    case coach = "Coach"
    var id: String { rawValue }
    var welcome: String { self == .coach ? "I am a coach" : "I am a player" }
    var detail: String {
        self == .coach ? "Manage your players, plan sessions and follow their progress, while tracking your own sport too."
            : "Record matches, training and tournaments, and follow your progress across your sports."
    }
}

enum CourtAccessPreference: String, Codable, CaseIterable, Identifiable {
    case sighted = "Sighted"
    case visuallyImpaired = "Visually impaired"
    case wheelchair = "Wheelchair"
    case deaf = "Deaf"
    case learningDisability = "Learning disability"
    case custom = "Custom"
    var id: String { rawValue }
}

struct CourtAccessSettings: Codable, Equatable {
    var preferences: Set<CourtAccessPreference> = [.sighted]
    var classification = ""
    var customDescription = ""
    var bounceOverride: Int?
    var communication = ""
    var learningSupport = ""
    var ruleAdaptations = ""
    var equipmentAdaptations = ""
    var preferHaptics = false
    var preferText = false

    var summary: String {
        let labels = CourtAccessPreference.allCases.filter { preferences.contains($0) }
            .map { $0 == .custom && !customDescription.isBlank ? customDescription : $0.rawValue }
        return labels.isEmpty ? "No access preference selected" : labels.joined(separator: ", ")
    }

    func allowedBounces(for sport: CourtSport) -> Int? {
        guard sport.allowsBouncePreference else { return nil }
        if let bounceOverride { return bounceOverride }
        if preferences.contains(.custom) || sport == .custom { return nil }
        var candidates: [Int] = []
        if preferences.contains(.wheelchair) {
            guard [.tennis, .pickleball, .racquetball].contains(sport) else { return nil }
            candidates.append(2)
        }
        if preferences.contains(.visuallyImpaired) {
            guard sport == .tennis else { return nil }
            switch classification.uppercased() {
            case "B1", "B2": candidates.append(3)
            case "B3": candidates.append(2)
            case "B4", "B5": candidates.append(1)
            default: return nil
            }
        }
        // Combined adaptations require an explicit agreement when defaults differ.
        guard Set(candidates).count <= 1 else { return nil }
        return candidates.first ?? 1
    }

    var validationMessage: String? {
        if let bounceOverride, !(0...20).contains(bounceOverride) { return "Choose a bounce allowance from 0 to 20." }
        if preferences.contains(.custom), customDescription.isBlank { return "Describe your custom access preference." }
        return nil
    }
}

enum CourtPointSystem: String, Codable, CaseIterable, Identifiable {
    case tennisGames = "Games and sets"
    case rally = "Rally points"
    case sideOut = "Side-out points"
    case aggregate = "Four-discipline aggregate"
    var id: String { rawValue }
}

enum CourtDeuceRule: String, Codable, CaseIterable, Identifiable {
    case advantage = "Advantage"
    case noAd = "No-ad"
    case starPoint = "Star point"
    var id: String { rawValue }
}

enum CourtServiceRule: String, Codable, CaseIterable, Identifiable {
    case rallyWinner = "Rally winner serves"
    case alternateTwo = "Alternate every two points"
    case sideOut = "Change on side-out"
    case games = "Alternate games"
    case manual = "Manual service selection"
    var id: String { rawValue }
}

// A value copy belongs to the record, never a live reference to profile defaults.
struct CourtScoringRules: Codable, Equatable {
    var version = 1
    var reference = "Local custom rules"
    var sourceURL = ""
    var system: CourtPointSystem = .rally
    var target = 11
    var winBy = 2
    var cap: Int?
    var roundsToWin = 2
    var deuce: CourtDeuceRule = .advantage
    var service: CourtServiceRule = .rallyWinner
    var doublesTwoServers = false
    var gamesPerSet = 6
    var tieBreakAt: Int? = 6
    var tieBreakTarget = 7
    var decidingMatchTieBreak = false
    var decidingTieBreakTarget = 10
    var customOverride = false

    var validationMessage: String? {
        guard (1...99).contains(target), (1...10).contains(winBy), (1...9).contains(roundsToWin),
              (1...20).contains(gamesPerSet), (1...99).contains(tieBreakTarget),
              (1...99).contains(decidingTieBreakTarget) else { return "Check the target, winning margin and match length." }
        if let cap, !(target...199).contains(cap) { return "The cap must be at least the target and no more than 199." }
        if let tieBreakAt, !(1...20).contains(tieBreakAt) { return "Choose a tie-break trigger from 1 to 20 games." }
        if system == .sideOut && service != .sideOut { return "Side-out scoring requires side-out service." }
        if system == .aggregate && (target != 21 || winBy != 2 || cap != nil) { return "Racketlon uses four games to 21, winning by two without a cap." }
        return nil
    }

    static func standard(for sport: CourtSport, doubles: Bool = false) -> CourtScoringRules {
        var rules = CourtScoringRules()
        switch sport {
        case .tennis:
            rules.system = .tennisGames; rules.service = .games; rules.roundsToWin = 1
            rules.reference = "ITF Rules of Tennis 2026"; rules.sourceURL = "https://www.itftennis.com/en/about-us/governance/rules-and-regulations/"
        case .padel:
            rules.system = .tennisGames; rules.service = .games; rules.deuce = .starPoint
            rules.reference = "FIP Star Point 2026; event format may differ"; rules.sourceURL = "https://www.padelfip.com/2025/12/between-innovation-and-tradition-introducing-the-star-point-the-scoring-system-that-appeals-to-everyone/"
        case .pickleball:
            rules.system = .sideOut; rules.service = .sideOut; rules.doublesTwoServers = doubles
            rules.reference = "USA Pickleball 2026, side-out format"; rules.sourceURL = "https://usapickleball.org/rules/"
        case .badminton:
            rules.target = 21; rules.cap = 30
            rules.reference = "BWF 2026, 21-point format"; rules.sourceURL = "https://corporate.bwfbadminton.com/statutes/"
        case .squash:
            rules.roundsToWin = 3
            rules.reference = "World Squash singles rules September 2025, PAR 11"; rules.sourceURL = "https://worldsquashofficiating.com/rules-of-squash/"
        case .tableTennis:
            rules.roundsToWin = 3; rules.service = .alternateTwo
            rules.reference = "ITTF 2026, games to 11; match length selectable"; rules.sourceURL = "https://www.ittf.com/statutes/"
        case .racquetball:
            rules.roundsToWin = 3; rules.service = .sideOut; rules.doublesTwoServers = doubles
            rules.reference = "IRF rally scoring, best of five to 11"; rules.sourceURL = "https://www.internationalracquetball.com/rules/"
        case .racketlon:
            rules.system = .aggregate; rules.target = 21; rules.service = .alternateTwo
            rules.reference = "FIR Rules of Racketlon July 2022"; rules.sourceURL = "https://www.racketlon.net/wp-content/uploads/2022/07/FIR-Rules-of-Racketlon-25.07.2022.pdf"
        case .beachTennis:
            rules.system = .tennisGames; rules.service = .games; rules.deuce = .noAd; rules.decidingMatchTieBreak = true
            rules.reference = "ITF Rules of Beach Tennis 2026"; rules.sourceURL = "https://www.itftennis.com/media/15473/rules-of-beach-tennis-2026.pdf"
        case .platformTennis:
            rules.system = .tennisGames; rules.service = .games; rules.deuce = doubles ? .advantage : .noAd
            rules.reference = "APTA rules; tour no-ad variants selectable"; rules.sourceURL = "https://platformtennis.org/rules/"
        case .custom:
            rules.target = 10; rules.winBy = 1; rules.roundsToWin = 1; rules.service = .manual
        }
        return rules
    }
}

struct CourtSportPreferences: Codable, Equatable, Identifiable {
    var sport = CourtSportSelection.tennis
    var role: CourtRole = .player
    var access = CourtAccessSettings()
    var rules = CourtScoringRules.standard(for: .tennis)
    var primaryGoal = ""
    var developmentNotes = ""
    var reviewDate: Date?
    var id: String { sport.id }

    init(sport: CourtSportSelection = .tennis, role: CourtRole = .player) {
        self.sport = sport
        self.role = role
        self.rules = .standard(for: sport.sport)
    }
}

struct CourtProfile: Codable, Equatable {
    var sports: [CourtSportPreferences] = [CourtSportPreferences()]
    var selectedSportID = CourtSportSelection.tennis.id
    var coachOwnerID: UUID?
    var archivedAt: Date?
    var modifiedAt = Date()
    var revision = 0
    var coaching = CourtCoachCredentials()

    var selected: CourtSportPreferences { sports.first { $0.id == selectedSportID } ?? sports.first ?? CourtSportPreferences() }

    mutating func select(_ sport: CourtSportSelection) -> Bool {
        guard sport.isValid else { return false }
        if !sports.contains(where: { $0.id == sport.id }) { sports.append(CourtSportPreferences(sport: sport)) }
        selectedSportID = sport.id
        return true
    }

    mutating func update(_ preferences: CourtSportPreferences) -> Bool {
        guard preferences.sport.isValid, preferences.access.validationMessage == nil,
              preferences.rules.validationMessage == nil,
              let index = sports.firstIndex(where: { $0.id == preferences.id }) else { return false }
        sports[index] = preferences
        return true
    }

    static func legacy(_ player: PlayerProfile) -> CourtProfile {
        var profile = CourtProfile()
        var preferences = CourtSportPreferences()
        preferences.primaryGoal = player.primaryGoal
        preferences.access.preferences = player.playerMode == .blindTennis ? [.visuallyImpaired] : [.sighted]
        preferences.access.classification = player.sightLevel == .notKnown ? "" : player.sightLevel.label
        preferences.access.bounceOverride = player.bounceAllowance
        preferences.rules.roundsToWin = player.defaultMatchFormat.setsNeededToWin
        preferences.rules.deuce = player.playerMode == .blindTennis ? .noAd : .advantage
        profile.sports = [preferences]
        return profile
    }
}

struct CourtCoachCredentials: Codable, Equatable {
    var level = ""
    var qualifications = ""
    var experience = ""
    var audience = ""
    var specialisms = ""
    var focus = ""
    var sessionGoals = ""
    var organisation = ""
    var renewalDate: Date?
    var safeguardingNotes = ""
}

extension PlayerProfile {
    var court: CourtProfile {
        get { courtProfile ?? CourtProfile.legacy(self) }
        set { courtProfile = newValue }
    }
    var selectedSport: CourtSportSelection { court.selected.sport }
    var isArchived: Bool { court.archivedAt != nil }
}
