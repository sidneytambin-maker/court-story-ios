import Foundation

enum CourtServiceBox: String, Codable, CaseIterable, Identifiable {
    case right = "Right"
    case left = "Left"
    var id: String { rawValue }
    var opposite: Self { self == .right ? .left : .right }
}

// Stored in every score checkpoint so service choices survive undo, backup and sync.
struct CourtDoublesService: Codable, Equatable {
    var firstMembers = [0, 0]
    var rightMembers = [0, 0]
    var serverMember = 0
    var receiverMember: Int? = 0
    var box: CourtServiceBox = .right
    var lastSquashServers: [Int?] = [nil, nil]
    var tableReceivers = [[0, 1], [1, 0]]
    var midpointChanged = false
    var receiverSwaps = [false, false]
    var selectedDecidingBox: CourtServiceBox?

    var isValid: Bool {
        [firstMembers, rightMembers].allSatisfy { $0.count == 2 && $0.allSatisfy { (0...1).contains($0) } }
            && (0...1).contains(serverMember) && (receiverMember.map { (0...1).contains($0) } ?? true)
            && lastSquashServers.count == 2 && lastSquashServers.allSatisfy { $0.map { (0...1).contains($0) } ?? true }
            && tableReceivers.count == 2 && tableReceivers.allSatisfy { Set($0) == Set([0, 1]) }
            && receiverSwaps.count == 2
    }

    mutating func begin(sport: CourtSport, frame: CourtScoreFrame, previous: CourtScoreFrame? = nil) {
        serverMember = firstMembers[frame.server]
        rightMembers = firstMembers
        receiverMember = firstMembers[1 - frame.server]
        box = .right
        midpointChanged = false
        selectedDecidingBox = nil
        receiverSwaps = [false, false]
        if sport == .tableTennis {
            if let old = previous?.doublesService {
                receiverMember = old.tableReceivers[1 - frame.server].firstIndex(of: serverMember)
            }
            rememberTablePair(server: frame.server)
        } else if sport == .squash {
            if let old = previous?.doublesService { serverMember = old.serverMember }
            lastSquashServers[frame.server] = serverMember
        } else if sport == .racquetball || sport == .beachTennis {
            receiverMember = nil
        }
    }

    mutating func advance(sport: CourtSport, rules: CourtScoringRules, from old: CourtScoreFrame, to new: CourtScoreFrame) {
        guard !new.complete else { return }
        if new.gummiarm { return }
        if new.rounds.count != old.rounds.count {
            if rules.system == .tennisGames {
                refreshTennis(sport: sport, rules: rules, frame: new)
            } else {
                begin(sport: sport, frame: new, previous: old)
                if sport == .racketlon { refreshRacketlon(frame: new) }
            }
            return
        }
        switch sport {
        case .tennis, .padel, .beachTennis, .platformTennis:
            if new.serviceTurn != old.serviceTurn { selectedDecidingBox = nil }
            refreshTennis(sport: sport, rules: rules, frame: new)
        case .tableTennis:
            if new.serviceTurn != old.serviceTurn { rotateTable(previousServer: old.server, nextServer: new.server) }
            if !midpointChanged, new.roundsWon.allSatisfy({ $0 == rules.roundsToWin - 1 }), new.points.max() == 5 {
                receiverMember = 1 - (receiverMember ?? 0)
                midpointChanged = true
            }
            rememberTablePair(server: new.server)
        case .badminton:
            if old.server == new.server { rightMembers[old.server] = 1 - rightMembers[old.server] }
            box = new.points[new.server].isMultiple(of: 2) ? .right : .left
            serverMember = member(on: new.server, in: box)
            receiverMember = member(on: 1 - new.server, in: box)
        case .pickleball:
            if new.points[old.server] != old.points[old.server] { rightMembers[old.server] = 1 - rightMembers[old.server] }
            if new.server != old.server { serverMember = rightMembers[new.server] }
            else if new.serverNumber != old.serverNumber { serverMember = 1 - serverMember }
            box = serverMember == rightMembers[new.server] ? .right : .left
            receiverMember = member(on: 1 - new.server, in: box)
        case .squash:
            if new.server != old.server {
                serverMember = lastSquashServers[new.server].map { 1 - $0 } ?? firstMembers[new.server]
                lastSquashServers[new.server] = serverMember
                box = .right
            } else { box = box.opposite }
            receiverMember = member(on: 1 - new.server, in: box)
        case .racquetball:
            serverMember = new.serverNumber == 1 ? firstMembers[new.server] : 1 - firstMembers[new.server]
            // Only the nominated first server serves in the opening service turn.
            if new.server == new.firstServer && new.serviceTurn == 0 { serverMember = firstMembers[new.server] }
            receiverMember = nil
        case .racketlon: refreshRacketlon(frame: new, previous: old)
        case .custom: break
        }
    }

    mutating func refreshTennis(sport: CourtSport, rules: CourtScoringRules, frame: CourtScoreFrame) {
        let deciding = rules.decidingMatchTieBreak && rules.roundsToWin > 1 && frame.roundsWon.allSatisfy { $0 == rules.roundsToWin - 1 }
        let tie = deciding || frame.tennis.isTiebreak || rules.tieBreakAt.map { frame.tennis.playerGames == $0 && frame.tennis.opponentGames == $0 } == true
        let total = frame.points.reduce(0, +)
        let turn = frame.serviceTurn + (tie ? (total + 1) / 2 : 0)
        serverMember = (firstMembers[frame.server] + turn / 2) % 2
        box = total.isMultiple(of: 2) ? .right : .left
        if tie && sport == .platformTennis { box = box.opposite }
        if isDecidingPoint(rules: rules, frame: frame), let selectedDecidingBox { box = selectedDecidingBox }
        receiverMember = sport == .beachTennis ? nil : member(on: 1 - frame.server, in: box)
    }

    mutating func correctPoints(sport: CourtSport, rules: CourtScoringRules, from old: CourtScoreFrame, to new: CourtScoreFrame) {
        switch sport {
        case .tennis, .padel, .beachTennis, .platformTennis:
            if !isDecidingPoint(rules: rules, frame: new) { selectedDecidingBox = nil }
            refreshTennis(sport: sport, rules: rules, frame: new)
        case .tableTennis:
            let difference = new.serviceTurn - old.serviceTurn
            for _ in 0..<(abs(difference) % 4) {
                if difference > 0 { rotateTable(previousServer: old.server, nextServer: new.server) }
                else {
                    let receiver = serverMember
                    serverMember = 1 - (receiverMember ?? 0)
                    receiverMember = receiver
                }
            }
            let changedEnds = new.roundsWon.allSatisfy { $0 == rules.roundsToWin - 1 } && (new.points.max() ?? 0) >= 5
            if changedEnds != midpointChanged {
                receiverMember = 1 - (receiverMember ?? 0)
                midpointChanged = changedEnds
            }
            rememberTablePair(server: new.server)
        case .badminton:
            // A point correction is not another rally or service handover.
            box = new.points[new.server].isMultiple(of: 2) ? .right : .left
            rightMembers[new.server] = box == .right ? serverMember : 1 - serverMember
            receiverMember = member(on: 1 - new.server, in: box)
        case .pickleball:
            for side in 0..<2 where (new.points[side] - old.points[side]) % 2 != 0 {
                rightMembers[side] = 1 - rightMembers[side]
            }
            box = serverMember == rightMembers[new.server] ? .right : .left
            receiverMember = member(on: 1 - new.server, in: box)
        case .squash, .racquetball, .racketlon, .custom: break
        }
    }

    func isDecidingPoint(rules: CourtScoringRules, frame: CourtScoreFrame) -> Bool {
        guard rules.system == .tennisGames, !frame.tennis.isTiebreak,
              !(rules.decidingMatchTieBreak && rules.roundsToWin > 1 && frame.roundsWon.allSatisfy { $0 == rules.roundsToWin - 1 }),
              frame.points[0] == frame.points[1] else { return false }
        return rules.deuce == .noAd && frame.points[0] >= 3 || rules.deuce == .starPoint && frame.points[0] >= 5
    }

    private func member(on side: Int, in box: CourtServiceBox) -> Int {
        box == .right ? rightMembers[side] : 1 - rightMembers[side]
    }

    mutating func rotateTable(previousServer: Int, nextServer: Int) {
        let previousMember = serverMember
        serverMember = receiverMember ?? firstMembers[nextServer]
        receiverMember = 1 - previousMember
    }

    mutating func rememberTablePair(server: Int) {
        guard let receiverMember else { return }
        tableReceivers[server][serverMember] = receiverMember
        tableReceivers[server][1 - serverMember] = 1 - receiverMember
        tableReceivers[1 - server][receiverMember] = 1 - serverMember
        tableReceivers[1 - server][1 - receiverMember] = serverMember
    }

    mutating func refreshRacketlon(frame: CourtScoreFrame, previous: CourtScoreFrame? = nil) {
        let total = frame.points.reduce(0, +)
        let deuce = frame.points.allSatisfy { $0 >= 20 }
        let turn = frame.serviceTurn
        if frame.disciplineIndex == 0 {
            if let previous, previous.serviceTurn != turn { rotateTable(previousServer: previous.server, nextServer: frame.server) }
            if !midpointChanged && frame.points.max() == 11 {
                receiverMember = 1 - (receiverMember ?? 0); midpointChanged = true
            }
            box = .right
            rememberTablePair(server: frame.server)
            return
        }
        serverMember = (firstMembers[frame.server] + turn / 2) % 2
        box = total.isMultiple(of: 2) ? .right : .left
        if frame.disciplineIndex == 2 {
            // FIR doubles squash is two consecutive singles halves, not WSF doubles.
            let secondHalf = (frame.points.max() ?? 0) >= 11
            serverMember = (firstMembers[frame.server] + (secondHalf ? 1 : 0)) % 2
            receiverMember = (firstMembers[1 - frame.server] + (secondHalf ? 1 : 0)) % 2
        } else if frame.disciplineIndex == 1 {
            if deuce { box = ((total - 40) / 4).isMultiple(of: 2) ? .right : .left }
            let receivingOffset = ((turn + 1) / 2 + (deuce ? 0 : total % 2)) % 2
            receiverMember = (firstMembers[1 - frame.server] + receivingOffset + (receiverSwaps[1 - frame.server] ? 1 : 0)) % 2
        } else {
            if deuce { box = ((total - 40) / 2).isMultiple(of: 2) ? .right : .left }
            receiverMember = member(on: 1 - frame.server, in: box)
        }
    }

    mutating func chooseRacketlonReceiverSwap(side: Int, frame: CourtScoreFrame) {
        receiverSwaps[side].toggle()
        rightMembers[side] = 1 - rightMembers[side]
        refreshRacketlon(frame: frame)
    }
}

extension CourtScoreSession {
    var hasDoublesMembers: Bool { sport.sport != .custom && sides.count == 2 && sides.allSatisfy { $0.members.count == 2 } }

    var serviceSummary: String {
        guard !frame.complete, let service = frame.doublesService, hasDoublesMembers else {
            return "Serving: \(sides[frame.server].name)." + (rules.doublesTwoServers ? " Server \(frame.serverNumber)." : "")
        }
        let server = sides[frame.server].members[service.serverMember]
        let receiver = service.receiverMember.map { sides[1 - frame.server].members[$0] }
        var text = "Serving: \(server), \(sides[frame.server].name)."
        if sport.sport != .racquetball && sport.sport != .beachTennis { text += " \(service.box.rawValue) service court." }
        text += receiver.map { " Receiving: \($0)." } ?? " Either opposing player may receive."
        if rules.doublesTwoServers { text += " Server \(frame.serverNumber)." }
        if service.isDecidingPoint(rules: rules, frame: frame), sport.sport != .beachTennis {
            text += service.selectedDecidingBox == nil ? " Receiving pair chooses the deciding-point court; apply any competition mixed-doubles restriction." : " Deciding-point court selected."
        }
        return text
    }
}
