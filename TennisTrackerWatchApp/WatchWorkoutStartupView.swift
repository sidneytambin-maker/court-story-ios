import SwiftUI

struct WatchWorkoutStartupView: View {
    @EnvironmentObject private var store: WatchTennisStore
    @AccessibilityFocusState private var statusFocused: Bool

    var body: some View {
        Section {
            Text(store.workoutMessage)
                .accessibilityIdentifier(store.isPreparingWorkout ? "healthStartProgress" : "healthStartFailure")
                .accessibilityFocused($statusFocused)
            if store.isPreparingWorkout {
                ProgressView().accessibilityHidden(true)
            } else {
                Button("Retry Workout") { store.retryHealthStart() }
                    .accessibilityIdentifier("retryWatchWorkout")
                    .accessibilityHint("Checks Health access again and starts this same workout. Does not create a duplicate session.")
                NavigationLink("Health Access") { WatchWorkoutSettingsView() }
                Button("Use Session Timer Only") { store.startPendingTrainingWithoutHealth() }
                    .accessibilityIdentifier("timerOnlyRecovery")
                    .accessibilityHint("Starts timing without a Health workout or Health measurements. Does not change your usual setting.")
                if !store.healthClient.diagnosticCode.isEmpty {
                    Text(store.healthClient.diagnosticCode).font(.footnote)
                        .accessibilityLabel("Health diagnostic: " + store.healthClient.diagnosticCode)
                }
            }
            Button("Cancel Workout Start", role: .cancel) { store.cancelPendingTrainingStart() }
                .accessibilityIdentifier("cancelWatchWorkoutStart")
        }
        .onAppear { statusFocused = true }
        .onChange(of: store.isPreparingWorkout) { _, preparing in
            if !preparing { statusFocused = true }
        }
    }
}

struct WatchWorkoutSettingsView: View {
    @EnvironmentObject private var store: WatchTennisStore
    @State private var requesting = false
    @State private var message = ""
    @AccessibilityFocusState private var statusFocused: Bool

    var body: some View {
        Form {
            if let player = store.selectedPlayer, store.mayUseHealth(for: player.id) {
                Toggle("Save My Workouts to Health", isOn: Binding(get: { store.defaultUseHealth }, set: store.setDefaultUseHealth))
                    .accessibilityHint("Applies only to the Watch owner's workouts, never a coached player's activity.")
                Text(store.workoutAccess.description)
                if store.workoutAccess == .denied {
                    Text("On your Watch, open Settings, Health, Apps, then Court Story and allow Workouts. Return here and retry your workout.")
                } else {
                    Button("Review Health Access") {
                        requesting = true
                        Task {
                            message = await store.reviewHealthAccess()
                            requesting = false
                            statusFocused = true
                        }
                    }.disabled(requesting || store.isPreparingWorkout)
                }
                if !message.isEmpty { Text(message).accessibilityFocused($statusFocused) }
            } else {
                Text("Health belongs to the Watch owner. Coaching another player uses session timing, without recording their activity as your own workout.")
            }
        }.navigationTitle("Health Access")
    }
}
