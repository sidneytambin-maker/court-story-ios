import SwiftUI

struct WatchRootView: View {
    @StateObject private var store = WatchTennisStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var quickTraining = false
    @State private var notificationRoute: TennisActivityRoute?
    var body: some View {
        NavigationStack {
            selectedPage.toolbar {
                ToolbarItem(placement: .topBarLeading) { WatchPageSelector() }
            }
        }
        .id(store.page)
        .environmentObject(store)
        .modifier(WatchTestDynamicType())
        .tint(store.snapshot.settings.theme == .tennis ? TennisSportStyle.ball : .cyan)
        .sheet(isPresented: $quickTraining) { NavigationStack { WatchTrainingEntryView() }.environmentObject(store) }
        .sheet(item: $notificationRoute) { route in WatchNotificationDestination(route: route).environmentObject(store) }
        .sheet(item: $store.pendingHealthStart) { _ in
            NavigationStack {
                List {
                    Text(store.workoutMessage).accessibilityIdentifier("healthStartFailure")
                    if store.isPreparingWorkout { ProgressView("Starting session") }
                    Button("Retry Health Start") { store.retryHealthStart() }
                        .disabled(store.isPreparingWorkout)
                    Button("Start Without Health") { store.startPendingTrainingWithoutHealth() }
                        .disabled(store.isPreparingWorkout)
                    Button("Cancel", role: .cancel) { store.cancelPendingTrainingStart() }
                        .disabled(store.isPreparingWorkout)
                }.navigationTitle("Session Not Started")
            }
            .interactiveDismissDisabled(store.isPreparingWorkout)
        }
        .safeAreaInset(edge: .bottom) {
            if store.isPreparingWorkout { ProgressView("Starting session").padding(8).background(.regularMaterial) }
        }
        .onAppear { store.activate(); openPendingNotification() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.restoreWorkoutIfNeeded(); openPendingNotification() }
            else { TennisSoundPlayer.shared.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tennisWorkoutRecovery)) { _ in store.restoreWorkoutIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .tennisTrackerOpenURL)) { _ in openPendingNotification() }
        .onOpenURL { url in
            if let route = TennisActivityRoute(url: url) { notificationRoute = route }
            else if let page = TennisWatchPage.destination(for: url) {
                store.page = page
                if url.lastPathComponent == "start-training" { quickTraining = true }
            }
        }
    }

    private func openPendingNotification() {
        if let url = TennisNotificationInbox.take() { notificationRoute = TennisActivityRoute(url: url) }
    }

    @ViewBuilder private var selectedPage: some View {
        switch store.page {
        case .today: WatchTodayView()
        case .track: WatchTrackView()
        case .live: WatchLiveView()
        case .recent: WatchRecentView()
        case .score: WatchScoreView()
        }
    }
}

private struct WatchTestDynamicType: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-watch"),
           ProcessInfo.processInfo.arguments.contains("-watch-large-text") {
            content.dynamicTypeSize(.accessibility3)
        } else { content }
        #else
        content
        #endif
    }
}


private struct WatchTrackView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { WatchTrainingEntryView() } label: { Label("Track Training Session", systemImage: "figure.tennis") }
                NavigationLink { WatchMatchSetupView() } label: { Label("Live Score a Match", systemImage: "tennisball.fill") }
                NavigationLink { WatchRecordedMatchView() } label: { Label("Record Match Result", systemImage: "square.and.pencil") }
                    .accessibilityHint("Enter players, a completed result, sets and conditions without live scoring.")
                NavigationLink { WatchTournamentManagementView() } label: { Label("Manage Tournaments", systemImage: "trophy.fill") }
                    .accessibilityHint("Add, review, edit or delete your tournaments.")
            }
        }
        .navigationTitle("Track")
    }
}

struct WatchTrainingSetupView: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    @State private var type: TrainingType = .singlesPractice
    @State private var focus = ""
    @State private var additionalFocus: [String] = []
    @State private var context = TennisActivityContext()
    @State private var venue = ""
    @State private var location = ""
    @State private var otherPlayers = false

    private var useHealth: Binding<Bool> {
        Binding(get: { store.defaultUseHealth }, set: {
            store.setDefaultUseHealth($0)
        })
    }

    var body: some View {
        Form {
            Picker("Training type", selection: $type) {
                ForEach(TrainingType.allCases) { Text($0.rawValue).tag($0) }
            }
            TennisTrainingFocusPicker(focus: $focus, additionalFocus: $additionalFocus)
            TennisCoachPicker(coaches: store.snapshot.setup.coaches, context: $context)
            WatchVenueFields(venueID: $context.venueID, venue: $venue, location: $location)
            NavigationLink("Players Present") {
                WatchPlayerChoices(players: store.snapshot.players.filter { $0.id != store.selectedPlayer?.id }, selectedIDs: $context.participantIDs, otherSelected: $otherPlayers)
            }
            .accessibilityValue(context.participantSummary(in: store.snapshot.players).fallback("None"))
            TennisTournamentPicker(tournaments: store.snapshot.tournaments, tournamentID: $context.tournamentID, customName: $context.customTournamentName)
            if store.healthClient.available {
                Section("Apple Health") {
                    Toggle("Track Training as Workout", isOn: useHealth)
                    WatchHealthAccessView(client: store.healthClient)
                    Text("Court Story can record workout duration, heart rate, active energy and available steps and distance in Apple Health. Tennis tracking still works if you decline.")
                }
            }
            Button("Start Session") {
                context.captureLegacyNames(coaches: store.snapshot.setup.coaches, players: store.snapshot.players)
                context.coachesNeedDetails = context.needsOtherCoachName
                context.participantsNeedDetails = otherPlayers
                store.trackTrainingSession(type: type, focus: focus, additionalFocus: additionalFocus, context: context, venue: venue, location: location)
                dismiss()
            }
            .disabled(store.selectedPlayer == nil || store.activeTraining != nil || store.isPreparingWorkout || store.isFinishingWorkout)
        }
        .pickerStyle(.navigationLink)
        .navigationTitle("Training")
    }
}

private struct WatchMatchSetupView: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    @State private var match = MatchRecord(playerID: UUID())
    @State private var configured = false

    var body: some View {
        Form {
            TennisMatchPeopleFields(players: store.snapshot.players, match: $match)
            OrderedChoicePicker(title: "Match format", selection: $match.matchFormat, values: MatchFormat.allCases) { $0.label }
            WatchVenueFields(venueID: $match.venueID, venue: $match.venue, location: $match.location)
            TennisTournamentPicker(tournaments: store.snapshot.tournaments, tournamentID: $match.tournamentID, customName: $match.customTournamentName)
            TennisTrainingSessionPicker(sessions: store.snapshot.trainingSessions.filter { $0.playerID == match.playerID }, coaches: store.snapshot.setup.coaches, selection: $match.trainingSessionID)
            Section("Conditions") { TennisMatchConditionsFields(match: $match) }
            Button("Begin Match Scoring") {
                match.needsDetails = match.opponentName.isBlank || (match.matchType == .doubles && (match.partnerName.isBlank || match.opponent2Name.isBlank)) || match.venue.isBlank
                store.beginMatch(match)
                if match.needsDetails { store.announce("Match ready. Details can be edited on Watch.") }
                dismiss()
            }
            .disabled(!configured || store.activeMatch != nil)
        }
        .pickerStyle(.navigationLink)
        .navigationTitle("Live Score a Match")
        .onAppear {
            guard !configured, let player = store.selectedPlayer else { return }
            match = TennisWatchActivityFactory.match(player: player, kind: .singles)
            match.opponentName = ""
            configured = true
        }
    }
}

struct WatchTournamentSetupView: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    @State private var templateID: UUID?
    @State private var customName = ""
    var body: some View {
        Form {
            Section("Existing tournament") {
                ForEach(store.snapshot.tournaments.filter { !$0.isCompleted }) { tournament in
                    Button(tournament.name) { store.beginTournament(tournament); dismiss() }
                }
            }
            Section("New occurrence") {
                Picker("Regular tournament", selection: $templateID) {
                    Text("Other").tag(Optional<UUID>.none)
                    ForEach(store.snapshot.setup.tournamentTemplates) { Text($0.name).tag(Optional($0.id)) }
                }
                if templateID == nil { TextField("Other tournament name", text: $customName) }
                Button("Begin Tournament") {
                    guard let player = store.selectedPlayer else { return }
                    var tournament = TennisWatchActivityFactory.tournament(playerID: player.id)
                    tournament.name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let template = store.snapshot.setup.tournamentTemplates.first(where: { $0.id == templateID }) {
                        tournament.templateID = template.id; tournament.name = template.name
                        tournament.format = template.format; tournament.venueID = template.venueID
                        if let venue = store.snapshot.setup.venues.first(where: { $0.id == template.venueID }) {
                            tournament.venue = venue.name; tournament.location = venue.town
                        }
                    }
                    store.beginTournament(tournament)
                    store.announce("Tournament started. Dates and details can be edited on Watch.")
                    dismiss()
                }
                .disabled(templateID == nil && customName.isBlank)
            }
        }
        .navigationTitle("Tournament")
    }
}

private struct WatchLiveView: View {
    @EnvironmentObject private var store: WatchTennisStore
    var body: some View {
        List {
            if let training = store.activeTraining {
                WatchTrainingRow(training: training)
            }
            if let tournament = store.snapshot.tournaments.first(where: { $0.id == store.activeTournamentID }) {
                WatchTournamentRow(tournament: tournament)
            }
            if store.activeTraining == nil, let training = store.completedTraining {
                WatchTrainingRow(training: training, identifier: "Completed training summary")
                if store.isFinishingWorkout { ProgressView("Saving workout") }
                else if !store.workoutMessage.isEmpty { Text(store.workoutMessage).font(.footnote) }
                if training.trainingType == .matchPlay {
                    NavigationLink("Record Practice Result") { WatchPracticeResultView() }
                }
            } else if store.activeTraining == nil && store.activeTournamentID == nil {
                Text("No tennis activity in progress.")
            }
        }
        .navigationTitle("Live")
    }
}

private struct WatchHealthAccessView: View {
    @ObservedObject var client: WatchHealthWorkout
    var body: some View { Text("Health access: \(client.accessDescription)") }
}

private struct WatchPracticeResultView: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    @State private var result = TennisPracticeResult()
    var body: some View {
        Form {
            Picker("Singles or doubles", selection: $result.kind) {
                ForEach(MatchKind.allCases) { Text($0.rawValue).tag($0) }
            }
            TennisPersonPicker(title: "Opponent", players: store.snapshot.players.filter { $0.id != store.selectedPlayer?.id && $0.id != result.partnerID && $0.id != result.opponent2ID }, selection: $result.opponentID, name: $result.opponentName)
            if result.kind == .doubles {
                TennisPersonPicker(title: "Partner", players: store.snapshot.players.filter { $0.id != store.selectedPlayer?.id && $0.id != result.opponentID && $0.id != result.opponent2ID }, selection: $result.partnerID, name: $result.partnerName, regularPartnersFirst: true)
                TennisPersonPicker(title: "Second opponent", players: store.snapshot.players.filter { $0.id != store.selectedPlayer?.id && $0.id != result.partnerID && $0.id != result.opponentID }, selection: $result.opponent2ID, name: $result.opponent2Name)
            }
            OrderedChoicePicker(title: "Your games", selection: $result.playerGames, values: Array(0...30)) { "\($0) games" }
            OrderedChoicePicker(title: "Opponent games", selection: $result.opponentGames, values: Array(0...30)) { "\($0) games" }
            Button("Save Practice Result") {
                result.result = result.playerGames == result.opponentGames ? .draw : result.playerGames > result.opponentGames ? .win : .loss
                store.savePracticeResult(result); dismiss()
            }
        }.navigationTitle("Practice Result")
    }
}

private struct WatchRecentView: View {
    @EnvironmentObject private var store: WatchTennisStore
    private var matches: [MatchRecord] { Array(store.snapshot.matches.filter { $0.status == .completed && !$0.needsDetails }.sorted { $0.date > $1.date }.prefix(5)) }
    private var training: [TrainingSession] { Array(store.snapshot.trainingSessions.filter { !$0.needsDetails && !$0.isActive && ($0.actualFinish != nil || $0.expectedEndDate < Date()) }.sorted { $0.date > $1.date }.prefix(5)) }
    private var tournaments: [TournamentRecord] { Array(store.snapshot.tournaments.filter { $0.isCompleted && !$0.needsDetails }.sorted { $0.date > $1.date }.prefix(3)) }
    var body: some View {
        List {
            if !matches.isEmpty {
                Section { ForEach(matches) { WatchMatchRow(match: $0) } }
                    header: { Text("Matches").accessibilityHidden(true) }
            }
            if !training.isEmpty {
                Section { ForEach(training) { WatchTrainingRow(training: $0) } }
                    header: { Text("Training").accessibilityHidden(matches.isEmpty) }
            }
            if !tournaments.isEmpty {
                Section { ForEach(tournaments) { WatchTournamentRow(tournament: $0) } }
                    header: { Text("Tournaments").accessibilityHidden(matches.isEmpty && training.isEmpty) }
            }
            if store.needsDetailsCount > 0 {
                Section {
                    ForEach(store.snapshot.trainingSessions.filter { $0.needsDetails && !$0.isActive }) { WatchTrainingRow(training: $0) }
                    ForEach(store.snapshot.matches.filter { $0.needsDetails && $0.status != .inProgress }) { WatchMatchRow(match: $0) }
                    ForEach(store.snapshot.tournaments.filter { $0.needsDetails && $0.id != store.activeTournamentID }) { WatchTournamentRow(tournament: $0) }
                } header: { Text("Needs Details").accessibilityHidden(matches.isEmpty && training.isEmpty && tournaments.isEmpty) }
            } else if matches.isEmpty && training.isEmpty && tournaments.isEmpty {
                Text("No recent activity")
            }
        }.navigationTitle("Recent")
    }
}

private struct WatchScoreView: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @AccessibilityFocusState private var pointFocus: PointWinner?
    @State private var confirmFinish = false
    @State private var editingMatch: MatchRecord?
    @State private var deletingMatch = false
    var body: some View {
        List {
            if let match = store.activeMatch {
                Text(scoreText)
                    .accessibilityLabel("Current match score")
                    .accessibilityValue(scoreText)
                    .accessibilityAction(named: "Undo Last Point") { store.undoLastPoint() }
                    .accessibilityAction(named: "Save Match Progress") { store.saveMatchProgress() }
                    .accessibilityAction(named: "Edit Match") { editingMatch = match }
                    .accessibilityAction(named: "Hear Full Score") { store.announce(scoreText) }
                    .accessibilityActions {
                        if !store.scoreState.isTiebreak && !store.scoreState.isMatchComplete {
                            Button("Start Tie-break") { store.startTieBreak() }
                        }
                    }
                    .accessibilityAction(named: "Finish Match") { confirmFinish = true }
                    .accessibilityAction(named: "Delete") { deletingMatch = true }
                    .accessibilityAction { store.announce(scoreText) }
                HStack(spacing: 8) {
                    pointButton(name: match.playerTeam, winner: .player)
                    pointButton(name: match.opponentSummary.fallback("Opponent"), winner: .opponent)
                }.accessibilityElement(children: .contain)
                if hideScoreActions {
                    scoreActions(for: match).accessibilityRepresentation { EmptyView() }
                } else {
                    scoreActions(for: match)
                }
            } else {
                Text("No match in progress.")
                ForEach(store.snapshot.matches.filter { $0.status == .scheduled || $0.status == .inProgress }) { match in
                    Button("Score \(match.playerTeam) against \(match.opponentSummary)") { store.beginMatch(match) }
                }
                NavigationLink("Live Score a Match") { WatchMatchSetupView() }
            }
        }
        .navigationTitle("Score")
        .sheet(item: $editingMatch) { match in NavigationStack { WatchMatchEditor(draft: match) } }
        .sheet(isPresented: $deletingMatch) {
            if let match = store.activeMatch {
                WatchDeleteSheet(isPresented: $deletingMatch, deletion: TennisRecordDeletion(id: match.id, kind: .match))
            }
        }
        .confirmationDialog("Finish match with the recorded score?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish Match") { store.finishMatch() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var hideScoreActions: Bool { voiceOver || WatchAccessibilityNavigation.testingEnabled }

    private func pointButton(name: String, winner: PointWinner) -> some View {
        Button {
            store.recordPoint(winner); pointFocus = winner
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                Text(name).font(.caption).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .foregroundStyle(store.snapshot.settings.theme == .tennis ? TennisSportStyle.ink : .white)
        .accessibilityLabel("Record Point for \(name)")
        .accessibilityFocused($pointFocus, equals: winner)
    }

    private func scoreActions(for match: MatchRecord) -> some View {
        VStack(spacing: 8) {
            Button("Undo Last Point") { store.undoLastPoint() }
            Button("Edit Match") { editingMatch = match }
            Button("Save Match Progress") { store.saveMatchProgress() }
            Button("Start Tie-break") { store.startTieBreak() }
                .disabled(store.scoreState.isTiebreak || store.scoreState.isMatchComplete)
            Button("Finish Match") { confirmFinish = true }
            Button("Delete", role: .destructive) { deletingMatch = true }
        }.buttonStyle(.bordered)
    }

    private var scoreText: String {
        guard let match = store.activeMatch else { return "No match in progress." }
        return store.scoreState.spokenScore(playerName: match.playerTeam, opponentName: match.opponentSummary.fallback("Opponent"), suddenDeathDeuce: match.suddenDeathDeuce)
    }
}
