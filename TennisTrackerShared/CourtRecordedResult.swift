import Foundation

enum CourtRecordedResult {
    static func winner(_ round: CourtScoreRound) -> Int? {
        let values = round.tieBreak ?? round.points
        guard let high = values.max() else { return nil }
        let leaders = values.indices.filter { values[$0] == high }
        return leaders.count == 1 ? leaders[0] : nil
    }

    static func validation(_ rounds: [CourtScoreRound], sport: CourtSportSelection, rules: CourtScoringRules, sides: Int, decidingWinner: Int? = nil) -> String? {
        guard rules.validationMessage == nil, (2...12).contains(sides), !rounds.isEmpty,
              rounds.count <= (rules.system == .aggregate ? 4 : rules.roundsToWin * sides) else { return "Check the scoring rules and number of rounds." }
        var wins = Array(repeating: 0, count: sides)
        for (index, round) in rounds.enumerated() {
            let prefix = "Round \(index + 1): "
            guard round.points.count == sides, round.points.allSatisfy({ (0...9999).contains($0) }) else { return prefix + "enter a non-negative score for each side." }
            if wins.contains(where: { $0 >= rules.roundsToWin }) && rules.system != .aggregate { return prefix + "the match was already won in an earlier round." }
            let high = round.points.max() ?? 0
            if high == 0 { return prefix + "enter a score or remove the empty round." }
            if round.unfinished {
                guard index == rounds.count - 1, round.tieBreak == nil else { return prefix + "only the final round can be unfinished." }
                continue
            }
            let target = rules.system == .tennisGames ? rules.gamesPerSet : rules.target
            if let tie = round.tieBreak {
                guard rules.system == .tennisGames, sides == 2, tie.count == 2,
                      tie.allSatisfy({ (0...9999).contains($0) }) else { return prefix + "tie-break points require a games-and-sets sport." }
                let deciding = rules.decidingMatchTieBreak && wins.allSatisfy { $0 == rules.roundsToWin - 1 }
                let tieTarget = deciding ? rules.decidingTieBreakTarget : rules.tieBreakTarget
                guard let tieWinner = winner(CourtScoreRound(points: tie)),
                      validFinish(tie, target: tieTarget, margin: 2, cap: nil) else { return prefix + "the tie-break needs a valid winning score, or mark the round unfinished." }
                if deciding {
                    guard round.points == tie else { return prefix + "record the actual deciding match tie-break points, matching the tie-break score." }
                } else {
                    guard let trigger = rules.tieBreakAt,
                          round.points[tieWinner] == trigger + 1, round.points[1 - tieWinner] == trigger else { return prefix + "the games and tie-break must show the same winner at the configured trigger." }
                }
            } else {
                if rules.system == .tennisGames, rules.decidingMatchTieBreak,
                   wins.allSatisfy({ $0 == rules.roundsToWin - 1 }) {
                    return prefix + "enter the deciding match tie-break points."
                }
                let margin = rules.system == .tennisGames ? 2 : rules.winBy
                guard validFinish(round.points, target: target, margin: margin, cap: rules.system == .tennisGames ? nil : rules.cap) else {
                    return prefix + "the score is not a finished round under these rules. Correct it or mark it unfinished."
                }
                if rules.system == .tennisGames, let trigger = rules.tieBreakAt,
                   (round.points.min() ?? 0) >= trigger { return prefix + "enter the tie-break points for this set." }
            }
            if let side = winner(round) { wins[side] += 1 }
        }
        if let decidingWinner {
            let totals = (0..<sides).map { side in rounds.reduce(0) { $0 + $1.points[side] } }
            guard sport.sport == .racketlon, rounds.count == 4, !(rounds.last?.unfinished ?? true),
                  (0..<sides).contains(decidingWinner), Set(totals).count == 1 else { return "A Gummiarm winner applies only after four tied-aggregate Racketlon games." }
        }
        return nil
    }

    private static func validFinish(_ values: [Int], target: Int, margin: Int, cap: Int?) -> Bool {
        let sorted = values.sorted(by: >)
        guard sorted.count >= 2, sorted[0] > sorted[1], sorted[0] >= target else { return false }
        let high = sorted[0], second = sorted[1]
        if let cap, high > cap { return false }
        if cap == high { return second < high && (high == target || high - second <= margin) }
        return high - second >= margin && (high == target || high - second == margin)
    }
}

extension MatchRecord {
    var usesCourtScoring: Bool { court.sport.sport != .tennis || court.score != nil }

    func makeCourtScore() -> CourtScoreSession {
        if let score = court.score { return score }
        let rules = court.rules ?? .standard(for: court.sport.sport, doubles: matchType == .doubles)
        let yours = CourtScoreSide(name: playerTeam, members: [playerName, partnerName].filter { !$0.isBlank })
        let theirs = CourtScoreSide(name: opponentSummary.fallback("Opponent"), members: [opponentName, opponent2Name].filter { !$0.isBlank })
        return CourtScoreSession(sport: court.sport, rules: rules, sides: [yours, theirs])
    }

    mutating func applyCourtScore(_ score: CourtScoreSession) {
        court.score = score
        court.rules = score.rules
        setScores = score.resultSummary
        yourSetsWon = score.frame.roundsWon.first ?? 0
        opponentSetsWon = score.frame.roundsWon.dropFirst().max() ?? 0
        if score.frame.complete {
            result = score.frame.winningSide.map { $0 == 0 ? .win : .loss } ?? .draw
            status = .completed
            liveScore = nil
        }
    }
}
