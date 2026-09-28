import SwiftUI

struct TennisRecordedScoreFields: View {
    @Binding var match: MatchRecord
    @State private var sets = Array(repeating: TennisRecordedSet(), count: 5)
    @State private var loaded = false

    private var count: Int { TennisRecordedScore.requiredRows(format: match.matchFormat, sets: sets) }
    var body: some View {
        Group {
        ForEach(0..<count, id: \.self) { index in
            #if os(watchOS)
            // Each native Watch picker needs its own Form row and presentation owner.
            Section {
                setFields(index)
            } header: {
                Text("Set \(index + 1)")
            }
            #else
            VStack(alignment: .leading) {
                Text("Set \(index + 1)").font(.headline).accessibilityAddTraits(.isHeader)
                setFields(index)
            }.accessibilityElement(children: .contain)
            #endif
        }
        if !match.setScores.isBlank {
            Toggle("Match ended by retirement", isOn: Binding(
                get: { match.result == .retired },
                set: { retired in
                    match.result = retired ? .retired : .draw
                    if !retired { TennisRecordedScore.apply(sets, to: &match) }
                }))
        }
        if let message = TennisRecordedScore.validationMessage(for: match) {
            Text(message).accessibilityIdentifier("recordedScoreValidation")
        } else if !match.setScores.isBlank {
            Text("\(match.result.rawValue): \(match.setScores)")
                .accessibilityLabel("Recorded result: \(match.result.rawValue). " + summary)
                .accessibilityIdentifier("recordedScoreSummary")
        } else {
            Picker("Result without set scores", selection: $match.result) {
                ForEach(MatchResult.allCases) { Text($0.rawValue).tag($0) }
            }.accessibilityIdentifier("recordedMatchResult")
        }
        }
        .onAppear {
            guard !loaded else { return }
            for (index, set) in TennisRecordedScore.sets(from: match).prefix(5).enumerated() { sets[index] = set }
            loaded = true
        }
        .onChange(of: match.matchFormat) { _, _ in
            guard loaded, !match.recordedSets.isEmpty else { return }
            TennisRecordedScore.apply(sets, to: &match)
        }
    }

    @ViewBuilder
    private func setFields(_ index: Int) -> some View {
        OrderedChoicePicker(title: "Your games", selection: games(index, yours: true), values: Array(0...max(30, sets[index].yourGames))) { "\($0) games" }
            .accessibilityLabel("Set \(index + 1), your games")
            .accessibilityIdentifier("set\(index + 1)YourGames")
        OrderedChoicePicker(title: "Opponent games", selection: games(index, yours: false), values: Array(0...max(30, sets[index].opponentGames))) { "\($0) games" }
            .accessibilityLabel("Set \(index + 1), opponent games")
            .accessibilityIdentifier("set\(index + 1)OpponentGames")
        Toggle("Tie-break played", isOn: field(index, \.hasTiebreak))
            .accessibilityLabel("Set \(index + 1), tie-break played")
            .accessibilityIdentifier("set\(index + 1)Tiebreak")
        if sets[index].hasTiebreak {
            OrderedChoicePicker(title: "Your tie-break points", selection: field(index, \.yourTiebreak),
                values: [Int?.none] + (0...max(50, sets[index].yourTiebreak ?? 0)).map { Optional($0) }) { $0.map { "\($0) points" } ?? "Not recorded" }
                .accessibilityLabel("Set \(index + 1), your tie-break points")
                .accessibilityIdentifier("set\(index + 1)YourTiebreak")
            OrderedChoicePicker(title: "Opponent tie-break points", selection: field(index, \.opponentTiebreak),
                values: [Int?.none] + (0...max(50, sets[index].opponentTiebreak ?? 0)).map { Optional($0) }) { $0.map { "\($0) points" } ?? "Not recorded" }
                .accessibilityLabel("Set \(index + 1), opponent tie-break points")
                .accessibilityIdentifier("set\(index + 1)OpponentTiebreak")
        }
    }

    private var summary: String {
        match.recordedSets.enumerated().map { "Set \($0.offset + 1), \($0.element.spokenScore)." }.joined(separator: " ")
    }

    private func games(_ index: Int, yours: Bool) -> Binding<Int> {
        Binding { yours ? sets[index].yourGames : sets[index].opponentGames } set: { value in
            var set = sets[index]
            let wasSixAll = set.yourGames == 6 && set.opponentGames == 6
            if yours { set.yourGames = value } else { set.opponentGames = value }
            if !wasSixAll && set.yourGames == 6 && set.opponentGames == 6 && match.tieBreakRule != .noAutomatic { set.hasTiebreak = true }
            sets[index] = set
            TennisRecordedScore.apply(sets, to: &match)
        }
    }

    private func field<Value>(_ index: Int, _ key: WritableKeyPath<TennisRecordedSet, Value>) -> Binding<Value> {
        Binding { sets[index][keyPath: key] } set: { value in
            sets[index][keyPath: key] = value
            TennisRecordedScore.apply(sets, to: &match)
        }
    }
}
