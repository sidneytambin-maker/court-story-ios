import SwiftUI

struct TennisTrainingSessionPicker: View {
    let sessions: [TrainingSession]
    var coaches: [TennisCoach] = []
    @Binding var selection: UUID?

    private var sorted: [TrainingSession] { sessions.sorted { $0.date > $1.date } }
    private var value: String {
        guard let selection else { return "No training session" }
        return sessions.first { $0.id == selection }.map(label) ?? "Linked training session"
    }
    private func label(_ session: TrainingSession) -> String {
        var parts = [session.trainingType.rawValue, session.date.shortTennisDate]
        if session.hasStartTime { parts.append(session.date.formatted(date: .omitted, time: .shortened)) }
        if !session.venue.isBlank { parts.append(session.venue) }
        let names = session.context.coachSummary(in: coaches)
        if !names.isBlank { parts.append("Coaches: " + names) }
        return parts.joined(separator: ", ")
    }
    var body: some View {
        Picker("Training session", selection: $selection) {
            Text("No training session").tag(Optional<UUID>.none)
            ForEach(sorted) { Text(label($0)).tag(Optional($0.id)) }
            if let selection, !sessions.contains(where: { $0.id == selection }) {
                Text("Linked training session").tag(Optional(selection))
            }
        }
        #if os(watchOS)
        .pickerStyle(.navigationLink)
        #else
        .pickerStyle(.menu)
        #endif
        .accessibilityLabel("Training session")
        .accessibilityValue(value)
        .accessibilityIdentifier("matchTrainingPicker")
    }
}

struct TennisLinkedMatchesPicker: View {
    let matches: [MatchRecord]
    let sessionID: UUID
    @Binding var selected: [UUID]
    @State private var showingChoices = false

    private var value: String { selected.isEmpty ? "No matches" : "\(selected.count) linked \(selected.count == 1 ? "match" : "matches")" }
    var body: some View {
        #if os(watchOS)
        Button { showingChoices = true } label: {
            VStack(alignment: .leading) { Text("Linked matches"); Text(value).font(.callout) }
        }
        .accessibilityLabel("Linked matches").accessibilityValue(value)
        .accessibilityIdentifier("trainingMatchesPicker")
        .sheet(isPresented: $showingChoices) {
            NavigationStack {
                choices.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingChoices = false } } }
            }
        }
        #else
        NavigationLink("Linked matches") { choices }
            .accessibilityValue(value).accessibilityIdentifier("trainingMatchesPicker")
        #endif
    }

    private var choices: some View {
        TennisChoiceList {
            Button("No matches") { selected = [] }.accessibilityAddTraits(selected.isEmpty ? .isSelected : [])
            ForEach(matches.sorted { $0.date > $1.date }) { match in
                TennisSelectionRow(name: "\(match.matchType.rawValue), \(match.opponentSummary.fallback("Opponent not recorded")), \(match.date.shortTennisDate)", id: match.id, selectedIDs: $selected)
                    .accessibilityHint(match.trainingSessionID != nil && match.trainingSessionID != sessionID ? "Selecting moves this match from its other training session when saved." : "")
            }
            if matches.isEmpty { Text("No recorded or scheduled matches") }
        }.navigationTitle("Linked matches")
    }
}
