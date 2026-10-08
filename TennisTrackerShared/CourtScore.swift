import Foundation

struct CourtScoreSide: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var members: [String] = []
}

struct CourtScoreRound: Codable, Equatable {
    var points: [Int]
    var discipline: String?
    var tieBreak: [Int]?
    var unfinished = false
}

struct CourtScoreFrame: Codable, Equatable {
    var points: [Int]
    var roundsWon: [Int]
    var rounds: [CourtScoreRound] = []
    var aggregate: [Int]
    var server = 0
    var serverNumber = 1
    var firstServer = 0
    var serviceTurn = 0
    var disciplineIndex = 0
    var gummiarm = false
    var gummiarmPlayed = false
    var complete = false
    var winningSide: Int?
    var tennis = TennisScoreSnapshot()

    init(count: Int) {
        points = Array(repeating: 0, count: count)
        roundsWon = points
        aggregate = points
    }
}

// Extends the existing tennis engine and ports the shared Android point/aggregate
// rules. All mutations checkpoint the complete state, including service and undo.
struct CourtScoreSession: Codable, Equatable {
    var sport: CourtSportSelection
    var rules: CourtScoringRules
    var sides: [CourtScoreSide]
    private(set) var frame: CourtScoreFrame
    private(set) var history: [CourtScoreFrame] = []

    init(sport: CourtSportSelection, rules: CourtScoringRules, sides: [CourtScoreSide]) {
        self.sport = sport; self.rules = rules; self.sides = sides
        frame = CourtScoreFrame(count: sides.count)
        frame.serverNumber = rules.doublesTwoServers ? 2 : 1
    }

    var validationMessage: String? {
        if !sport.isValid { return "Name the custom sport." }
        if let error = rules.validationMessage { return error }
        if !(2...12).contains(sides.count) || (sport.sport != .custom && sides.count != 2) { return "Choose two sides, or 2 to 12 sides for a custom sport." }
        if sport.sport == .custom && (rules.system == .tennisGames || rules.system == .aggregate) { return "Custom sports use numeric rally or side-out scoring." }
        if Set(sides.map(\.id)).count != sides.count || sides.contains(where: { $0.name.isBlank || $0.members.count > 12 }) { return "Give each side a name and unique identity." }
        let names = sides.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if Set(names).count != names.count { return "Use distinct side names." }
        if !valid(frame) || history.contains(where: { !valid($0) }) { return "The saved score needs correction." }
        return nil
    }

    private func valid(_ value: CourtScoreFrame) -> Bool {
        let count = sides.count
        guard value.points.count == count, value.roundsWon.count == count, value.aggregate.count == count,
              [value.points, value.roundsWon, value.aggregate].allSatisfy({ $0.allSatisfy { (0...1000000).contains($0) } }),
              sides.indices.contains(value.server), sides.indices.contains(value.firstServer),
              (1...2).contains(value.serverNumber), (0...3).contains(value.disciplineIndex),
              value.winningSide.map({ sides.indices.contains($0) }) ?? true else { return false }
        return value.rounds.allSatisfy { $0.points.count == count && $0.points.allSatisfy { (0...1000000).contains($0) } }
    }

    private mutating func checkpoint() {
        history.append(frame)
        if history.count > 10000 { history.removeFirst(history.count - 10000) }
    }

    @discardableResult
    mutating func awardRally(to side: Int) -> Bool {
        guard validationMessage == nil, sides.indices.contains(side), !frame.complete else { return false }
        checkpoint()
        if rules.system == .tennisGames { tennisPoint(to: side); return true }
        if rules.system == .aggregate { aggregatePoint(to: side); return true }
        let serving = frame.server
        if rules.system != .sideOut || side == serving { frame.points[side] += 1 }
        updateService(winner: side, previousServer: serving)
        if isWinningScore(frame.points, side: side) {
            frame.rounds.append(CourtScoreRound(points: frame.points))
            frame.roundsWon[side] += 1
            frame.complete = frame.roundsWon[side] >= rules.roundsToWin
            frame.winningSide = frame.complete ? side : nil
            frame.points = Array(repeating: 0, count: sides.count)
            frame.server = rules.service == .alternateTwo ? (frame.firstServer + 1) % sides.count : side
            frame.firstServer = frame.server
            frame.serviceTurn = 0
            frame.serverNumber = rules.doublesTwoServers ? 2 : 1
        }
        return true
    }

    private func isWinningScore(_ points: [Int], side: Int) -> Bool {
        let others = points.enumerated().filter { $0.offset != side }.map(\.element)
        guard let runnerUp = others.max(), points[side] >= rules.target, points[side] > runnerUp else { return false }
        return points[side] - runnerUp >= rules.winBy || rules.cap.map { points[side] >= $0 } == true
    }

    private mutating func updateService(winner: Int, previousServer: Int) {
        switch rules.service {
        case .sideOut:
            if winner != previousServer {
                if rules.doublesTwoServers && frame.serverNumber == 1 { frame.serverNumber = 2 }
                else { frame.server = winner; frame.serverNumber = 1 }
            }
        case .rallyWinner: frame.server = winner
        case .alternateTwo:
            let count = frame.points.reduce(0, +)
            if count % 2 == 0 || frame.points.allSatisfy({ $0 >= rules.target - 1 }) {
                frame.server = (previousServer + 1) % sides.count
                frame.serviceTurn += 1
            }
        case .games, .manual: break
        }
    }

    private mutating func tennisPoint(to side: Int) {
        let previous = frame.tennis
        let deciding = rules.decidingMatchTieBreak && rules.roundsToWin > 1 &&
            previous.playerSets == rules.roundsToWin - 1 && previous.opponentSets == rules.roundsToWin - 1
        let tie = deciding || previous.isTiebreak || rules.tieBreakAt.map { previous.playerGames == $0 && previous.opponentGames == $0 } == true
        var engine = TennisScoringEngine(suddenDeathDeuce: rules.deuce == .noAd,
            tieBreakRule: rules.tieBreakAt == nil ? .noAutomatic : .standardAtSixAll,
            tieBreakTarget: rules.tieBreakTarget, setsNeededToWin: rules.roundsToWin, snapshot: previous)
        engine.gamesNeededToWinSet = rules.gamesPerSet
        engine.automaticTieBreakAt = rules.tieBreakAt
        engine.starPoint = rules.deuce == .starPoint
        engine.decidingMatchTieBreak = rules.decidingMatchTieBreak
        engine.decidingTieBreakTarget = rules.decidingTieBreakTarget
        _ = engine.awardPoint(to: side == 0 ? .player : .opponent)
        let next = engine.state.snapshot
        let gameEnded = next.playerGames + next.opponentGames != previous.playerGames + previous.opponentGames || next.completedSetScores.count > previous.completedSetScores.count
        if next.completedSetScores.count > previous.completedSetScores.count {
            let parts = next.completedSetScores.last?.split(separator: "-").compactMap { Int($0) } ?? []
            let tiePoints = [previous.playerPoints + (side == 0 ? 1 : 0), previous.opponentPoints + (side == 1 ? 1 : 0)]
            frame.rounds.append(CourtScoreRound(points: parts, tieBreak: tie ? tiePoints : nil))
        }
        if gameEnded {
            frame.serviceTurn += 1
            frame.server = (frame.firstServer + frame.serviceTurn) % 2
        } else if tie {
            let played = next.playerPoints + next.opponentPoints
            let offset = (played + 1) / 2
            frame.server = (frame.firstServer + frame.serviceTurn + offset) % 2
        }
        frame.tennis = next
        frame.points = [next.playerPoints, next.opponentPoints]
        frame.roundsWon = [next.playerSets, next.opponentSets]
        frame.complete = next.isMatchComplete
        frame.winningSide = next.isMatchComplete ? (next.playerSets > next.opponentSets ? 0 : 1) : nil
    }

    private mutating func aggregatePoint(to side: Int) {
        if frame.gummiarm {
            frame.gummiarmPlayed = true; frame.complete = true; frame.winningSide = side
            return
        }
        frame.points[side] += 1; frame.aggregate[side] += 1
        updateService(winner: side, previousServer: frame.server)
        let a = frame.points[0], b = frame.points[1], difference = frame.aggregate[0] - frame.aggregate[1]
        let remaining = 3 - frame.disciplineIndex
        let clinchA = difference - (max(21, a + 2) - b) - remaining * 21 > 0
        let clinchB = -difference - (max(21, b + 2) - a) - remaining * 21 > 0
        let ended = isWinningScore(frame.points, side: side)
        if ended || clinchA || clinchB {
            frame.rounds.append(CourtScoreRound(points: frame.points, discipline: Self.disciplines[frame.disciplineIndex], unfinished: !ended))
            if ended { frame.roundsWon[side] += 1 }
            if clinchA || clinchB { frame.complete = true; frame.winningSide = clinchA ? 0 : 1; return }
            if frame.disciplineIndex == 3 {
                if difference == 0 { frame.gummiarm = true }
                else { frame.complete = true; frame.winningSide = difference > 0 ? 0 : 1 }
            } else {
                frame.disciplineIndex += 1; frame.points = [0, 0]
                frame.server = 1 - frame.firstServer; frame.firstServer = frame.server; frame.serviceTurn = 0
            }
        }
    }

    static let disciplines = ["Table tennis", "Badminton", "Squash", "Tennis"]

    @discardableResult
    mutating func undo() -> Bool {
        guard let previous = history.popLast() else { return false }
        frame = previous
        return true
    }

    mutating func reset() {
        checkpoint()
        frame = CourtScoreFrame(count: sides.count)
        frame.serverNumber = rules.doublesTwoServers ? 2 : 1
    }

    @discardableResult
    mutating func setServer(_ side: Int, serverNumber: Int = 1) -> Bool {
        guard sides.indices.contains(side), (1...(rules.doublesTwoServers ? 2 : 1)).contains(serverNumber), !frame.complete else { return false }
        checkpoint(); frame.server = side; frame.serverNumber = serverNumber
        if frame.points.allSatisfy({ $0 == 0 }) { frame.firstServer = side }
        return true
    }

    @discardableResult
    mutating func correctPoints(_ points: [Int]) -> Bool {
        guard !frame.complete, points.count == sides.count, points.allSatisfy({ (0...9999).contains($0) }),
              rules.system != .aggregate else { return false }
        if rules.system == .tennisGames {
            let deciding = rules.decidingMatchTieBreak && frame.tennis.playerSets == rules.roundsToWin - 1 && frame.tennis.opponentSets == rules.roundsToWin - 1
            let target = deciding ? rules.decidingTieBreakTarget : frame.tennis.isTiebreak ? rules.tieBreakTarget : 4
            let margin = frame.tennis.isTiebreak || deciding || rules.deuce == .advantage ? 2 : 1
            let high = points.max() ?? 0, low = points.min() ?? 0
            if high >= target && high - low >= margin { return false }
            if rules.deuce == .starPoint && !frame.tennis.isTiebreak && !deciding && high > 5 { return false }
        } else if points.indices.contains(where: { isWinningScore(points, side: $0) }) || rules.cap.map({ (points.max() ?? 0) >= $0 }) == true { return false }
        checkpoint()
        frame.points = points
        if rules.system == .tennisGames { frame.tennis.playerPoints = points[0]; frame.tennis.opponentPoints = points[1] }
        return true
    }

    @discardableResult
    mutating func recordResult(_ rounds: [CourtScoreRound], decidingWinner: Int? = nil) -> String? {
        if let error = CourtRecordedResult.validation(rounds, sport: sport, rules: rules, sides: sides.count, decidingWinner: decidingWinner) { return error }
        checkpoint()
        frame = CourtScoreFrame(count: sides.count)
        frame.rounds = rounds
        for round in rounds {
            for side in sides.indices { frame.aggregate[side] += round.points[side] }
            if let winner = CourtRecordedResult.winner(round), !round.unfinished { frame.roundsWon[winner] += 1 }
        }
        let values = rules.system == .aggregate ? frame.aggregate : frame.roundsWon
        let high = values.max() ?? 0
        let leaders = values.indices.filter { values[$0] == high }
        frame.complete = true
        frame.winningSide = leaders.count == 1 ? leaders[0] : decidingWinner
        frame.gummiarmPlayed = decidingWinner != nil
        return nil
    }

    var summary: String {
        guard validationMessage == nil else { return validationMessage ?? "Score unavailable" }
        if frame.complete, let winner = frame.winningSide {
            return "\(sides[winner].name) wins. " + resultSummary
        }
        if rules.system == .aggregate {
            let current = frame.gummiarm ? "Gummiarm, one deciding point. Toss for service, one serve only."
                : "\(Self.disciplines[frame.disciplineIndex]), \(numericSummary(frame.points))."
            return current + " Aggregate \(numericSummary(frame.aggregate)). Serving: \(sides[frame.server].name)."
        }
        if rules.system == .tennisGames {
            return TennisScoreState(snapshot: frame.tennis).spokenScore(playerName: sides[0].name, opponentName: sides[1].name,
                suddenDeathDeuce: rules.deuce == .noAd || (rules.deuce == .starPoint && min(frame.points[0], frame.points[1]) >= 5))
                + ". Serving: \(sides[frame.server].name)."
        }
        return "\(numericSummary(frame.points)). Games \(numericSummary(frame.roundsWon)). Serving: \(sides[frame.server].name)"
            + (rules.doublesTwoServers ? ", server \(frame.serverNumber)." : ".")
    }

    var resultSummary: String {
        if rules.system == .aggregate { return "Aggregate \(numericSummary(frame.aggregate))" + (frame.gummiarmPlayed ? ", Gummiarm point won." : ".") }
        return frame.rounds.map {
            $0.points.map(String.init).joined(separator: "-") + ($0.tieBreak.map { " (tie-break " + $0.map(String.init).joined(separator: "-") + ")" } ?? "") + ($0.unfinished ? " unfinished" : "")
        }.joined(separator: ", ")
    }

    private func numericSummary(_ values: [Int]) -> String {
        zip(sides, values).map { "\($0.name) \($1)" }.joined(separator: ", ")
    }
}
