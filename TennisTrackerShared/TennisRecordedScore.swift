import Foundation

struct TennisRecordedSet: Codable, Equatable {
    var yourGames = 0
    var opponentGames = 0
    var hasTiebreak = false
    var yourTiebreak: Int?
    var opponentTiebreak: Int?

    var isEntered: Bool { yourGames > 0 || opponentGames > 0 || (hasTiebreak && (yourTiebreak != nil || opponentTiebreak != nil)) }
    var result: MatchResult {
        if hasTiebreak, let yours = yourTiebreak, let theirs = opponentTiebreak {
            return yours > theirs ? .win : yours < theirs ? .loss : .draw
        }
        return yourGames > opponentGames ? .win : yourGames < opponentGames ? .loss : .draw
    }
    var games: (Int, Int) {
        // A recorded 6-all tie-break winner takes the deciding game. Tied/stopped scores stay tied.
        if hasTiebreak, yourGames == opponentGames, yourTiebreak != nil, opponentTiebreak != nil {
            return (yourGames + (result == .win ? 1 : 0), opponentGames + (result == .loss ? 1 : 0))
        }
        return (yourGames, opponentGames)
    }
    var scoreText: String { "\(games.0)-\(games.1)" }
    var spokenScore: String {
        var text = "\(games.0) games to \(games.1)"
        if hasTiebreak, let yours = yourTiebreak, let theirs = opponentTiebreak {
            text += ", tie-break: your \(yours) points, opponent \(theirs) points"
            if yours == theirs { text += ", tied" }
        }
        return text
    }
}

enum TennisRecordedScore {
    static func sets(from match: MatchRecord) -> [TennisRecordedSet] {
        if !match.recordedSets.isEmpty { return match.recordedSets }
        // Read common historic score notation without changing the saved record on opening an editor.
        let pattern = #"^\s*(\d+)\s*[-\u2013\u2212]\s*(\d+)\s*(?:\(\s*(\d+)\s*[-\u2013\u2212]\s*(\d+)\s*\))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var sets: [TennisRecordedSet] = []
        for part in match.setScores.split(separator: ",") {
            let text = String(part)
            guard let found = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let first = Range(found.range(at: 1), in: text), let second = Range(found.range(at: 2), in: text),
                  let yours = Int(text[first]), let theirs = Int(text[second]) else { return [] }
            let points: (Int) -> Int? = { index in Range(found.range(at: index), in: text).flatMap { Int(text[$0]) } }
            let tie = (min(yours, theirs) >= 6 && abs(yours - theirs) <= 1)
            sets.append(TennisRecordedSet(yourGames: yours, opponentGames: theirs,
                hasTiebreak: points(3) != nil || (tie && match.tieBreakRule != .noAutomatic),
                yourTiebreak: points(3), opponentTiebreak: points(4)))
        }
        return sets
    }

    static func requiredRows(format: MatchFormat, sets: [TennisRecordedSet]) -> Int {
        if format == .oneSet { return 1 }
        var wins = 0, losses = 0
        for (index, set) in sets.prefix(format.maximumSetsToEnter).enumerated() {
            if !set.isEntered { return max(format.defaultSetsToEnter, index + 1) }
            if set.result == .win { wins += 1 }
            if set.result == .loss { losses += 1 }
            if format != .custom && (wins == format.setsNeededToWin || losses == format.setsNeededToWin) { return index + 1 }
        }
        return min(format.maximumSetsToEnter, max(format.defaultSetsToEnter, sets.count + 1))
    }

    static func apply(_ sets: [TennisRecordedSet], to match: inout MatchRecord) {
        let retired = match.result == .retired
        let rows = requiredRows(format: match.matchFormat, sets: sets)
        let entered = Array(sets.prefix(rows)).filter(\.isEntered)
        match.recordedSets = entered
        match.setScores = entered.map(\.scoreText).joined(separator: ", ")
        match.yourSetsWon = entered.filter { $0.result == .win }.count
        match.opponentSetsWon = entered.filter { $0.result == .loss }.count
        match.result = match.yourSetsWon > match.opponentSetsWon ? .win : match.yourSetsWon < match.opponentSetsWon ? .loss : .draw
        if retired { match.result = .retired }
        match.hadTiebreak = entered.contains(where: \.hasTiebreak)
        match.tiebreakScore = entered.enumerated().compactMap { index, set in
            guard set.hasTiebreak, let yours = set.yourTiebreak, let theirs = set.opponentTiebreak else { return nil }
            return "Set \(index + 1): \(yours)-\(theirs)"
        }.joined(separator: "; ")
    }

    static func validationMessage(for match: MatchRecord) -> String? {
        for (index, set) in match.recordedSets.enumerated() {
            if set.hasTiebreak && (set.yourTiebreak == nil || set.opponentTiebreak == nil) {
                return "Set \(index + 1): choose both tie-break point scores, or turn off tie-break if none was played."
            }
            if set.hasTiebreak && set.yourGames != set.opponentGames && set.isEntered {
                let gameResult: MatchResult = set.yourGames > set.opponentGames ? .win : .loss
                if set.result != gameResult { return "Set \(index + 1): the games and tie-break points must show the same winner. For a tied tie-break, enter equal games." }
            }
        }
        return nil
    }
}
