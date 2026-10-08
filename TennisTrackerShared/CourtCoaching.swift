import Foundation

struct CourtActivity: Codable, Equatable {
    var sport = CourtSportSelection.tennis
    var rules: CourtScoringRules?
    var access: CourtAccessSettings?
    var enteredByCoachID: UUID?
    var surface = ""
    var sessionType = ""
    var plan: CourtSessionPlan?
    var score: CourtScoreSession?

    init() {}

    init(player: PlayerProfile, coachID: UUID? = nil) {
        let preferences = player.court.selected
        sport = preferences.sport
        rules = preferences.rules
        access = preferences.access
        enteredByCoachID = coachID == player.id ? nil : coachID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sport = try c.decodeIfPresent(CourtSportSelection.self, forKey: .sport) ?? .tennis
        rules = try c.decodeIfPresent(CourtScoringRules.self, forKey: .rules)
        access = try c.decodeIfPresent(CourtAccessSettings.self, forKey: .access)
        enteredByCoachID = try c.decodeIfPresent(UUID.self, forKey: .enteredByCoachID)
        surface = try c.decodeIfPresent(String.self, forKey: .surface) ?? ""
        sessionType = try c.decodeIfPresent(String.self, forKey: .sessionType) ?? ""
        plan = try c.decodeIfPresent(CourtSessionPlan.self, forKey: .plan)
        score = try c.decodeIfPresent(CourtScoreSession.self, forKey: .score)
    }
}

struct CourtSessionPlan: Codable, Equatable {
    var objective = ""
    var drills = ""
    var equipment = ""
    var adaptations = ""
    var successMeasure = ""
    var review = ""
    var sourceObservationID: UUID?
}

struct CourtObservation: Identifiable, Codable, Equatable {
    var id = UUID()
    var athleteID: UUID
    var coachID: UUID
    var sport: CourtSportSelection
    var date = Date()
    var focus = ""
    var happened = ""
    var interpretation = ""
    var playerPerspective = ""
    var nextAction = ""
    var linkedActivityID: UUID?
    var modifiedAt = Date()
    var revision = 0

    var validationMessage: String? {
        if athleteID == coachID { return "Select an athlete from your roster, not your own profile." }
        if !sport.isValid { return "Choose a sport." }
        if happened.isBlank { return "Record what happened before saving the observation." }
        return nil
    }

    func practicePlan(on date: Date) -> TrainingSession {
        var session = TrainingSession(playerID: athleteID)
        session.date = TennisScheduling.fiveMinuteDate(date)
        session.hasStartTime = true
        session.focus = focus
        session.court.sport = sport
        session.court.enteredByCoachID = coachID
        var plan = CourtSessionPlan()
        plan.objective = nextAction
        plan.sourceObservationID = id
        session.court.plan = plan
        return session
    }
}

struct CourtMeasuredDrill: Identifiable, Codable, Equatable {
    var id = UUID()
    var athleteID: UUID
    var coachID: UUID
    var sport: CourtSportSelection
    var date = Date()
    var name = ""
    var focus = ""
    var successfulAttempts = 0
    var totalAttempts = 0
    var setup = ""
    var conditions = ""
    var measurement: Double?
    var unit = ""
    var linkedActivityID: UUID?
    var modifiedAt = Date()
    var revision = 0

    var validationMessage: String? {
        if athleteID == coachID { return "Select the athlete whose attempts were measured." }
        if !sport.isValid || name.isBlank { return "Enter a drill name and sport." }
        guard (1...100000).contains(totalAttempts), (0...totalAttempts).contains(successfulAttempts) else {
            return "Enter a total greater than zero and successes between zero and that total."
        }
        if let measurement, !measurement.isFinite || measurement < 0 || unit.isBlank { return "Enter a non-negative measurement and its unit." }
        return nil
    }
    var proportion: Double? { validationMessage == nil ? Double(successfulAttempts) / Double(totalAttempts) : nil }
    var summary: String {
        guard let proportion else { return "Measurement needs correction" }
        return "\(name), \(successfulAttempts) of \(totalAttempts) attempts, \(Int((proportion * 100).rounded())) percent"
    }
    func isComparable(to other: CourtMeasuredDrill) -> Bool {
        athleteID == other.athleteID && sport == other.sport && name == other.name && focus == other.focus &&
            setup == other.setup && conditions == other.conditions && unit == other.unit
    }
}

enum CourtMediaKind: String, Codable { case photo, video }

struct CourtMediaMoment: Identifiable, Codable, Equatable {
    var id = UUID()
    var seconds: Double
    var description = ""
    var observation = ""
    var nextAction = ""
}

struct CourtMediaRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var athleteID: UUID
    var coachID: UUID
    var sport: CourtSportSelection
    var activityID: UUID?
    var kind: CourtMediaKind
    var createdAt = Date()
    var description = ""
    var relativeFilename: String
    var durationSeconds: Double?
    var moments: [CourtMediaMoment] = []
    var modifiedAt = Date()
    var revision = 0

    var validationMessage: String? {
        guard sport.isValid, !relativeFilename.isEmpty,
              relativeFilename == URL(fileURLWithPath: relativeFilename).lastPathComponent,
              !relativeFilename.contains(".."), !relativeFilename.contains("/"), !relativeFilename.contains("\\") else {
            return "The media file reference is invalid."
        }
        if let durationSeconds, !durationSeconds.isFinite || durationSeconds < 0 { return "The video duration is invalid." }
        if moments.contains(where: { !$0.seconds.isFinite || $0.seconds < 0 || $0.seconds > (durationSeconds ?? 0) }) {
            return "Each video moment must be within the clip."
        }
        if kind == .photo && !moments.isEmpty { return "Timed moments belong to video clips." }
        return nil
    }
}

struct CourtWorkspace: Codable, Equatable {
    var version = 1
    var ownerPlayerID: UUID?
    var deviceOwnerPlayerID: UUID?
    var activeAthleteID: UUID?
    var observations: [CourtObservation] = []
    var drills: [CourtMeasuredDrill] = []
    var media: [CourtMediaRecord] = []
    var deletedIDs: Set<UUID> = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        ownerPlayerID = try c.decodeIfPresent(UUID.self, forKey: .ownerPlayerID)
        deviceOwnerPlayerID = try c.decodeIfPresent(UUID.self, forKey: .deviceOwnerPlayerID)
        activeAthleteID = try c.decodeIfPresent(UUID.self, forKey: .activeAthleteID)
        observations = try c.decodeIfPresent([CourtObservation].self, forKey: .observations) ?? []
        drills = try c.decodeIfPresent([CourtMeasuredDrill].self, forKey: .drills) ?? []
        media = try c.decodeIfPresent([CourtMediaRecord].self, forKey: .media) ?? []
        deletedIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .deletedIDs) ?? []
    }

    func containsAthlete(_ id: UUID, coachID: UUID, players: [PlayerProfile], includeArchived: Bool = false) -> Bool {
        id != coachID && players.contains { $0.id == id && $0.court.coachOwnerID == coachID && (includeArchived || !$0.isArchived) }
    }

    func mayMeasurePersonalWorkout(playerID: UUID) -> Bool { deviceOwnerPlayerID == playerID }
}

enum CourtFeature: CaseIterable {
    case record, roster, planning, goals, observations, media, measuredDrills, advancedStatistics, coachExport

    func isAvailable(in mode: TrackingMode) -> Bool {
        switch self {
        case .record, .roster, .planning, .goals: return true
        case .observations, .media: return mode != .basic
        case .measuredDrills, .advancedStatistics, .coachExport: return mode == .power
        }
    }
}

enum CourtCoachingProgress {
    static func completedSessions(coachID: UUID, sport: CourtSportSelection, data: AppData, now: Date = Date()) -> [TrainingSession] {
        var seen: Set<UUID> = []
        return data.trainingSessions.filter { session in
            guard session.court.enteredByCoachID == coachID, session.playerID != coachID,
                  session.court.sport == sport, !data.deletedRecordIDs.contains(session.id),
                  session.date <= now, let finished = session.actualFinish, finished <= now,
                  let started = session.actualStart, started <= finished,
                  data.court.containsAthlete(session.playerID, coachID: coachID, players: data.players, includeArchived: true),
                  TennisDurationFormatter.trainingSeconds(session) > 0, seen.insert(session.id).inserted else { return false }
            return true
        }
    }
}
