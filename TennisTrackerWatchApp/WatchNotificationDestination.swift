import SwiftUI

struct WatchNotificationDestination: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    let route: TennisActivityRoute
    var body: some View {
        NavigationStack {
            destination.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .onAppear { if let id = route.recordID { store.openNotificationRecordIDs.insert(id) } }
        .onDisappear { if let id = route.recordID { store.openNotificationRecordIDs.remove(id) } }
    }
    @ViewBuilder private var destination: some View {
        switch route.kind {
        case .training:
            if let session = store.snapshot.trainingSessions.first(where: { $0.id == route.recordID }) {
                if route.action == .reflection && !session.isActive && CourtFeature.observations.isAvailable(in: store.snapshot.settings.trackingMode) { WatchTrainingReflectionEditor(session: session) }
                else {
                    List {
                        WatchTrainingRow(training: session)
                        if session.actualStart == nil && session.actualFinish == nil {
                            Button("Start Workout") { if store.beginTraining(session) { dismiss() } }
                                .accessibilityIdentifier("startWatchWorkout")
                                .accessibilityHint(store.workoutStartHint)
                                .disabled(store.activeTraining != nil || store.isPreparingWorkout || store.isFinishingWorkout)
                        }
                    }.navigationTitle("Training")
                }
            } else { unavailable }
        case .match:
            if let match = store.snapshot.matches.first(where: { $0.id == route.recordID }) {
                if match.status == .inProgress {
                    List {
                        Text(TennisSummaryFormatter.match(match, style: .short))
                        Button("Resume Live Match") { store.resume(match); dismiss() }
                    }.navigationTitle("Live Match")
                } else if route.action == .result { WatchNotificationResultEditor(match: match) }
                else {
                    List {
                        WatchMatchRow(match: match)
                        if match.status == .scheduled {
                            Button("Start Live Scoring") { store.beginMatch(match); dismiss() }.disabled(store.activeMatch != nil)
                        }
                    }.navigationTitle("Match")
                }
            } else { unavailable }
        case .tournament:
            if let tournament = store.snapshot.tournaments.first(where: { $0.id == route.recordID }) {
                List { WatchTournamentRow(tournament: tournament) }.navigationTitle("Tournament")
            } else { unavailable }
        case .weekly:
            TennisWeeklyReview(records: store.scopedSnapshot.achievementRecords, playerID: store.snapshot.selectedPlayerID,
                weekStart: route.weekStart ?? TennisReportingWeek.interval(containing: Date()).start)
        case .achievements:
            TennisAchievementsView(achievements: store.scopedSnapshot.achievements)
        }
    }
    private var unavailable: some View {
        List {
            if let id = route.recordID, store.snapshot.deletedRecordIDs.contains(id) ||
                (store.snapshot.requestedActivityID == id && store.snapshot.requestedActivityFound == false) {
                Text("This activity is no longer available. It may have been deleted.").accessibilityIdentifier("notificationActivityUnavailable")
            } else {
                Text("This activity is not stored on this Watch yet. Its details have been requested from your iPhone.")
                    .accessibilityIdentifier("notificationActivityUnavailable")
                Button("Request Activity Again") { requestActivity() }
                    .accessibilityHint("The exact activity will open here when it arrives. Both devices need a connection to sync.")
            }
        }.navigationTitle("Activity Details").onAppear { requestActivity() }
    }
    private func requestActivity() {
        if let id = route.recordID, !store.snapshot.deletedRecordIDs.contains(id) { store.send(.requestActivity(id)) }
    }
}

struct WatchTrainingReflectionEditor: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TennisReflectionDraft
    @State private var message = ""
    init(session: TrainingSession) { _draft = State(initialValue: TennisReflectionDraft(session: session)) }
    private var current: TrainingSession? { store.snapshot.trainingSessions.first { $0.id == draft.sessionID } }
    var body: some View {
        Form {
            if let current, CourtFeature.observations.isAvailable(in: store.snapshot.settings.trackingMode) { TennisReflectionFields(draft: $draft, summary: store.trainingSummary(current, style: .short)) }
            else if current != nil { Text("Reflections are available in Standard and Power. Saved reflections are retained.") }
            else { Text("This session is no longer available.") }
            if !message.isEmpty { Text(message) }
            Button("Save Reflection") {
                guard CourtFeature.observations.isAvailable(in: store.snapshot.settings.trackingMode), let current, !current.isActive, let updated = draft.applying(to: current) else {
                    message = "This session is unavailable or still active. Finish tracking before saving a reflection."
                    store.announce(message); return
                }
                store.updateTrainingDetails(updated); dismiss()
            }.disabled(current == nil || !CourtFeature.observations.isAvailable(in: store.snapshot.settings.trackingMode)).accessibilityIdentifier("saveTrainingReflection")
        }.navigationTitle("Training Reflection")
    }
}

struct WatchNotificationResultEditor: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MatchRecord
    @State private var message = ""
    @State private var courtScoreError = ""
    init(match: MatchRecord) { _draft = State(initialValue: TennisNotificationResult.draft(match)) }
    var body: some View {
        Form {
            Text(TennisSummaryFormatter.match(draft, style: .short)).accessibilityIdentifier("notificationMatchSummary")
            if !message.isEmpty { Text(message) }
            if draft.usesCourtScoring { CourtRecordedScoreFields(match: $draft, validationMessage: $courtScoreError, showsRules: true) }
            else {
                OrderedChoicePicker(title: "Match format", selection: $draft.matchFormat, values: MatchFormat.allCases) { $0.label }
                TennisRecordedScoreFields(match: $draft)
            }
            if let current = store.snapshot.matches.first(where: { $0.id == draft.id }),
               current.opponentName.isBlank || (current.matchType == .doubles && (current.partnerName.isBlank || current.opponent2Name.isBlank)) {
                NavigationLink("Add Missing Players") { WatchMatchEditor(draft: current) }
                    .accessibilityHint("Choose the missing players, save those details, then finish recording this result.")
            }
            if CourtFeature.observations.isAvailable(in: store.snapshot.settings.trackingMode) { TextField("Next practice focus", text: $draft.nextPracticeFocus) }
            Button("Save Result") {
                if draft.usesCourtScoring && !courtScoreError.isEmpty { message = courtScoreError; store.announce(message); return }
                if !draft.usesCourtScoring, let error = TennisRecordedScore.validationMessage(for: draft) { message = error; store.announce(error); return }
                guard let current = store.snapshot.matches.first(where: { $0.id == draft.id }),
                      let updated = TennisNotificationResult.applying(draft, to: current) else {
                    message = "This match is unavailable or live scoring has started. Close this reminder and resume the live match."
                    store.announce(message); return
                }
                if updated.usesCourtScoring {
                    if store.saveCourtMatch(updated, showAsActive: false) { dismiss() }
                } else {
                    if let error = TennisManualMatchEntry.validationMessage(for: updated) { message = error; store.announce(error); return }
                    store.saveRecordedMatch(updated); dismiss()
                }
            }.accessibilityIdentifier("saveNotificationMatchResult")
        }.navigationTitle("Match Result")
    }
}
