import Foundation

enum PointWinner: Codable, Equatable, Hashable {
    case player
    case opponent
}

struct TennisScoreSnapshot: Codable, Equatable {
    var playerPoints = 0
    var opponentPoints = 0
    var playerGames = 0
    var opponentGames = 0
    var playerSets = 0
    var opponentSets = 0
    var completedSetScores: [String] = []
    var isTiebreak = false
    var isMatchComplete = false
    var lastWinner: PointWinner?
}

struct TennisScoreState: Codable, Equatable {
    var playerPoints = 0
    var opponentPoints = 0
    var playerGames = 0
    var opponentGames = 0
    var playerSets = 0
    var opponentSets = 0
    var completedSetScores: [String] = []
    var manualTiebreakActive = false
    var automaticTiebreakActive = false
    var isMatchComplete = false
    var lastWinner: PointWinner?

    var isTiebreak: Bool {
        manualTiebreakActive || automaticTiebreakActive
    }

    var snapshot: TennisScoreSnapshot {
        TennisScoreSnapshot(
            playerPoints: playerPoints,
            opponentPoints: opponentPoints,
            playerGames: playerGames,
            opponentGames: opponentGames,
            playerSets: playerSets,
            opponentSets: opponentSets,
            completedSetScores: completedSetScores,
            isTiebreak: isTiebreak,
            isMatchComplete: isMatchComplete,
            lastWinner: lastWinner
        )
    }

    init() {}

    init(snapshot: TennisScoreSnapshot) {
        playerPoints = snapshot.playerPoints
        opponentPoints = snapshot.opponentPoints
        playerGames = snapshot.playerGames
        opponentGames = snapshot.opponentGames
        playerSets = snapshot.playerSets
        opponentSets = snapshot.opponentSets
        completedSetScores = snapshot.completedSetScores
        manualTiebreakActive = snapshot.isTiebreak
        automaticTiebreakActive = false
        isMatchComplete = snapshot.isMatchComplete
        lastWinner = snapshot.lastWinner
    }

    var pointScore: String {
        pointScore(suddenDeathDeuce: false)
    }

    func pointScore(suddenDeathDeuce: Bool) -> String {
        if isMatchComplete { return "Match complete" }
        if isTiebreak {
            return "Tiebreak \(playerPoints)-\(opponentPoints)"
        }
        if playerPoints >= 3 && opponentPoints >= 3 {
            if suddenDeathDeuce { return "Sudden-death deuce" }
            if playerPoints == opponentPoints { return "Deuce" }
            return playerPoints > opponentPoints ? "Advantage Player" : "Advantage Opponent"
        }
        return "\(pointName(playerPoints))-\(pointName(opponentPoints))"
    }

    func spokenScore(playerName: String = "Player", opponentName: String = "Opponent", suddenDeathDeuce: Bool = false) -> String {
        let sets = "sets \(playerSets)-\(opponentSets)"
        let games = "games \(playerGames)-\(opponentGames)"
        return "\(pointScore(suddenDeathDeuce: suddenDeathDeuce)), \(games), \(sets), \(playerName) against \(opponentName)"
    }

    var spokenScore: String {
        spokenScore()
    }

    private func pointName(_ points: Int) -> String {
        switch points {
        case 0: return "Love"
        case 1: return "15"
        case 2: return "30"
        default: return "40"
        }
    }
}

struct TennisScoringEngine {
    private(set) var state = TennisScoreState()
    private var history: [TennisScoreState] = []
    var playerName = "Player"
    var opponentName = "Opponent"
    var suddenDeathDeuce = false
    var tieBreakRule: TieBreakRule = .standardAtSixAll
    var tieBreakTarget = 7
    var tieBreakWinByTwo = true
    var setsNeededToWin = 2

    init(
        playerName: String = "Player",
        opponentName: String = "Opponent",
        suddenDeathDeuce: Bool = false,
        tieBreakRule: TieBreakRule = .standardAtSixAll,
        tieBreakTarget: Int = 7,
        tieBreakWinByTwo: Bool = true,
        setsNeededToWin: Int = 2,
        snapshot: TennisScoreSnapshot? = nil
    ) {
        self.playerName = playerName.fallback("Player")
        self.opponentName = opponentName.fallback("Opponent")
        self.suddenDeathDeuce = suddenDeathDeuce
        self.tieBreakRule = tieBreakRule
        self.tieBreakTarget = max(1, tieBreakTarget)
        self.tieBreakWinByTwo = tieBreakWinByTwo
        self.setsNeededToWin = max(1, setsNeededToWin)
        if let snapshot {
            self.state = TennisScoreState(snapshot: snapshot)
        }
    }

    mutating func awardPoint(to winner: PointWinner) -> String {
        guard !state.isMatchComplete else { return "Match is already complete. \(fullScore)" }
        history.append(state)
        state.lastWinner = winner
        prepareAutomaticTieBreakIfNeeded()
        switch winner {
        case .player:
            state.playerPoints += 1
        case .opponent:
            state.opponentPoints += 1
        }
        resolvePoint()
        let name = winner == .player ? playerName : opponentName
        let announcement = TennisSummaryFormatter.scoreAnnouncement(
            state: state,
            playerName: playerName,
            opponentName: opponentName,
            suddenDeathDeuce: suddenDeathDeuce
        )
        return "\(announcement) Point to \(name)."
    }

    mutating func startTieBreak() -> String {
        guard !state.isMatchComplete else { return "Match is already complete. \(fullScore)" }
        guard !state.isTiebreak else { return "Tie-break already in progress. \(fullScore)" }
        history.append(state)
        state.playerPoints = 0
        state.opponentPoints = 0
        state.manualTiebreakActive = true
        return "Tie-break started. \(fullScore)"
    }

    mutating func finishTieBreak(winner: PointWinner) -> String {
        guard state.isTiebreak else { return "No tie-break is in progress. \(fullScore)" }
        history.append(state)
        if winner == .player {
            state.playerPoints = max(state.playerPoints, state.opponentPoints + 1, tieBreakTarget)
        } else {
            state.opponentPoints = max(state.opponentPoints, state.playerPoints + 1, tieBreakTarget)
        }
        finishGameAndMaybeSet()
        return "Tie-break finished. \(fullScore)"
    }

    mutating func undo() -> String {
        guard let previous = history.popLast() else {
            return "Nothing to undo. \(fullScore)."
        }
        state = previous
        return "Undone. \(fullScore)"
    }

    mutating func reset() {
        state = TennisScoreState()
        history.removeAll()
    }

    private mutating func resolvePoint() {
        if state.isTiebreak {
            let targetReached = max(state.playerPoints, state.opponentPoints) >= tieBreakTarget
            let margin = abs(state.playerPoints - state.opponentPoints)
            if targetReached && (!tieBreakWinByTwo || margin >= 2) {
                finishGameAndMaybeSet()
            }
            return
        }

        if suddenDeathDeuce && state.playerPoints >= 4 && state.opponentPoints >= 3 && state.playerPoints > state.opponentPoints {
            finishGameAndMaybeSet()
            return
        }
        if suddenDeathDeuce && state.opponentPoints >= 4 && state.playerPoints >= 3 && state.opponentPoints > state.playerPoints {
            finishGameAndMaybeSet()
            return
        }
        if max(state.playerPoints, state.opponentPoints) >= 4 && abs(state.playerPoints - state.opponentPoints) >= 2 {
            finishGameAndMaybeSet()
        }
    }

    private mutating func finishGameAndMaybeSet() {
        if state.playerPoints > state.opponentPoints {
            state.playerGames += 1
        } else {
            state.opponentGames += 1
        }
        state.manualTiebreakActive = false
        state.automaticTiebreakActive = false
        state.playerPoints = 0
        state.opponentPoints = 0
        if setIsComplete {
            finishSet()
        }
    }

    private var setIsComplete: Bool {
        if max(state.playerGames, state.opponentGames) >= 6 && abs(state.playerGames - state.opponentGames) >= 2 {
            return true
        }
        if max(state.playerGames, state.opponentGames) == 7 {
            return true
        }
        return false
    }

    private mutating func prepareAutomaticTieBreakIfNeeded() {
        guard !state.manualTiebreakActive else { return }
        guard state.playerGames == 6 && state.opponentGames == 6 else { return }
        switch tieBreakRule {
        case .standardAtSixAll:
            state.automaticTiebreakActive = true
            tieBreakTarget = 7
        case .tenPoint:
            state.automaticTiebreakActive = true
            tieBreakTarget = 10
        case .manual, .noAutomatic:
            state.automaticTiebreakActive = false
        }
    }

    private mutating func finishSet() {
        state.completedSetScores.append("\(state.playerGames)-\(state.opponentGames)")
        if state.playerGames > state.opponentGames {
            state.playerSets += 1
        } else {
            state.opponentSets += 1
        }
        state.playerGames = 0
        state.opponentGames = 0
        if state.playerSets == setsNeededToWin || state.opponentSets == setsNeededToWin {
            state.isMatchComplete = true
        }
    }

    var scorePhrase: String {
        state.spokenScore(playerName: playerName, opponentName: opponentName, suddenDeathDeuce: suddenDeathDeuce)
    }

    var fullScore: String {
        let leader: String
        if state.playerSets != state.opponentSets {
            leader = state.playerSets > state.opponentSets ? "\(playerName) leads \(opponentName)" : "\(opponentName) leads \(playerName)"
        } else if state.playerGames != state.opponentGames {
            leader = state.playerGames > state.opponentGames ? "\(playerName) leads \(opponentName)" : "\(opponentName) leads \(playerName)"
        } else {
            leader = "\(playerName) and \(opponentName) are level"
        }
        if state.isMatchComplete {
            let winner = state.playerSets > state.opponentSets ? playerName : opponentName
            return "Match complete. \(winner) wins. Final score, \(state.completedSetScores.joined(separator: ", ").fallback("sets \(state.playerSets)-\(state.opponentSets)"))."
        }
        return "\(leader). Current game, \(state.pointScore(suddenDeathDeuce: suddenDeathDeuce)). Games \(state.playerGames)-\(state.opponentGames). Sets \(state.playerSets)-\(state.opponentSets)."
    }
}
