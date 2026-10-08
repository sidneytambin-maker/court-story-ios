import Foundation

struct CourtOfficialFormat: Identifiable, Equatable {
    var id: String
    var title: String
    var rules: CourtScoringRules

    static func choices(for sport: CourtSport, doubles: Bool = false) -> [Self] {
        let base = CourtScoringRules.standard(for: sport, doubles: doubles)
        func format(_ id: String, _ title: String, _ update: (inout CourtScoringRules) -> Void = { _ in }) -> Self {
            var rules = base
            update(&rules)
            rules.customOverride = false
            return Self(id: sport.rawValue + "." + id, title: title, rules: rules)
        }
        switch sport {
        case .tennis:
            return [format("best3", "Best of 3 sets"), format("best5", "Best of 5 sets") { $0.roundsToWin = 3 },
                format("noad-match-tiebreak", "No-ad, deciding 10-point match tie-break") {
                    $0.deuce = .noAd; $0.decidingMatchTieBreak = true
                }]
        case .padel:
            return [format("star", "Best of 3 sets, Star Point"),
                format("advantage", "Best of 3 sets, advantage") { $0.deuce = .advantage },
                format("golden", "Best of 3 sets, Golden Point") { $0.deuce = .noAd }]
        case .pickleball:
            return [format("best3-11", "Best of 3 games to 11, side-out"),
                format("best5-11", "Best of 5 games to 11, side-out") { $0.roundsToWin = 3 },
                format("one-15", "One game to 15, side-out") { $0.roundsToWin = 1; $0.target = 15 },
                format("one-21", "One game to 21, side-out") { $0.roundsToWin = 1; $0.target = 21 }]
        case .badminton: return [format("best3-21", "Best of 3 games to 21")]
        case .squash:
            let name = doubles ? "softball doubles" : "singles"
            return [format("best5", "Best of 5 games to 11, \(name)"),
                format("best3", "Best of 3 games to 11, \(name)") { $0.roundsToWin = 2 }]
        case .tableTennis:
            return [format("best5", "Best of 5 games to 11"),
                format("best3", "Best of 3 games to 11") { $0.roundsToWin = 2 },
                format("best7", "Best of 7 games to 11") { $0.roundsToWin = 4 }]
        case .racquetball: return [format("irf-best5", "IRF best of 5 games to 11, rally scoring")]
        case .racketlon: return [format("fir", "Four sports, 21 points each, aggregate result")]
        case .beachTennis: return [format("itf", "Best of 3 sets, deciding 10-point match tie-break")]
        case .platformTennis: return [format("apta", doubles ? "Best of 3 sets, advantage" : "Best of 3 sets, no-ad singles")]
        case .custom: return []
        }
    }

    static func matching(_ rules: CourtScoringRules, sport: CourtSport, doubles: Bool = false) -> Self? {
        choices(for: sport, doubles: doubles).first { $0.rules.sameScoring(as: rules) }
    }
}

extension CourtScoringRules {
    func sameScoring(as other: Self) -> Bool {
        var a = self, b = other
        a.reference = ""; b.reference = ""; a.sourceURL = ""; b.sourceURL = ""
        a.version = 1; b.version = 1; a.customOverride = false; b.customOverride = false
        return a == b
    }

    var formatSummary: String {
        if system == .aggregate { return "Table tennis, badminton, squash, then tennis. Four games to 21, win by two. Total points decide the match." }
        let length = roundsToWin == 1 ? "One \(system == .tennisGames ? "set" : "game")" : "Best of \(roundsToWin * 2 - 1) \(system == .tennisGames ? "sets" : "games")"
        if system == .tennisGames {
            return "\(length). \(gamesPerSet) games per set, win by two. \(deuce.rawValue). "
                + (tieBreakAt.map { "Tie-break at \($0)-all, to \(tieBreakTarget), win by two. " } ?? "No set tie-break. ")
                + (decidingMatchTieBreak ? "Deciding set: \(decidingTieBreakTarget)-point match tie-break, win by two." : "")
        }
        return "\(length). First to \(target), win by \(winBy). " + (cap.map { "Cap \($0). " } ?? "No cap. ") + system.rawValue + "."
    }
}
