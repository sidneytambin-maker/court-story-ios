import Foundation

enum TennisNotificationResult {
    static func draft(_ match: MatchRecord) -> MatchRecord {
        var draft = match; draft.status = .completed
        return draft
    }
    static func applying(_ draft: MatchRecord, to current: MatchRecord) -> MatchRecord? {
        guard draft.id == current.id, current.status != .inProgress, draft.playerID == current.playerID,
              draft.court.sport == current.court.sport else { return nil }
        if draft.usesCourtScoring {
            guard let score = draft.court.score, score.validationMessage == nil, score.frame.complete,
                  CourtRecordedResult.validation(score.frame.rounds, sport: score.sport, rules: score.rules,
                    sides: score.sides.count, decidingWinner: score.frame.gummiarmPlayed ? score.frame.winningSide : nil) == nil else { return nil }
        }
        var updated = current
        updated.status = .completed; updated.liveScore = nil
        updated.matchFormat = draft.matchFormat
        updated.recordedSets = draft.recordedSets; updated.setScores = draft.setScores
        updated.yourSetsWon = draft.yourSetsWon; updated.opponentSetsWon = draft.opponentSetsWon
        updated.result = draft.result; updated.hadTiebreak = draft.hadTiebreak; updated.tiebreakScore = draft.tiebreakScore
        updated.nextPracticeFocus = draft.nextPracticeFocus
        if draft.usesCourtScoring, let score = draft.court.score { updated.applyCourtScore(score) }
        updated.needsDetails = updated.opponentName.isBlank || updated.opponentName == "Opponent" ||
            (updated.matchType == .doubles && (updated.partnerName.isBlank || updated.opponent2Name.isBlank)) || updated.setScores.isBlank
        return updated
    }
}
