import SwiftUI

struct WatchRecordedMatchView: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    @State private var match = MatchRecord(playerID: UUID())
    @State private var configured = false
    @State private var validationMessage = ""
    @State private var scoreError = ""

    var body: some View {
        Form {
            if !validationMessage.isBlank { Text(validationMessage).accessibilityIdentifier("recordMatchValidation") }
            CourtCaptureIdentity(athlete: store.selectedPlayer?.displayName ?? "Player", sport: match.court.sport, coached: match.court.enteredByCoachID != nil)
            if match.court.sport.sport != .custom { TennisMatchPeopleFields(players: store.snapshot.players, match: $match) }
            WatchMatchScheduleFields(match: $match)
            OrderedChoicePicker(title: "Match round", selection: $match.matchPosition, values: MatchPosition.allCases) { $0.label }
                .accessibilityIdentifier("matchRoundPicker")
            WatchVenueFields(venueID: $match.venueID, venue: $match.venue, location: $match.location)
            TennisTournamentPicker(tournaments: store.scopedSnapshot.tournaments, tournamentID: $match.tournamentID, customName: $match.customTournamentName)
            TennisTrainingSessionPicker(sessions: store.scopedSnapshot.trainingSessions, coaches: store.snapshot.setup.coaches, selection: $match.trainingSessionID)
            if configured {
                if match.court.sport.sport != .custom {
                    NavigationLink("Scoring rules") {
                        Form {
                            CourtRuleFields(sport: match.court.sport.sport,
                                rules: Binding(get: { match.court.rules ?? match.makeCourtScore().rules }, set: { match.court.rules = $0 }),
                                doubles: match.matchType == .doubles)
                        }.navigationTitle("Match rules")
                    }
                }
                CourtRecordedScoreFields(match: $match, validationMessage: $scoreError)
            }
            Section("Conditions") { TennisMatchConditionsFields(match: $match) }
            TextField("Next practice focus", text: $match.nextPracticeFocus)
                .accessibilityHint("Your latest completed match review appears in What to work on on the iPhone dashboard.")
            TextField("Notes", text: $match.notes)
            Button("Save Match Result") {
                if !scoreError.isEmpty { validationMessage = scoreError; store.announce(scoreError); return }
                if store.saveCourtMatch(match, showAsActive: false) { dismiss() }
            }.disabled(!configured).accessibilityIdentifier("saveRecordedMatch")
        }
        .pickerStyle(.navigationLink)
        .navigationTitle("Record Match Result")
        .onAppear {
            guard !configured, let draft = store.makeCourtMatch() else { return }
            match = draft
            match.status = .completed
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
                    tournament.court = CourtActivity(player: player, coachID: store.capturingCoachID)
                    tournament.category = player.bCategory
                    newTournament = tournament
                }
            }.disabled(store.selectedPlayer == nil)
            ForEach(store.scopedSnapshot.tournaments.sorted { $0.date > $1.date }) { WatchTournamentRow(tournament: $0) }
            NavigationLink("Start Tournament Timing") { WatchTournamentSetupView() }
        }
        .navigationTitle("Tournaments")
        .sheet(item: $newTournament) { draft in
            NavigationStack { WatchTournamentEditor(draft: draft, isNew: true) }
        }
    }
}
