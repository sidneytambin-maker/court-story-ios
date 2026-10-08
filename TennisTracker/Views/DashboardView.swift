import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: TennisStore
    @State private var matchToEdit: MatchRecord?
    @State private var matchToDelete: MatchRecord?
    @State private var resumeMatch: MatchRecord?
    @State private var showingLiveScorer = false
    @State private var tournamentToEdit: TournamentRecord?
    @State private var matchTournament: TournamentRecord?
    @State private var trainingToEdit: TrainingSession?
    @State private var showingNewTraining = false
    @State private var confirmDeleteMatch = false
    @State private var focusToEdit: TrainingSession?
    @State private var showingGoals = false
    @State private var showingMatchReviews = false
    @State private var showingCoachSummary = false

    private var stats: TennisStatistics {
        TennisStatistics.build(matches: store.selectedMatches, training: store.selectedTraining, tournaments: store.selectedTournaments)
    }

    private var progress: TennisPlayerProgress {
        TennisPlayerProgress.build(player: store.selectedPlayer, matches: store.selectedMatches, training: store.selectedTraining, coaches: store.data.setup.coaches)
    }

    private var nextTournament: TournamentRecord? {
        store.selectedTournaments
            .filter { !$0.isCompleted }
            .sorted { $0.date < $1.date }
            .first
    }

    var body: some View {
        let progress = self.progress
        let stats = self.stats
        NavigationStack {
            TennisList {
                Section {
                    CourtWorkspaceSwitcher()
                    if store.data.settings.theme == .tennis {
                        TennisDashboardHeader(name: store.selectedPlayer?.displayName ?? "Player")
                    } else {
                        Text("Welcome, \(store.selectedPlayer?.displayName ?? "player")").font(.headline)
                    }
                }

                if store.selectedMatches.isEmpty && store.selectedTraining.isEmpty && store.selectedTournaments.isEmpty {
                    Section {
                        Button("Record Match", systemImage: "tennisball") { matchToEdit = store.makeDefaultMatch() }
                            .accessibilityIdentifier("dashboardFirstMatch")
                        Button("Track Training Session", systemImage: "figure.tennis") { showingNewTraining = true }
                            .accessibilityIdentifier("dashboardFirstTraining")
                        Button("Add Tournament", systemImage: "trophy") { tournamentToEdit = store.makeDefaultTournament() }
                            .accessibilityIdentifier("dashboardFirstTournament")
                    }
                }

                if store.selectedTraining.contains(where: \.isActive) || store.selectedMatches.contains(where: { $0.status == .inProgress }) {
                    TennisSection("Current activity") {
                        if let training = store.selectedTraining.first(where: \.isActive) {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                NavigationLink(store.trainingSummary(training, now: context.date)) {
                                    TrainingDetailView(session: training)
                                }
                            }
                        }
                        if let match = store.selectedMatches.first(where: { $0.status == .inProgress }) {
                            Button(TennisSummaryFormatter.match(match)) {
                                resumeMatch = match
                                showingLiveScorer = true
                            }
                            .accessibilityHint("Resumes match scoring.")
                        }
                    }
                }

                if nextTraining != nil || nextMatch != nil || (store.data.settings.showUpcomingTournaments && nextTournament != nil) {
                    TennisSection("Up next") {
                        if let training = nextTraining {
                            NavigationLink(store.trainingSummary(training)) { TrainingDetailView(session: training) }
                        }
                        if let match = nextMatch {
                            NavigationLink(TennisSummaryFormatter.match(match, tournaments: store.selectedTournaments)) { MatchDetailView(match: match) }
                        }
                        if store.data.settings.showUpcomingTournaments, let tournament = nextTournament {
                            NavigationLink(TennisSummaryFormatter.tournament(tournament, matches: store.selectedMatches)) {
                                TournamentDetailView(tournament: tournament)
                            }
                            .accessibilityAction(named: "Edit tournament") { tournamentToEdit = tournament }
                            .accessibilityAction(named: tournament.completionActionTitle) {
                                store.toggleTournamentCompletion(tournament.id)
                            }
                            .accessibilityAction(named: "Add Match to Tournament") { matchTournament = tournament }
                            .accessibilityAction(named: "Add tournament to Calendar") { addTournamentToCalendar(tournament) }
                        }
                    }
                }

                TennisSection("Match results, all time") {
                    TennisResultDashboardRow(title: "Singles matches", totals: progress.singles, symbol: "person.fill",
                        trainingMatchCount: progress.singlesPractice.count, compact: store.data.settings.trackingMode != .power)
                    TennisResultDashboardRow(title: "Doubles matches", totals: progress.doubles, symbol: "person.2.fill",
                        trainingMatchCount: progress.doublesPractice.count, compact: store.data.settings.trackingMode != .power)
                }

                Section {
                    SummaryRow(title: "Training, last 30 days", value: stats.trainingCountLast30Days == 0 ? "No training recorded." : "\(stats.trainingCountLast30Days) \(stats.trainingCountLast30Days == 1 ? "session" : "sessions"), \(TennisDurationFormatter.text(seconds: stats.trainingSecondsLast30Days)).")
                        .accessibilityIdentifier("dashboardTrainingSummary")
                        .accessibilityAction(named: "Track Training Session") { showingNewTraining = true }
                }

                if store.data.settings.showNeedsAttention && !stats.needsAttention.isEmpty {
                    TennisSection("Needs attention") {
                        Text(stats.needsAttention.joined(separator: " "))
                        if let training = store.selectedTraining.first(where: \.needsDetails) {
                            Button("Complete Training Details") {
                                var draft = training
                                draft.markDetailsComplete()
                                trainingToEdit = draft
                            }
                        }
                        if let match = store.selectedMatches.first(where: \.needsDetails) {
                            Button("Complete Match Details") { matchToEdit = match }
                            Button("Mark Match Complete") { store.completeMatchDetails(match.id) }
                        }
                    }
                }

                DashboardInsightsSection(progress: progress, mode: store.data.settings.trackingMode,
                    chooseFocus: {
                        if let id = progress.trainingNeedingFocus.first {
                            focusToEdit = store.selectedTraining.first { $0.id == id }
                        }
                    }, editGoals: { showingGoals = true }, reviewMatch: { showingMatchReviews = true },
                    planTraining: { showingNewTraining = true })

                if store.data.settings.trackingMode == .power {
                    Section {
                        Button("Preview Coach Summary", systemImage: "square.and.arrow.up") { showingCoachSummary = true }
                            .accessibilityIdentifier("dashboardCoachPreview")
                    }
                }

                if store.data.settings.showRecentActivity && store.selectedMatches.contains(where: { $0.status == .completed }) {
                    TennisSection("Recent matches") {
                        ForEach(store.selectedMatches.filter { $0.status == .completed }.suffix(3)) { match in
                            NavigationLink(TennisSummaryFormatter.match(match, tournaments: store.selectedTournaments, style: .short)) {
                                MatchDetailView(match: match)
                            }
                            .accessibilityLabel(TennisSummaryFormatter.match(match, tournaments: store.selectedTournaments, style: .long))
                            .accessibilityAction(named: "Edit match") { matchToEdit = match }
                            .accessibilityAction(named: "Add Match to Calendar") { addMatchToCalendar(match) }
                            .accessibilityAction(named: "Delete match") {
                                matchToDelete = match
                                confirmDeleteMatch = true
                            }
                        }
                    }
                }

                Section {
                    NavigationLink { TennisAchievementsView(achievements: store.data.achievements).tennisThemedList() } label: {
                        TennisAchievementsSummary(achievements: store.data.achievements)
                    }
                }
            }
            .tennisThemedList()
            .navigationTitle("Dashboard")
            .toolbar {
                Menu {
                    Button("Record Match", systemImage: "tennisball") { matchToEdit = store.makeDefaultMatch() }
                    Button("Track Training Session", systemImage: "figure.tennis") { showingNewTraining = true }
                    Button("Add Tournament", systemImage: "trophy") { tournamentToEdit = store.makeDefaultTournament() }
                } label: {
                    Label("Track Tennis Activity", systemImage: "plus")
                }
                .accessibilityIdentifier("dashboardAddActivity")
            }
            .sheet(isPresented: $showingCoachSummary) {
                CoachSummaryView(progress: progress, stats: stats)
            }
            .sheet(item: $matchToEdit) { match in
                MatchEditorView(match: match)
            }
            .sheet(isPresented: $showingLiveScorer) {
                LiveMatchView(existingMatch: resumeMatch)
                    .onDisappear { resumeMatch = nil }
            }
            .sheet(item: $tournamentToEdit) { tournament in
                TournamentEditorView(tournament: tournament)
            }
            .sheet(item: $matchTournament) { tournament in
                if let match = store.makeDefaultMatch(tournamentID: tournament.id) {
                    MatchEditorView(match: match)
                }
            }
            .sheet(isPresented: $showingNewTraining) {
                if let session = store.makeDefaultTraining() {
                    TrainingEditorView(session: session)
                }
            }
            .sheet(item: $focusToEdit) { TrainingFocusEditor(session: $0) }
            .sheet(isPresented: $showingGoals) {
                if let player = store.selectedPlayer { PlayerGoalsEditor(player: player) }
            }
            .sheet(isPresented: $showingMatchReviews) {
                NavigationStack {
                    TennisList {
                        ForEach(store.selectedMatches.filter { $0.status == .completed }) { match in
                            NavigationLink(TennisSummaryFormatter.match(match, style: .short)) { MatchReviewEditor(match: match) }
                        }
                        if !store.selectedMatches.contains(where: { $0.status == .completed }) {
                            Text("No completed matches to review.")
                        }
                    }
                    .navigationTitle("Review a Match")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingMatchReviews = false } } }
                }
            }
            .sheet(item: $trainingToEdit) { session in
                TrainingEditorView(session: session)
            }
            .confirmationDialog("Delete this match?", isPresented: $confirmDeleteMatch, titleVisibility: .visible) {
                Button("Delete Match", role: .destructive) {
                    if let matchToDelete {
                        store.deleteMatch(matchToDelete)
                    }
                    matchToDelete = nil
                }
                Button("Cancel", role: .cancel) { matchToDelete = nil }
            }
        }
    }

    private var nextTraining: TrainingSession? {
        store.selectedTraining.filter { $0.actualStart == nil && $0.date >= Date() }.min { $0.date < $1.date }
    }

    private var nextMatch: MatchRecord? {
        TennisMatchListGroups(matches: store.selectedMatches).nextUpcomingMatch()
    }

    private func addMatchToCalendar(_ match: MatchRecord) {
        Task {
            await store.addToCalendar(TennisCalendarMapper.event(for: match))
        }
    }

    private func addTournamentToCalendar(_ tournament: TournamentRecord) {
        Task {
            await store.addToCalendar(TennisCalendarMapper.event(for: tournament))
        }
    }
}
