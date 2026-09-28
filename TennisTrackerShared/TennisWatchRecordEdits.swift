import Foundation

enum TennisWatchRecordEdits {
    static func training(_ draft: TrainingSession, current: TrainingSession, durationWasEdited: Bool = false, now: Date = Date()) -> TrainingSession {
        var updated = current
        updated.retainManualDuration(from: draft)
        // Wire timestamps have whole-second precision. An explicit edit of the unchanged revision
        // can still change minutes within that second; a newer phone revision keeps precedence.
        if durationWasEdited, draft.durationMinutes > 0,
           draft.durationSource == .manual, current.durationSource == .manual,
           draft.durationEditedAt != nil, draft.durationEditedAt == current.durationEditedAt,
           draft.revision == current.revision {
            updated.durationMinutes = draft.durationMinutes
        }
        // A planned duration is not a recorded-workout correction. Copy it only after an explicit edit,
        // and only while both versions are untracked, so a stale form cannot replace live timing.
        if durationWasEdited, draft.durationMinutes > 0,
           draft.durationSource == .recorded, current.durationSource == .recorded,
           draft.actualStart == nil, draft.actualFinish == nil, draft.workout == nil,
           current.actualStart == nil, current.actualFinish == nil, current.workout == nil {
            updated.durationMinutes = draft.durationMinutes
        }
        updated.trainingType = draft.trainingType
        updated.focus = draft.focus
        updated.additionalFocus = draft.additionalFocus
        updated.context = draft.context
        updated.venue = draft.venue
        updated.location = draft.location
        updated.notes = draft.notes
        updated.sessionOutcome = draft.sessionOutcome
        updated.effortLevel = draft.effortLevel
        updated.hasSessionDetails = draft.hasSessionDetails
        updated.needsDetails = draft.needsDetails
        if !draft.needsDetails { updated.markDetailsComplete() }
        return TennisRecordConflictResolver.prepareLocalTraining(updated, now: now)
    }

    static func match(_ draft: MatchRecord, current: MatchRecord, now: Date = Date()) -> MatchRecord {
        var updated = current
        updated.opponentID = draft.opponentID; updated.opponentName = draft.opponentName
        updated.partnerID = draft.partnerID; updated.partnerName = draft.partnerName
        updated.opponent2ID = draft.opponent2ID; updated.opponent2Name = draft.opponent2Name
        updated.venueID = draft.venueID; updated.venue = draft.venue; updated.location = draft.location
        updated.tournamentID = draft.tournamentID; updated.notes = draft.notes
        updated.customTournamentName = draft.customTournamentName
        updated.trainingSessionID = draft.trainingSessionID
        updated.courtSurface = draft.courtSurface
        updated.environment = draft.environment
        updated.matchConditions = draft.matchConditions
        updated.nextPracticeFocus = draft.nextPracticeFocus
        updated.matchNeedsWork = draft.matchNeedsWork
        if current.status == .completed && draft.status == .completed {
            updated.date = draft.date
            updated.matchType = draft.matchType
            updated.matchFormat = draft.matchFormat
            updated.result = draft.result
            updated.yourSetsWon = draft.yourSetsWon
            updated.opponentSetsWon = draft.opponentSetsWon
            updated.setScores = draft.setScores
            updated.recordedSets = draft.recordedSets
            updated.hadTiebreak = draft.hadTiebreak
            updated.tiebreakScore = draft.tiebreakScore
            if draft.matchType == .singles {
                updated.partnerID = nil; updated.partnerName = ""
                updated.opponent2ID = nil; updated.opponent2Name = ""
            }
        }
        updated.needsDetails = draft.needsDetails
        return TennisRecordConflictResolver.prepareLocalMatch(updated, now: now)
    }

    static func tournament(_ draft: TournamentRecord, current: TournamentRecord, now: Date = Date()) -> TournamentRecord {
        var updated = current
        updated.name = draft.name
        updated.date = draft.date; updated.endDate = max(draft.date, draft.endDate)
        updated.venueID = draft.venueID; updated.venue = draft.venue; updated.location = draft.location
        updated.notes = draft.notes; updated.stageReached = draft.stageReached
        updated.finishingPosition = draft.finishingPosition
        updated.needsDetails = draft.needsDetails
        return TennisRecordConflictResolver.prepareLocalTournament(updated, now: now)
    }
}
