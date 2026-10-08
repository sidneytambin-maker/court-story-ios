import SwiftUI

struct CourtScoreSetupFields: View {
    @Binding var score: CourtScoreSession
    var showsSideNames = true
    var doubles = false
    var showsService = true
    var body: some View {
        if score.sport.sport == .custom {
            Picker("Participants or teams", selection: Binding(get: { score.sides.count }, set: { count in
                var sides = score.sides
                while sides.count < count { sides.append(CourtScoreSide(name: "Side \(sides.count + 1)")) }
                sides = Array(sides.prefix(count))
                score = CourtScoreSession(sport: score.sport, rules: score.rules, sides: sides)
            })) { ForEach(2...12, id: \.self) { Text("\($0)").tag($0) } }
        }
        if showsSideNames {
            ForEach(score.sides.indices, id: \.self) { side in
                TextField("Side \(side + 1) name", text: Binding(get: { score.sides[side].name }, set: { score.sides[side].name = $0 }))
                    .accessibilityIdentifier("courtSideName\(side)")
            }
        }
        NavigationLink("Scoring rules") {
            Form {
                CourtRuleFields(sport: score.sport.sport, rules: Binding(get: { score.rules }, set: {
                    let first = score.frame.firstServer
                    score = CourtScoreSession(sport: score.sport, rules: $0, sides: score.sides)
                    _ = score.setServer(first, serverNumber: $0.doublesTwoServers ? 2 : 1)
                }), doubles: doubles)
            }.navigationTitle("Match rules")
        }.accessibilityValue(score.rules.reference)
        if showsService {
            Picker("First server", selection: Binding(get: { score.frame.server }, set: { _ = score.setServer($0, serverNumber: score.rules.doublesTwoServers ? 2 : 1) })) {
                ForEach(score.sides.indices, id: \.self) { Text(score.sides[$0].name).tag($0) }
            }
        }
        if let error = score.validationMessage { Text(error).accessibilityIdentifier("courtScoreSetupError") }
    }
}

struct CourtScoreControls: View {
    @Binding var score: CourtScoreSession
    var changed: () -> Void
    @State private var confirmReset = false
    @State private var correcting = false
    var body: some View {
        Text(score.summary).font(.headline).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("courtLiveScoreSummary")
        if score.frame.serviceChoicePrompt != nil {
            ForEach(score.sides.indices, id: \.self) { side in
                Button("\(score.sides[side].name) serves first") {
                    if score.setServer(side, serverNumber: score.rules.doublesTwoServers ? 2 : 1) { changed() }
                }
            }
        } else if !score.frame.complete {
            ForEach(score.sides.indices, id: \.self) { side in
                Button("Rally won by \(score.sides[side].name)", systemImage: "plus") {
                    if score.awardRally(to: side) { changed() }
                }.accessibilityIdentifier("courtAwardRally\(side)")
            }
        }
        Button("Undo last score change", systemImage: "arrow.uturn.backward") {
            if score.undo() { changed() }
        }.disabled(score.history.isEmpty).accessibilityIdentifier("courtUndoScore")
        if !score.frame.complete && score.frame.serviceChoicePrompt == nil {
            Picker("Serving side", selection: Binding(get: { score.frame.server }, set: { if score.setServer($0) { changed() } })) {
                ForEach(score.sides.indices, id: \.self) { Text(score.sides[$0].name).tag($0) }
            }
            if score.rules.doublesTwoServers {
                Picker("Server number", selection: Binding(get: { score.frame.serverNumber }, set: { if score.setServer(score.frame.server, serverNumber: $0) { changed() } })) {
                    Text("First server").tag(1); Text("Second server").tag(2)
                }
            }
            if score.rules.system != .aggregate {
                Button("Correct current points", systemImage: "pencil") { correcting = true }
            }
        }
        Button("Reset score", systemImage: "arrow.counterclockwise", role: .destructive) { confirmReset = true }
            .confirmationDialog("Reset all points and rounds?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset score", role: .destructive) { score.reset(); changed() }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $correcting) { CourtPointCorrection(score: $score, changed: changed) }
    }
}

private struct CourtPointCorrection: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var score: CourtScoreSession
    var changed: () -> Void
    @State private var points: [Int] = []
    @State private var error = ""
    @AccessibilityFocusState private var errorFocused: Bool
    var body: some View {
        NavigationStack {
            Form {
                ForEach(points.indices, id: \.self) { side in
                    TextField("\(score.sides[side].name), current points", value: $points[side], format: .number)
                }
                if !error.isEmpty { Text(error).accessibilityFocused($errorFocused) }
            }.navigationTitle("Correct points")
                .onAppear { points = score.frame.points }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if score.correctPoints(points) { changed(); dismiss() }
                            else { error = "This would be a finished or impossible score. Award the deciding rally or correct the recorded rounds instead."; errorFocused = true }
                        }
                    }
                }
        }
    }
}

struct CourtRecordedScoreFields: View {
    @Binding var match: MatchRecord
    @Binding var validationMessage: String
    @State private var score: CourtScoreSession?
    @State private var rounds: [CourtScoreRound] = []
    @State private var decidingWinner: Int?
    var body: some View {
        Group {
            if let score {
                if match.court.sport.sport == .custom {
                    CourtScoreSetupFields(score: Binding(get: { self.score ?? score }, set: { updated in
                        self.score = updated
                        match.court.rules = updated.rules
                        rounds = rounds.map { round in
                            var value = round
                            value.points = Array((round.points + Array(repeating: 0, count: updated.sides.count)).prefix(updated.sides.count))
                            return value
                        }
                        apply()
                    }), showsService: false)
                }
                ForEach(rounds.indices, id: \.self) { index in
                    Text(score.rules.system == .aggregate ? CourtScoreSession.disciplines[min(index, 3)] : "Round \(index + 1)")
                        .font(.headline).accessibilityAddTraits(.isHeader)
                    ForEach(score.sides.indices, id: \.self) { side in
                        NumberChoicePicker(title: "\(score.sides[side].name), \(score.rules.system == .tennisGames ? "games" : "points")", value: $rounds[index].points[side], range: 0...199)
                            .accessibilityIdentifier("courtRound\(index)Side\(side)")
                    }
                    Toggle("Round unfinished", isOn: $rounds[index].unfinished)
                    if score.rules.system == .tennisGames && !rounds[index].unfinished {
                        Toggle("Tie-break played", isOn: Binding(get: { rounds[index].tieBreak != nil }, set: { rounds[index].tieBreak = $0 ? [0, 0] : nil }))
                        if let points = rounds[index].tieBreak {
                            ForEach(score.sides.indices, id: \.self) { side in
                                NumberChoicePicker(title: "\(score.sides[side].name), tie-break points", value: Binding(get: { rounds[index].tieBreak?[side] ?? points[side] }, set: { rounds[index].tieBreak?[side] = $0 }), range: 0...199)
                            }
                        }
                    }
                    Button("Remove round \(index + 1)", systemImage: "trash", role: .destructive) { rounds.remove(at: index) }
                }
                if rounds.count < (score.rules.system == .aggregate ? 4 : (score.rules.roundsToWin - 1) * score.sides.count + 1) {
                    Button("Add round", systemImage: "plus") { rounds.append(CourtScoreRound(points: Array(repeating: 0, count: score.sides.count))) }
                }
                if score.rules.system == .aggregate && rounds.count == 4 {
                    Picker("Gummiarm winner", selection: $decidingWinner) {
                        Text("Not played").tag(Optional<Int>.none)
                        ForEach(score.sides.indices, id: \.self) { Text(score.sides[$0].name).tag(Optional($0)) }
                    }
                }
                if !validationMessage.isEmpty { Text(validationMessage).accessibilityIdentifier("courtRecordedScoreError") }
                else { Text(match.court.score?.summary ?? "Enter the recorded scores.").accessibilityIdentifier("courtRecordedScoreSummary") }
            }
        }
        .onAppear {
            guard score == nil else { return }
            let value = match.makeCourtScore()
            score = value
            decidingWinner = value.frame.gummiarmPlayed ? value.frame.winningSide : nil
            rounds = value.frame.rounds.isEmpty ? [CourtScoreRound(points: Array(repeating: 0, count: value.sides.count))] : value.frame.rounds
            apply()
        }
        .onChange(of: rounds) { _, _ in apply() }
        .onChange(of: decidingWinner) { _, _ in apply() }
        .onChange(of: match.court.rules) { _, rules in
            guard var value = score, let rules, rules != value.rules else { return }
            value.rules = rules; score = value; apply()
        }
        .onChange(of: [match.playerName, match.partnerName, match.opponentName, match.opponent2Name]) { _, _ in
            guard match.court.sport.sport != .custom, var value = score else { return }
            let sides = match.courtScoreSides
            for index in value.sides.indices {
                value.sides[index].name = sides[index].name
                value.sides[index].members = sides[index].members
            }
            score = value; apply()
        }
    }
    private func apply() {
        guard var value = score else { return }
        validationMessage = value.recordResult(rounds, decidingWinner: decidingWinner) ?? ""
        if validationMessage.isEmpty {
            if value.sport.sport == .custom {
                match.playerName = value.sides[0].name
                match.opponentName = value.sides.dropFirst().map(\.name).joined(separator: ", ")
            }
            match.applyCourtScore(value)
        }
    }
}
