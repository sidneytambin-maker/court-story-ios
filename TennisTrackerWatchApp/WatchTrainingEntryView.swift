import SwiftUI

struct WatchTrainingEntryView: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    @State private var selection: TrainingSession?
    @State private var candidates: [TrainingSession] = []
    @State private var newSession = false
    @State private var configured = false
    @State private var editing = false

    var body: some View {
        Group {
            if store.activeTraining != nil {
                List { Button("Return to Active Training") { store.page = .live; dismiss() } }
            } else if !configured {
                ProgressView()
            } else if newSession || candidates.isEmpty {
                WatchTrainingSetupView()
            } else if let selection, let current = store.snapshot.trainingSessions.first(where: { $0.id == selection.id }) {
                List {
                    Text(store.trainingSummary(current)).accessibilityIdentifier("Scheduled training preview")
                    Button("Start Workout") {
                        if store.beginTraining(current) { dismiss() }
                    }.buttonStyle(.borderedProminent).tint(TennisSportStyle.ball).foregroundStyle(TennisSportStyle.ink)
                        .accessibilityIdentifier("startWatchWorkout")
                        .accessibilityHint(store.workoutStartHint)
                        .disabled(store.isPreparingWorkout || store.isFinishingWorkout)
                    Button("Edit Details") { editing = true }
                    Button("Start a Different Session") { newSession = true }
                }.navigationTitle("Scheduled")
                .sheet(isPresented: $editing) { NavigationStack { WatchTrainingEditor(draft: current) } }
            } else {
                List {
                    ForEach(candidates.filter { candidate in store.snapshot.trainingSessions.contains { $0.id == candidate.id } }) { training in
                        Button(store.trainingSummary(training)) { selection = training }
                    }
                    Button("Start a Different Session") { newSession = true }
                }.navigationTitle("Choose Training")
            }
        }
        .onAppear {
            guard !configured else { return }
            candidates = TennisScheduling.nearbyTraining(in: store.scopedSnapshot)
            if candidates.count == 1 { selection = candidates.first }
            configured = true
        }
    }
}
