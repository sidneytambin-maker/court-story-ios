import SwiftUI

struct WatchRecordedMatchView: View {
    @EnvironmentObject private var store: WatchTennisStore
    var linkedTraining: TrainingSession?
    @State private var match = MatchRecord(playerID: UUID())
    @State private var configured = false
    @State private var validationMessage = ""
    @State private var scoreError = ""
    @State private var showingRules = false

    var body: some View {
        #if DEBUG && targetEnvironment(simulator)
        let _ = WatchNavigationDiagnostics.trace("recorded match") { Self._printChanges() }
        #endif
        Form {
            if !validationMessage.isBlank { Text(validationMessage).accessibilityIdentifier("recordMatchValidation") }
            CourtCaptureIdentity(athlete: store.snapshot.players.first { $0.id == match.playerID }?.displayName ?? "Player", sport: match.court.sport, coached: match.court.enteredByCoachID != nil)
            if match.court.sport.sport != .custom { TennisMatchPeopleFields(players: store.snapshot.players, match: $match) }
            WatchMatchScheduleFields(match: $match)
            OrderedChoicePicker(title: "Match round", selection: $match.matchPosition, values: MatchPosition.allCases) { $0.label }
                .accessibilityIdentifier("matchRoundPicker")
            WatchVenueFields(venueID: $match.venueID, venue: $match.venue, location: $match.location)
            TennisTournamentPicker(tournaments: store.snapshot.tournaments.filter { $0.playerID == match.playerID && $0.court.sport == match.court.sport }, tournamentID: $match.tournamentID, customName: $match.customTournamentName)
            TennisTrainingSessionPicker(sessions: store.snapshot.trainingSessions.filter { $0.playerID == match.playerID && $0.court.sport == match.court.sport }, coaches: store.snapshot.setup.coaches, selection: $match.trainingSessionID)
            if configured {
                if match.court.sport.sport != .custom {
                    Button("Scoring rules") { showingRules = true }
                }
                CourtRecordedScoreFields(match: $match, validationMessage: $scoreError)
            }
            Section("Conditions") { TennisMatchConditionsFields(match: $match) }
            if CourtFeature.observations.isAvailable(in: store.snapshot.settings.trackingMode) {
            TextField("Next practice focus", text: $match.nextPracticeFocus)
                .accessibilityHint("Your latest completed match review appears in What to work on on the iPhone dashboard.")
            }
            TextField("Notes", text: $match.notes)
            WatchSaveAndDismissButton(title: "Save Match Result") {
                if !scoreError.isEmpty { validationMessage = scoreError; store.announce(scoreError); return false }
                return store.saveCourtMatch(match, showAsActive: false)
            }.disabled(!configured).accessibilityIdentifier("saveRecordedMatch")
        }
        .pickerStyle(.navigationLink)
        .navigationTitle("Record Match Result")
        .sheet(isPresented: $showingRules) {
            NavigationStack {
                WatchRecordedMatchRulesView(match: $match)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Back", systemImage: "chevron.backward") { showingRules = false }
                                .labelStyle(.iconOnly).accessibilityLabel("Back to match result")
                        }
                    }
            }
        }
        .onChange(of: match.matchType) { _, _ in if configured { match.configureNewCourtMatch() } }
        .onAppear {
            guard !configured, let draft = store.makeCourtMatch() else { return }
            match = draft
            if let linkedTraining {
                match.playerID = linkedTraining.playerID
                match.playerName = store.snapshot.players.first { $0.id == linkedTraining.playerID }?.displayName ?? "Player"
                match.court = linkedTraining.court
                match.court.score = nil
                match.trainingSessionID = linkedTraining.id
                match.tournamentID = linkedTraining.context.tournamentID
                match.venueID = linkedTraining.context.venueID; match.venue = linkedTraining.venue; match.location = linkedTraining.location
                match.configureNewCourtMatch()
            }
            match.status = .completed
            match.date = linkedTraining?.date ?? Calendar.current.startOfDay(for: Date())
            configured = true
        }
    }
}

private struct WatchRecordedMatchRulesView: View {
    @Binding var match: MatchRecord
    var body: some View {
        #if DEBUG && targetEnvironment(simulator)
        let _ = WatchNavigationDiagnostics.trace("recorded rules") { Self._printChanges() }
        #endif
        Form {
            CourtRuleFields(sport: match.court.sport.sport,
                rules: Binding(get: { match.court.rules ?? match.makeCourtScore().rules }, set: { match.court.rules = $0 }),
                doubles: match.matchType == .doubles)
        }.navigationTitle("Match rules").pickerStyle(.navigationLink)
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
