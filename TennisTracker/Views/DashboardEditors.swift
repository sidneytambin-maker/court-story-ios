import SwiftUI

struct TrainingFocusEditor: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    let session: TrainingSession
    @State private var focus: String
    @State private var additionalFocus: [String]

    init(session: TrainingSession) {
        self.session = session
        _focus = State(initialValue: session.focus)
        _additionalFocus = State(initialValue: session.additionalFocus)
    }
    var body: some View {
        NavigationStack {
            TennisTrainingFocusChoices(focus: $focus, additionalFocus: $additionalFocus)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if var latest = store.data.trainingSessions.first(where: { $0.id == session.id }) {
                                latest.focus = focus; latest.additionalFocus = additionalFocus
                                store.upsertTraining(latest)
                            }
                            dismiss()
                        }.accessibilityIdentifier("saveDashboardFocus")
                    }
                }
        }
    }
}

struct PlayerGoalsEditor: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    let playerID: UUID
    @State private var goal: String
    @State private var coachingFocus: String

    init(player: PlayerProfile) {
        playerID = player.id
        _goal = State(initialValue: player.primaryGoal)
        _coachingFocus = State(initialValue: player.coachingFocus)
    }
    var body: some View {
        NavigationStack {
            TennisForm {
                TextField("Personal tennis goal", text: $goal, axis: .vertical)
                    .accessibilityIdentifier("personalGoalField")
                    .accessibilityHint("For example, improve second-serve consistency. Saved goals appear in What to work on.")
                TextField("Coaching priority", text: $coachingFocus, axis: .vertical)
                    .accessibilityIdentifier("coachingPriorityField")
                    .accessibilityHint("An area to discuss or practise with your coach.")
            }
            .navigationTitle("Goals and Priorities")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if var player = store.data.players.first(where: { $0.id == playerID }) {
                            player.primaryGoal = goal; player.coachingFocus = coachingFocus
                            store.upsertPlayer(player)
                        }
                        dismiss()
                    }.accessibilityIdentifier("savePlayerGoals")
                }
            }
        }
    }
}

struct MatchReviewEditor: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    let matchID: UUID
    @State private var priority: String
    @State private var needsWork: String
    init(match: MatchRecord) {
        matchID = match.id
        _priority = State(initialValue: match.nextPracticeFocus)
        _needsWork = State(initialValue: match.matchNeedsWork)
    }
    var body: some View {
        TennisForm {
            TextField("Next practice focus", text: $priority, axis: .vertical)
                .accessibilityIdentifier("matchReviewPriorityField")
                .accessibilityHint("Record what to practise after this match. Your latest completed match review appears in What to work on.")
            TextField("What needs work", text: $needsWork, axis: .vertical)
                .accessibilityHint("Used as your review priority when Next practice focus is empty.")
        }
        .navigationTitle("Match Review")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if var match = store.data.matches.first(where: { $0.id == matchID }) {
                        match.nextPracticeFocus = priority; match.matchNeedsWork = needsWork
                        store.upsertMatch(match)
                    }
                    dismiss()
                }.accessibilityIdentifier("saveMatchReview")
            }
        }
    }
}
