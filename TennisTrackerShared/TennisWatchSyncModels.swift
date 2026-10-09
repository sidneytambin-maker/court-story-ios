import Foundation

struct TennisWatchSnapshot: Codable, Equatable {
    var courtProtocolVersion = 2
    var court = CourtWorkspace()
    var libraryID: UUID?
    var generatedAt = Date()
    var deletedRecordIDs: Set<UUID> = []
    var selectedPlayerID: UUID?
    var players: [PlayerProfile] = []
    var matches: [MatchRecord] = []
    var trainingSessions: [TrainingSession] = []
    var tournaments: [TournamentRecord] = []
    var settings = AppSettings()
    var setup = TennisSetup()
    var knownVenues: [TennisVenueChoice] = []
    var achievementHistory: [TennisAchievementRecord] = []
    var requestedActivityID: UUID?
    var requestedActivityFound: Bool?

    static let empty = TennisWatchSnapshot()

    init() {}

    init(data: AppData, now: Date = Date(), including recordID: UUID? = nil) {
        court = data.court
        if court.deviceOwnerPlayerID == nil { court.deviceOwnerPlayerID = data.selectedPlayerID ?? data.players.first?.id }
        if court.ownerPlayerID == nil { court.ownerPlayerID = data.selectedPlayerID ?? data.players.first?.id }
        libraryID = data.libraryID
        generatedAt = now
        deletedRecordIDs = data.deletedRecordIDs
        selectedPlayerID = data.selectedPlayerID
        players = data.players
        settings = data.settings
        setup = data.setup
        achievementHistory = TennisAchievementRecord.collect(matches: data.matches, training: data.trainingSessions, tournaments: data.tournaments, now: now, players: data.players)
        knownVenues = TennisVenueChoice.build(setup: data.setup, matches: data.matches, training: data.trainingSessions, tournaments: data.tournaments)

        let recentLimit = Calendar.current.date(byAdding: .day, value: -60, to: now) ?? now
        let weekStart = TennisReportingWeek.interval(containing: now).start
        matches = data.matches
            .filter { $0.status != .completed || $0.needsDetails || $0.date >= recentLimit || $0.date >= now }
            .sorted { $0.date > $1.date }
            .prefix(30)
            .map { $0 }
        // History limits must never drop a scheduled/active match or an offline edit awaiting details.
        matches += data.matches.filter { record in
            (record.status != .completed || record.needsDetails || (record.date >= weekStart && record.date <= now)) && !matches.contains { $0.id == record.id }
        }
        trainingSessions = data.trainingSessions
            .filter { $0.isActive || $0.needsDetails || $0.date >= recentLimit || $0.expectedEndDate >= now }
            .sorted { $0.date > $1.date }
            .prefix(30)
            .map { $0 }
        let focusStart = Calendar.current.date(byAdding: .day, value: -30, to: Calendar.current.startOfDay(for: now)) ?? now
        trainingSessions += data.trainingSessions.filter { record in
            // Match TennisPlayerProgress's recorded focus window even when the editable cache is full.
            let start = record.actualStart ?? record.date
            let inFocusWindow = record.isRecordedTraining(at: now) && start >= focusStart && start <= now
            return (record.isActive || record.needsDetails || inFocusWindow || (record.date >= weekStart && record.date <= now))
                && !trainingSessions.contains { $0.id == record.id }
        }
        tournaments = data.tournaments
            .filter { !$0.isCompleted || $0.needsDetails || $0.endDate >= recentLimit }
            .sorted { $0.date > $1.date }
            .prefix(20)
            .map { $0 }
        tournaments += data.tournaments.filter { record in
            (!record.isCompleted || record.needsDetails) && !tournaments.contains { $0.id == record.id }
        }
        if let recordID {
            requestedActivityID = recordID
            requestedActivityFound = !data.deletedRecordIDs.contains(recordID) &&
                (data.matches.contains { $0.id == recordID } || data.trainingSessions.contains { $0.id == recordID } || data.tournaments.contains { $0.id == recordID })
            matches += data.matches.filter { $0.id == recordID && !matches.contains { $0.id == recordID } }
            trainingSessions += data.trainingSessions.filter { $0.id == recordID && !trainingSessions.contains { $0.id == recordID } }
            tournaments += data.tournaments.filter { $0.id == recordID && !tournaments.contains { $0.id == recordID } }
        }
        // Retained and explicitly requested tournaments need their full linked results for honest summaries.
        let retainedTournamentIDs = Set(tournaments.map(\.id))
        let retainedMatchIDs = Set(matches.map(\.id))
        matches += data.matches.filter { record in
            guard let tournamentID = record.tournamentID else { return false }
            return retainedTournamentIDs.contains(tournamentID) && !retainedMatchIDs.contains(record.id)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        courtProtocolVersion = try c.decodeIfPresent(Int.self, forKey: .courtProtocolVersion) ?? 1
        court = try c.decodeIfPresent(CourtWorkspace.self, forKey: .court) ?? CourtWorkspace()
        libraryID = try c.decodeIfPresent(UUID.self, forKey: .libraryID)
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .distantPast
        deletedRecordIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .deletedRecordIDs) ?? []
        selectedPlayerID = try c.decodeIfPresent(UUID.self, forKey: .selectedPlayerID)
        players = try c.decodeIfPresent([PlayerProfile].self, forKey: .players) ?? []
        matches = try c.decodeIfPresent([MatchRecord].self, forKey: .matches) ?? []
        trainingSessions = try c.decodeIfPresent([TrainingSession].self, forKey: .trainingSessions) ?? []
        tournaments = try c.decodeIfPresent([TournamentRecord].self, forKey: .tournaments) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        setup = try c.decodeIfPresent(TennisSetup.self, forKey: .setup) ?? TennisSetup()
        knownVenues = try c.decodeIfPresent([TennisVenueChoice].self, forKey: .knownVenues) ?? []
        achievementHistory = try c.decodeIfPresent([TennisAchievementRecord].self, forKey: .achievementHistory) ?? []
        requestedActivityID = try c.decodeIfPresent(UUID.self, forKey: .requestedActivityID)
        requestedActivityFound = try c.decodeIfPresent(Bool.self, forKey: .requestedActivityFound)
    }

    mutating func retainOpenActivities(_ ids: Set<UUID>, from local: Self) {
        guard libraryID == local.libraryID else { return }
        let deleted = deletedRecordIDs.union(local.deletedRecordIDs)
        let retained = ids.subtracting(deleted)
        matches += local.matches.filter { record in retained.contains(record.id) && !matches.contains { $0.id == record.id } }
        trainingSessions += local.trainingSessions.filter { record in retained.contains(record.id) && !trainingSessions.contains { $0.id == record.id } }
        let playerIDs = Set(players.map(\.id)).subtracting(deleted)
        let retainedTournaments = local.tournaments.filter { record in
            retained.contains(record.id) && playerIDs.contains(record.playerID) && !tournaments.contains { $0.id == record.id }
        }
        tournaments += retainedTournaments
        // Only a locally retained tournament needs cached links; a current incoming tournament is authoritative.
        let incomingMatchIDs = Set(matches.map(\.id))
        matches += local.matches.filter { record in
            !deleted.contains(record.id) && playerIDs.contains(record.playerID) && !incomingMatchIDs.contains(record.id)
                && retainedTournaments.contains { $0.id == record.tournamentID && $0.playerID == record.playerID }
        }
    }
}

struct TennisWatchCommandEnvelope: Codable, Equatable {
    var libraryID: UUID?
    var command: TennisWatchSyncCommand
    var courtProtocolVersion = 2

    init(libraryID: UUID?, command: TennisWatchSyncCommand, courtProtocolVersion: Int = 2) {
        self.libraryID = libraryID; self.command = command; self.courtProtocolVersion = courtProtocolVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        libraryID = try c.decodeIfPresent(UUID.self, forKey: .libraryID)
        command = try c.decode(TennisWatchSyncCommand.self, forKey: .command)
        courtProtocolVersion = try c.decodeIfPresent(Int.self, forKey: .courtProtocolVersion) ?? 1
    }

    func isAllowed(in libraryID: UUID) -> Bool {
        if case .requestSnapshot = command { return true }
        return self.libraryID == libraryID
    }
}

struct TennisWatchCommandQueue: Codable {
    var libraryID: UUID?
    var commands: [TennisWatchSyncCommand]
}

struct TennisWatchLibraryFence: Codable, Equatable {
    var current: UUID?
    var retired: Set<UUID> = []

    func canRestoreCachedLibrary(_ libraryID: UUID?) -> Bool {
        guard let libraryID, !retired.contains(libraryID) else { return false }
        return current == nil || current == libraryID
    }

    mutating func accept(_ libraryID: UUID?, authoritative: Bool) -> Bool {
        guard let libraryID, !retired.contains(libraryID) else { return false }
        if current == libraryID { return true }
        // Only the phone's latest application context may replace a library, never a delayed live message.
        guard authoritative else { return false }
        if let current { retired.insert(current) }
        current = libraryID
        return true
    }
}

enum TennisWatchSyncCommand: Codable, Equatable {
    case court(CourtWatchMutation)
    case requestSnapshot
    case requestActivity(UUID)
    case snapshotReceived(Date)
    case upsertMatch(MatchRecord)
    case upsertTraining(TrainingSession)
    case upsertTournament(TournamentRecord)
    case deleteRecord(TennisRecordDeletion)
    case markMatchDetailsComplete(UUID)
    case markTrainingDetailsComplete(UUID)
    case markTournamentDetailsComplete(UUID)
}

enum TennisRecordConflictResolver {
    static func shouldReplace(incomingRevision: Int, incomingModifiedAt: Date, existingRevision: Int, existingModifiedAt: Date) -> Bool {
        if incomingRevision != existingRevision {
            return incomingRevision > existingRevision
        }
        // The existing wire format carries whole seconds. Compare at that precision
        // so an encoded acknowledgement can acknowledge its local source record.
        return incomingModifiedAt.timeIntervalSince1970.rounded(.down)
            >= existingModifiedAt.timeIntervalSince1970.rounded(.down)
    }

    static func prepareLocalMatch(_ match: MatchRecord, now: Date = Date()) -> MatchRecord {
        var copy = match
        copy.revision += 1
        copy.modifiedAt = now
        return copy
    }

    static func prepareLocalTraining(_ session: TrainingSession, now: Date = Date()) -> TrainingSession {
        var copy = session
        copy.revision += 1
        copy.modifiedAt = now
        return copy
    }

    static func mergeTraining(incoming: TrainingSession, existing: TrainingSession) -> TrainingSession {
        guard incoming.id == existing.id else { return incoming }
        let incomingWins = shouldReplace(incomingRevision: incoming.revision, incomingModifiedAt: incoming.modifiedAt,
            existingRevision: existing.revision, existingModifiedAt: existing.modifiedAt)
        let winner = incomingWins ? incoming : existing
        let other = incomingWins ? existing : incoming
        var merged = winner
        merged.retainManualDuration(from: other)
        // Duration corrections and late Health saves are independent changes to the same activity.
        if merged.workout == nil || (merged.workout?.workoutID == nil && other.workout?.workoutID != nil) {
            merged.workout = other.workout ?? merged.workout
        }
        if merged.trackedOnWatch == nil { merged.trackedOnWatch = other.trackedOnWatch }
        if merged.actualStart == nil { merged.actualStart = other.actualStart }
        if merged.actualFinish == nil, let finish = other.actualFinish {
            merged.actualFinish = finish
            if merged.durationSource != .manual { merged.durationMinutes = other.durationMinutes }
        }
        if merged != winner {
            merged.revision = max(incoming.revision, existing.revision) + 1
            merged.modifiedAt = max(incoming.modifiedAt, existing.modifiedAt)
        }
        return merged
    }

    static func prepareLocalTournament(_ tournament: TournamentRecord, now: Date = Date()) -> TournamentRecord {
        var copy = tournament
        copy.revision += 1
        copy.modifiedAt = now
        return copy
    }
}

enum TennisWatchActivityFactory {
    static func trainingSession(playerID: UUID, type: TrainingType = .singlesPractice, startDate: Date = Date()) -> TrainingSession {
        var session = TrainingSession(playerID: playerID)
        session.date = startDate
        session.actualStart = startDate
        session.trackedOnWatch = true
        session.hasStartTime = true
        session.durationMinutes = 1
        session.trainingType = type
        session.hasSessionDetails = false
        session.needsDetails = true
        return TennisRecordConflictResolver.prepareLocalTraining(session, now: startDate)
    }

    static func finishTrainingSession(_ session: TrainingSession, finishDate: Date = Date()) -> TrainingSession {
        var finished = session
        finished.actualFinish = max(session.actualStart ?? session.date, finishDate)
        let minutes = Int(ceil(finishDate.timeIntervalSince(session.actualStart ?? session.date) / 60))
        if finished.durationSource != .manual { finished.durationMinutes = max(1, minutes) }
        finished.needsDetails = true
        finished.hasSessionDetails = false
        return TennisRecordConflictResolver.prepareLocalTraining(finished, now: finishDate)
    }

    static func match(player: PlayerProfile, kind: MatchKind, tournament: TournamentRecord? = nil, startDate: Date = Date()) -> MatchRecord {
        var match = MatchRecord(playerID: player.id)
        match.date = startDate
        match.actualStart = startDate
        match.hasStartTime = true
        match.status = .inProgress
        match.matchType = kind
        match.playerName = player.displayName
        match.opponentName = "Opponent"
        match.matchFormat = player.defaultMatchFormat
        match.sightLevel = player.sightLevel
        match.allowedBounces = player.bounceAllowance ?? player.sightLevel.allowedBounces
        match.suddenDeathDeuce = player.playerMode == .blindTennis
        match.tournamentID = tournament?.id
        match.venueID = tournament?.venueID
        match.venue = tournament?.venue ?? ""
        match.location = tournament?.location ?? ""
        match.needsDetails = true
        match.liveScore = TennisScoreState().snapshot
        return TennisRecordConflictResolver.prepareLocalMatch(match, now: startDate)
    }

    static func tournament(playerID: UUID, startDate: Date = Date()) -> TournamentRecord {
        var tournament = TournamentRecord(playerID: playerID)
        tournament.name = "Tournament"
        tournament.date = startDate
        tournament.endDate = startDate
        tournament.actualStart = startDate
        tournament.finalResult = .inProgress
        tournament.needsDetails = true
        tournament.notes = "Created on Apple Watch."
        return TennisRecordConflictResolver.prepareLocalTournament(tournament, now: startDate)
    }

    static func finishMatch(_ match: MatchRecord, score: TennisScoreState, now: Date = Date()) -> MatchRecord {
        var finished = match
        finished.status = .completed
        if let start = match.actualStart { finished.actualFinish = max(start, now) }
        finished.liveScore = nil
        finished.yourSetsWon = score.playerSets
        finished.opponentSetsWon = score.opponentSets
        var scores = score.completedSetScores
        if score.playerGames != 0 || score.opponentGames != 0 { scores.append("\(score.playerGames)-\(score.opponentGames)") }
        finished.setScores = scores.joined(separator: ", ")
        if score.playerSets != score.opponentSets { finished.result = score.playerSets > score.opponentSets ? .win : .loss }
        else if score.playerGames != score.opponentGames { finished.result = score.playerGames > score.opponentGames ? .win : .loss }
        else { finished.result = .draw }
        finished.hadTiebreak = score.isTiebreak || finished.setScores.contains("7-6") || finished.setScores.contains("6-7")
        finished.needsDetails = true
        return TennisRecordConflictResolver.prepareLocalMatch(finished, now: now)
    }
}

extension Date {
    var shortTennisDate: String {
        formatted(date: .abbreviated, time: .omitted)
    }

    var fullTennisDate: String {
        formatted(date: .long, time: .omitted)
    }

    var shortTennisTime: String {
        formatted(date: .omitted, time: .shortened)
    }

    var tennisSummaryDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: self)
    }
}

extension Calendar {
    func dateByKeepingTime(from timeSource: Date, on dateSource: Date) -> Date {
        let time = dateComponents([.hour, .minute, .second], from: timeSource)
        var date = dateComponents([.year, .month, .day], from: dateSource)
        date.hour = time.hour
        date.minute = time.minute
        date.second = time.second
        return self.date(from: date) ?? dateSource
    }
}

extension Int {
    var durationText: String {
        let total = Swift.max(0, self)
        let hours = total / 60
        let minutes = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if minutes > 0 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        return parts.isEmpty ? "0 minutes" : parts.joined(separator: " ")
    }
}

extension JSONEncoder {
    static var tennisTracker: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var tennisTracker: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
