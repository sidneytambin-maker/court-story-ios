import SwiftUI

struct WatchTodayView: View {
    @EnvironmentObject private var store: WatchTennisStore
    @State private var showingSyncStatus = false

    private var nextTraining: TrainingSession? {
        store.scopedSnapshot.trainingSessions
            .filter { !$0.isActive && $0.actualFinish == nil && $0.expectedEndDate >= Date() }
            .min { $0.date < $1.date }
    }

    var body: some View {
        List {
            if let player = store.selectedPlayer {
                NavigationLink { WatchCourtWorkspaceView() } label: {
                    CourtCaptureIdentity(athlete: player.displayName, sport: store.courtSport, coached: store.capturingCoachID != nil)
                }.accessibilityHint("Change sport, role or the player you are recording for.")
            }
            if store.courtRole == .coach {
                NavigationLink("Your Players") { WatchCourtRosterView().equatable() }
                if let athlete = store.snapshot.court.activeAthleteID,
                   CourtFeature.observations.isAvailable(in: store.snapshot.settings.trackingMode) {
                    NavigationLink("Player Journal") { WatchCourtJournalView(athleteID: athlete) }
                }
            }
            if let training = store.activeTraining {
                WatchTrainingRow(training: training)
            }
            if store.activeMatch != nil {
                Button("Resume Match Scoring") { store.page = .score }
                    .accessibilityIdentifier("overviewResumeMatch")
            }
            if let training = nextTraining {
                Section("Next training") {
                    WatchTrainingRow(training: training)
                    Button("Start Workout") { store.beginTraining(training) }
                        .accessibilityIdentifier("overviewStartSession")
                        .disabled(store.activeTraining != nil || store.isPreparingWorkout || store.isFinishingWorkout)
                }
            }
            if store.activeTraining == nil && store.activeMatch == nil && nextTraining == nil {
                Button { store.page = .track } label: {
                    Label("Track \(store.courtSport.name) Activity", systemImage: "plus")
                }
                .accessibilityIdentifier("overviewTrackActivity")
            }
            if let match = TennisMatchListGroups(matches: store.scopedSnapshot.matches).nextUpcomingMatch() {
                Section("Next match") { WatchMatchRow(match: match) }
            }
            if store.snapshot.settings.showUpcomingTournaments, let tournament = store.upcomingTournament {
                Section("Next tournament") { WatchTournamentRow(tournament: tournament) }
            }
            if store.snapshot.settings.showNeedsAttention && store.needsDetailsCount > 0 {
                Button("Review \(store.needsDetailsCount) activities needing details") { store.page = .recent }
                    .accessibilityIdentifier("overviewNeedsDetails")
            }
            if let player = store.selectedPlayer {
                WatchDashboardProgress(player: player)
                NavigationLink { TennisAchievementsView(achievements: store.scopedSnapshot.achievements) } label: {
                    TennisAchievementsSummary(achievements: store.scopedSnapshot.achievements)
                }
            }
            Section {
                Button { showingSyncStatus.toggle() } label: {
                    Label("Sync status", systemImage: showingSyncStatus ? "chevron.down" : "chevron.right")
                }
                .accessibilityValue(showingSyncStatus ? "Expanded" : "Collapsed")
                .accessibilityHint("Shows or hides the latest sync status.")
                .accessibilityIdentifier("overviewSyncStatus")
                if showingSyncStatus {
                    Text(store.lastSyncStatus).font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("Overview")
    }
}

private struct WatchDashboardProgress: View {
    @EnvironmentObject private var store: WatchTennisStore
    let player: PlayerProfile
    @State private var expanded = false
    @State private var configured = false

    private var progress: TennisPlayerProgress {
        TennisPlayerProgress.build(player: player, matches: store.scopedSnapshot.matches,
            training: store.scopedSnapshot.trainingSessions, coaches: store.snapshot.setup.coaches)
    }

    var body: some View {
        let progress = self.progress
        let totals = TennisMatchResultTotals.build(records: store.scopedSnapshot.achievementRecords, playerID: player.id)
        Section {
            Button { expanded.toggle() } label: {
                Label("Results & focus", systemImage: expanded ? "chevron.down" : "chevron.right")
            }
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows or hides match results and recent training focus.")
            .accessibilityIdentifier("overviewProgress")
            if expanded {
                result("Singles", totals: totals.singles)
                result("Doubles", totals: totals.doubles)
                ForEach(progress.focus.prefix(3)) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.focus).font(.headline)
                        Text("\(item.sessions) \(item.sessions == 1 ? "session" : "sessions")").font(.body)
                        ProgressView(value: Double(item.sessions), total: Double(max(1, progress.focus.map(\.sessions).max() ?? 1)))
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.focus)
                    .accessibilityValue("\(item.sessions) \(item.sessions == 1 ? "session" : "sessions"), last 30 days")
                }
            }
        }
        .onAppear {
            guard !configured else { return }
            expanded = store.snapshot.settings.trackingMode != .basic
            configured = true
        }
        .onChange(of: store.snapshot.settings.trackingMode) { _, mode in expanded = mode != .basic }
    }

    private func result(_ title: String, totals: TennisResultTotals) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            Text("\(totals.wins) W  \(totals.losses) L  \(totals.draws) D").font(.body).monospacedDigit()
            if totals.retired > 0 { Text("\(totals.retired) retired").font(.footnote) }
            if totals.stopped > 0 { Text("\(totals.stopped) stopped without a winner").font(.footnote) }
            if store.snapshot.settings.trackingMode == .power && totals.count > 0 {
                Text("Win rate: " + winRate(totals)).font(.footnote)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) matches, all time")
        .accessibilityValue(totals.summary + (store.snapshot.settings.trackingMode == .power && totals.count > 0 ? " Win rate: " + winRate(totals) + ", of all recorded results." : ""))
        .accessibilityIdentifier("overviewResults." + title)
    }

    private func winRate(_ totals: TennisResultTotals) -> String {
        (Double(totals.wins) / Double(max(1, totals.count))).formatted(.percent.precision(.fractionLength(0)))
    }
}
