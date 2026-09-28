import Foundation

enum TennisNotificationResult {
    static func draft(_ match: MatchRecord) -> MatchRecord {
        var draft = match; draft.status = .completed
        return draft
    }
    static func applying(_ draft: MatchRecord, to current: MatchRecord) -> MatchRecord? {
        guard draft.id == current.id, current.status != .inProgress else { return nil }
        var updated = current
        updated.status = .completed; updated.liveScore = nil
        updated.matchFormat = draft.matchFormat
        updated.recordedSets = draft.recordedSets; updated.setScores = draft.setScores
        updated.yourSetsWon = draft.yourSetsWon; updated.opponentSetsWon = draft.opponentSetsWon
        updated.result = draft.result; updated.hadTiebreak = draft.hadTiebreak; updated.tiebreakScore = draft.tiebreakScore
        updated.nextPracticeFocus = draft.nextPracticeFocus
        updated.needsDetails = updated.opponentName.isBlank || updated.opponentName == "Opponent" ||
            (updated.matchType == .doubles && (updated.partnerName.isBlank || updated.opponent2Name.isBlank)) || updated.setScores.isBlank
        return updated
    }
}
