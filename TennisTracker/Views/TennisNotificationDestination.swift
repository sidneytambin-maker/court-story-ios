import SwiftUI

struct TennisNotificationDestination: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    let route: TennisActivityRoute
    var body: some View {
        Group {
            switch route.kind {
            case .training:
                if let session = store.data.trainingSessions.first(where: { $0.id == route.recordID }) {
                    if route.action == .reflection && !session.isActive { TrainingReflectionEditor(session: session) }
                    else { NavigationStack { TrainingDetailView(session: session).toolbar { closeButton } } }
                } else { unavailable }
            case .match:
                if let match = store.data.matches.first(where: { $0.id == route.recordID }) {
                    if match.status == .inProgress { LiveMatchView(existingMatch: match) }
                    else if route.action == .result { NotificationMatchResultEditor(match: match) }
                    else { NavigationStack { MatchDetailView(match: match).toolbar { closeButton } } }
                } else { unavailable }
            case .tournament:
                if let tournament = store.data.tournaments.first(where: { $0.id == route.recordID }) {
                    NavigationStack { TournamentDetailView(tournament: tournament).toolbar { closeButton } }
                } else { unavailable }
            case .weekly:
                NavigationStack {
                    TennisWeeklyReview(records: store.data.achievementRecords, playerID: store.selectedPlayerID,
                        weekStart: route.weekStart ?? TennisReportingWeek.interval(containing: Date()).start)
                        .tennisThemedList().toolbar { closeButton }
                }
            case .achievements:
                NavigationStack { TennisAchievementsView(achievements: store.data.achievements).tennisThemedList().toolbar { closeButton } }
            }
        }.onAppear { selectRecordPlayer() }
    }
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
    }
    private var unavailable: some View {
        NavigationStack {
            TennisList {
                Text("This activity is no longer available. It may have been deleted.")
                    .accessibilityIdentifier("notificationActivityUnavailable")
            }.tennisThemedList().navigationTitle("Activity Unavailable").toolbar { closeButton }
        }
    }
    private func selectRecordPlayer() {
        let id = store.data.trainingSessions.first { $0.id == route.recordID }?.playerID ??
            store.data.matches.first { $0.id == route.recordID }?.playerID ??
            store.data.tournaments.first { $0.id == route.recordID }?.playerID
        if id != store.selectedPlayerID, let player = store.data.players.first(where: { $0.id == id }) { store.selectPlayer(player) }
    }
}

struct TrainingReflectionEditor: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TennisReflectionDraft
    @State private var message = ""
    init(session: TrainingSession) { _draft = State(initialValue: TennisReflectionDraft(session: session)) }
    private var current: TrainingSession? { store.data.trainingSessions.first { $0.id == draft.sessionID } }
    var body: some View {
        NavigationStack {
            TennisForm {
                if let current {
                    TennisReflectionFields(draft: $draft, summary: store.trainingSummary(current, style: .short))
                } else { Text("This session is no longer available. Your reflection has not been saved.") }
                if !message.isEmpty { Text(message) }
            }
            .tennisThemedList().navigationTitle("Training Reflection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Reflection") {
                        guard let current, !current.isActive, let updated = draft.applying(to: current) else {
                            message = "This session is unavailable or still active. Finish tracking before saving a reflection."
                            store.announce(message); return
                        }
                        store.upsertTraining(updated); dismiss()
                    }.disabled(current == nil).accessibilityIdentifier("saveTrainingReflection")
                }
            }
        }
    }
}

struct NotificationMatchResultEditor: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MatchRecord
    @State private var message = ""
    init(match: MatchRecord) { _draft = State(initialValue: TennisNotificationResult.draft(match)) }
    var body: some View {
        NavigationStack {
            TennisForm {
                Text(TennisSummaryFormatter.match(draft, style: .short)).accessibilityIdentifier("notificationMatchSummary")
                if !message.isEmpty { Text(message) }
                OrderedChoicePicker(title: "Match format", selection: $draft.matchFormat, values: MatchFormat.allCases) { $0.label }
                TennisRecordedScoreFields(match: $draft)
                TextField("Next practice focus", text: $draft.nextPracticeFocus, axis: .vertical)
            }.tennisThemedList().navigationTitle("Match Result")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Result") {
                        if let error = TennisRecordedScore.validationMessage(for: draft) { message = error; store.announce(error); return }
                        guard let current = store.data.matches.first(where: { $0.id == draft.id }),
                              let updated = TennisNotificationResult.applying(draft, to: current) else {
                            message = "This match is unavailable or live scoring has started. Close this reminder and resume the live match."
                            store.announce(message); return
                        }
                        store.upsertMatch(updated); dismiss()
                    }.accessibilityIdentifier("saveNotificationMatchResult")
                }
            }
        }
    }
}
