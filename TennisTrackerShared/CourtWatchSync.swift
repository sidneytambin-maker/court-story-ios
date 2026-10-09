import Foundation

enum CourtWatchMutation: Codable, Equatable {
    case onboarding(PlayerProfile, AppSettings)
    case profile(PlayerProfile)
    case observation(CourtObservation)
    case drill(CourtMeasuredDrill)
    case deleteCoaching(UUID)

    var id: UUID {
        switch self {
        case .onboarding(let profile, _): return profile.id
        case .profile(let value): return value.id
        case .observation(let value): return value.id
        case .drill(let value): return value.id
        case .deleteCoaching(let id): return id
        }
    }

    @discardableResult
    func apply(to data: inout AppData) -> Bool {
        switch self {
        case .onboarding(let profile, let settings):
            guard data.players.isEmpty, !data.onboardingCompleted, !profile.name.isBlank else { return false }
            data.players = [profile]; data.selectedPlayerID = profile.id
            data.court.ownerPlayerID = profile.id; data.court.deviceOwnerPlayerID = profile.id
            data.settings = settings; data.onboardingCompleted = true
        case .profile(let value):
            guard !value.name.isBlank else { return false }
            if value.isArchived && (data.matches.contains { $0.playerID == value.id && $0.status == .inProgress } ||
                data.trainingSessions.contains { $0.playerID == value.id && $0.isActive } ||
                data.tournaments.contains { $0.playerID == value.id && $0.actualStart != nil && $0.actualFinish == nil }) { return false }
            if let index = data.players.firstIndex(where: { $0.id == value.id }) {
                let old = data.players[index].court, next = value.court
                guard old.coachOwnerID == next.coachOwnerID,
                      TennisRecordConflictResolver.shouldReplace(incomingRevision: next.revision, incomingModifiedAt: next.modifiedAt, existingRevision: old.revision, existingModifiedAt: old.modifiedAt) else { return false }
                data.players[index] = value
            } else { data.players.append(value) }
            if let athleteID = data.court.activeAthleteID, let ownerID = data.court.ownerPlayerID {
                let owner = data.players.first { $0.id == ownerID }
                let athlete = data.players.first { $0.id == athleteID }
                if athlete?.isArchived != false || owner?.court.selected.role != .coach ||
                    athlete?.court.sports.contains(where: { $0.sport == owner?.selectedSport }) != true {
                    data.court.activeAthleteID = nil
                    data.selectedPlayerID = ownerID
                }
            }
        case .observation(let value):
            guard !data.court.deletedIDs.contains(value.id), CourtFeature.observations.isAvailable(in: data.settings.trackingMode) else { return false }
            if let old = data.court.observations.first(where: { $0.id == value.id }), !TennisRecordConflictResolver.shouldReplace(incomingRevision: value.revision, incomingModifiedAt: value.modifiedAt, existingRevision: old.revision, existingModifiedAt: old.modifiedAt) { return false }
            data.court.observations.removeAll { $0.id == value.id }; data.court.observations.append(value)
        case .drill(let value):
            guard !data.court.deletedIDs.contains(value.id), CourtFeature.measuredDrills.isAvailable(in: data.settings.trackingMode) else { return false }
            if let old = data.court.drills.first(where: { $0.id == value.id }), !TennisRecordConflictResolver.shouldReplace(incomingRevision: value.revision, incomingModifiedAt: value.modifiedAt, existingRevision: old.revision, existingModifiedAt: old.modifiedAt) { return false }
            data.court.drills.removeAll { $0.id == value.id }; data.court.drills.append(value)
        case .deleteCoaching(let id):
            data.court.observations.removeAll { $0.id == id }
            data.court.drills.removeAll { $0.id == id }
            data.court.media.removeAll { $0.id == id }
            data.court.deletedIDs.insert(id)
        }
        return true
    }

    func isAcknowledged(in data: AppData) -> Bool {
        switch self {
        case .onboarding(let value, _): return data.players.contains { $0.id == value.id }
        case .profile(let value):
            guard let current = data.players.first(where: { $0.id == value.id }) else { return false }
            return TennisRecordConflictResolver.shouldReplace(incomingRevision: current.court.revision, incomingModifiedAt: current.court.modifiedAt, existingRevision: value.court.revision, existingModifiedAt: value.court.modifiedAt)
        case .observation(let value):
            if data.court.deletedIDs.contains(value.id) { return true }
            guard let current = data.court.observations.first(where: { $0.id == value.id }) else { return false }
            return TennisRecordConflictResolver.shouldReplace(incomingRevision: current.revision, incomingModifiedAt: current.modifiedAt, existingRevision: value.revision, existingModifiedAt: value.modifiedAt)
        case .drill(let value):
            if data.court.deletedIDs.contains(value.id) { return true }
            guard let current = data.court.drills.first(where: { $0.id == value.id }) else { return false }
            return TennisRecordConflictResolver.shouldReplace(incomingRevision: current.revision, incomingModifiedAt: current.modifiedAt, existingRevision: value.revision, existingModifiedAt: value.modifiedAt)
        case .deleteCoaching(let id): return data.court.deletedIDs.contains(id)
        }
    }
}

extension TennisWatchSnapshot {
    func scoped(playerID: UUID?, sport: CourtSportSelection) -> Self {
        var result = self
        result.selectedPlayerID = playerID
        result.matches = matches.filter { $0.playerID == playerID && $0.court.sport == sport }
        result.trainingSessions = trainingSessions.filter { $0.playerID == playerID && $0.court.sport == sport }
        result.tournaments = tournaments.filter { $0.playerID == playerID && $0.court.sport == sport }
        result.achievementHistory = achievementRecords.filter { ($0.playerID == playerID || $0.coachID == playerID) && ($0.courtSport ?? .tennis) == sport }
        return result
    }

    func mayUseHealth(for playerID: UUID) -> Bool {
        guard let player = players.first(where: { $0.id == playerID }) else { return false }
        let owner = court.deviceOwnerPlayerID ?? (courtProtocolVersion < 2 ? selectedPlayerID : nil)
        return owner == playerID && player.court.coachOwnerID == nil
    }

    var courtLibrary: AppData {
        var data = AppData()
        data.libraryID = libraryID ?? data.libraryID
        data.players = players; data.selectedPlayerID = selectedPlayerID
        data.matches = matches; data.trainingSessions = trainingSessions; data.tournaments = tournaments
        data.settings = settings; data.setup = setup; data.court = court; data.deletedRecordIDs = deletedRecordIDs
        return data
    }

    mutating func applyCourtLibrary(_ data: AppData) { players = data.players; court = data.court; selectedPlayerID = data.selectedPlayerID; settings = data.settings }

    var legacyCompatible: Self {
        var legacy = self
        let owner = court.deviceOwnerPlayerID ?? selectedPlayerID
        legacy.selectedPlayerID = owner
        legacy.players = players.filter { $0.court.coachOwnerID == nil }
        legacy.matches = matches.filter { $0.playerID == owner && !$0.usesCourtScoring }
        legacy.trainingSessions = trainingSessions.filter { $0.playerID == owner && $0.court.sport == .tennis }
        legacy.tournaments = tournaments.filter { $0.playerID == owner && $0.court.sport == .tennis }
        legacy.achievementHistory = achievementHistory.filter {
            $0.playerID == owner && ($0.courtSport ?? .tennis) == .tennis && $0.usesCourtScoring != true
        }
        if let id = requestedActivityID {
            legacy.requestedActivityFound = !deletedRecordIDs.contains(id) &&
                (legacy.matches.contains { $0.id == id } || legacy.trainingSessions.contains { $0.id == id } || legacy.tournaments.contains { $0.id == id })
        }
        // Coaching metadata must not be sent to a version that cannot display or preserve it.
        legacy.court = CourtWorkspace()
        legacy.courtProtocolVersion = 1
        return legacy
    }
}

enum CourtSyncCompatibility {
    static func command(_ command: TennisWatchSyncCommand, protocolVersion: Int, data: AppData) -> TennisWatchSyncCommand? {
        guard (1...2).contains(protocolVersion) else { return nil }
        if protocolVersion == 2 { return command }
        func allowed(_ playerID: UUID, _ context: CourtActivity) -> Bool {
            context.sport == .tennis && context.score == nil && context.enteredByCoachID == nil &&
                data.players.contains { $0.id == playerID && $0.court.coachOwnerID == nil }
        }
        switch command {
        case .court: return nil
        case .upsertMatch(var record):
            if let existing = data.matches.first(where: { $0.id == record.id }) {
                guard existing.playerID == record.playerID, !existing.usesCourtScoring, allowed(existing.playerID, existing.court) else { return nil }
                record.court = existing.court
            }
            return !record.usesCourtScoring && allowed(record.playerID, record.court) ? .upsertMatch(record) : nil
        case .upsertTraining(var record):
            if let existing = data.trainingSessions.first(where: { $0.id == record.id }) {
                guard existing.playerID == record.playerID, allowed(existing.playerID, existing.court) else { return nil }
                record.court = existing.court
            }
            return allowed(record.playerID, record.court) ? .upsertTraining(record) : nil
        case .upsertTournament(var record):
            if let existing = data.tournaments.first(where: { $0.id == record.id }) {
                guard existing.playerID == record.playerID, allowed(existing.playerID, existing.court) else { return nil }
                record.court = existing.court
            }
            return allowed(record.playerID, record.court) ? .upsertTournament(record) : nil
        case .deleteRecord(let deletion):
            if data.matches.contains(where: { $0.id == deletion.id && $0.usesCourtScoring }) { return nil }
            let contexts = data.matches.filter { $0.id == deletion.id }.map { ($0.playerID, $0.court) } +
                data.trainingSessions.filter { $0.id == deletion.id }.map { ($0.playerID, $0.court) } +
                data.tournaments.filter { $0.id == deletion.id }.map { ($0.playerID, $0.court) }
            return contexts.allSatisfy { allowed($0.0, $0.1) } ? command : nil
        case .markMatchDetailsComplete(let id): return data.matches.first { $0.id == id }.map { !$0.usesCourtScoring && allowed($0.playerID, $0.court) } == true ? command : nil
        case .markTrainingDetailsComplete(let id): return data.trainingSessions.first { $0.id == id }.map { allowed($0.playerID, $0.court) } == true ? command : nil
        case .markTournamentDetailsComplete(let id): return data.tournaments.first { $0.id == id }.map { allowed($0.playerID, $0.court) } == true ? command : nil
        case .requestSnapshot, .requestActivity, .snapshotReceived: return command
        }
    }
}
