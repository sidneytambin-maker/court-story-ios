import SwiftUI

struct TrainingEntryDetails: View {
    @EnvironmentObject private var store: TennisStore
    @Binding var session: TrainingSession
    @Binding var newPlayers: [PlayerProfile]
    @Binding var linkedMatchIDs: [UUID]

    var body: some View {
        TennisOptionalSection("Session details", mode: store.data.settings.trackingMode, identifier: "trainingEntryDetails") {
            Toggle("Start time specified", isOn: $session.hasStartTime)
            if session.hasStartTime { FiveMinuteTimePicker(title: "Start time", date: $session.date) }
            StoredVenuePicker(id: $session.context.venueID, venue: $session.venue, location: $session.location, training: true)
            TennisCoachPicker(coaches: store.data.setup.coaches, context: $session.context)
            NavigationLink("Players Present") {
                TrainingParticipantPicker(session: $session, newPlayers: $newPlayers)
            }
            .accessibilityValue(session.context.participantSummary(in: store.data.players + newPlayers).fallback("None"))
            TennisTournamentPicker(tournaments: store.selectedTournaments, tournamentID: $session.context.tournamentID, customName: $session.context.customTournamentName)
            TennisLinkedMatchesPicker(matches: store.selectedMatches, sessionID: session.id, selected: $linkedMatchIDs)
            Picker("Surface", selection: $session.surface) {
                ForEach(CourtSurface.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("trainingSurfacePicker")
            TextField("Notes", text: $session.notes, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityIdentifier("trainingNotesField")
        }
    }
}

private struct TrainingParticipantPicker: View {
    @EnvironmentObject private var store: TennisStore
    @Binding var session: TrainingSession
    @Binding var newPlayers: [PlayerProfile]
    @State private var participantName = ""
    @FocusState private var nameFocused: Bool
    private var players: [PlayerProfile] { store.data.players + newPlayers }

    var body: some View {
        TennisList {
            ForEach(players.filter { $0.id != session.playerID }) { player in
                TennisSelectionRow(name: player.displayName, id: player.id, selectedIDs: $session.context.participantIDs)
            }
            TextField("Other player name", text: $participantName).focused($nameFocused)
            Button("Add Player") {
                let name = participantName.trimmingCharacters(in: .whitespacesAndNewlines)
                var player = players.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame } ?? PlayerProfile()
                player.name = name
                player.sightLevel = .notKnown
                player.bCategory = "Not known"
                if !players.contains(where: { $0.id == player.id }) { newPlayers.append(player) }
                if player.id != session.playerID && !session.context.participantIDs.contains(player.id) {
                    session.context.participantIDs.append(player.id)
                }
                participantName = ""
                nameFocused = false
            }
            .disabled(participantName.isBlank)
            Toggle("All participants recorded", isOn: Binding(
                get: { session.context.participantsNeedDetails != true },
                set: { session.context.participantsNeedDetails = !$0 }
            ))
        }
        .navigationTitle("Players Present")
    }
}

struct TrainingRatingsFields: View {
    @Binding var session: TrainingSession

    var body: some View {
        Toggle("Include body ratings", isOn: $session.hasSessionDetails)
            .accessibilityIdentifier("trainingIncludeRatings")
        if session.hasSessionDetails {
            OrderedChoicePicker(title: "Effort", selection: $session.effortLevel, values: RatingLevel.allCases) { $0.rawValue }
            OrderedChoicePicker(title: "Confidence", selection: $session.confidenceLevel, values: RatingLevel.allCases) { $0.rawValue }
            OrderedChoicePicker(title: "Energy", selection: $session.energyLevel, values: RatingLevel.allCases) { $0.rawValue }
            OrderedChoicePicker(title: "Pain", selection: $session.painLevel, values: PainLevel.allCases) { $0.rawValue }
            TextField("Outcome", text: $session.sessionOutcome, axis: .vertical)
        }
    }
}
