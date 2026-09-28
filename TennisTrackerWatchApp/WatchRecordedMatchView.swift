import SwiftUI

struct WatchRecordedMatchView: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    @State private var match = MatchRecord(playerID: UUID())
    @State private var configured = false
    @State private var validationMessage = ""

    var body: some View {
        Form {
            if !validationMessage.isBlank { Text(validationMessage).accessibilityIdentifier("recordMatchValidation") }
            TennisMatchPeopleFields(players: store.snapshot.players, match: $match)
            WatchDateField(title: "Match date", date: $match.date)
            WatchVenueFields(venueID: $match.venueID, venue: $match.venue, location: $match.location)
            TennisTournamentPicker(tournaments: store.snapshot.tournaments, tournamentID: $match.tournamentID, customName: $match.customTournamentName)
            TennisTrainingSessionPicker(sessions: store.snapshot.trainingSessions.filter { $0.playerID == match.playerID }, coaches: store.snapshot.setup.coaches, selection: $match.trainingSessionID)
            OrderedChoicePicker(title: "Match format", selection: $match.matchFormat, values: MatchFormat.allCases) { $0.label }
                .accessibilityIdentifier("matchFormatPicker")
            TennisRecordedScoreFields(match: $match)
            Section("Conditions") { TennisMatchConditionsFields(match: $match) }
            TextField("Next practice focus", text: $match.nextPracticeFocus)
                .accessibilityHint("Your latest completed match review appears in What to work on on the iPhone dashboard.")
            TextField("Notes", text: $match.notes)
            Button("Save Match Result") {
                if let error = TennisManualMatchEntry.validationMessage(for: match) {
                    validationMessage = error
                    store.announce(error)
                } else {
                    store.saveRecordedMatch(match)
                    dismiss()
                }
            }.disabled(!configured).accessibilityIdentifier("saveRecordedMatch")
        }
        .pickerStyle(.navigationLink)
        .navigationTitle("Record Match Result")
        .onAppear {
            guard !configured, let player = store.selectedPlayer else { return }
            match.playerID = player.id
            match.playerName = player.displayName
            match.matchFormat = player.defaultMatchFormat
            match.sightLevel = player.sightLevel
            match.allowedBounces = player.bounceAllowance ?? player.sightLevel.allowedBounces
            match.suddenDeathDeuce = player.playerMode == .blindTennis
            match.date = Calendar.current.startOfDay(for: Date())
            configured = true
        }
    }
}

struct WatchTournamentManagementView: View {
    @EnvironmentObject private var store: WatchTennisStore
    @State private var newTournament: TournamentRecord?

    var body: some View {
        List {
            Button("Add Tournament") {
                if let player = store.selectedPlayer {
                    var tournament = TournamentRecord(playerID: player.id)
                    tournament.category = player.bCategory
                    newTournament = tournament
                }
            }.disabled(store.selectedPlayer == nil)
            ForEach(store.snapshot.tournaments.sorted { $0.date > $1.date }) { WatchTournamentRow(tournament: $0) }
            NavigationLink("Start Tournament Timing") { WatchTournamentSetupView() }
        }
        .navigationTitle("Tournaments")
        .sheet(item: $newTournament) { draft in
            NavigationStack { WatchTournamentEditor(draft: draft, isNew: true) }
        }
    }
}
