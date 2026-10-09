import SwiftUI
import UIKit

struct TrainingView: View {
    @EnvironmentObject private var store: TennisStore
    @State private var showingNewTraining = false
    @State private var sessionToEdit: TrainingSession?
    @State private var sessionToDelete: TrainingSession?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            TennisList {
                Section {
                    Button("Track Training Session") { showingNewTraining = true }
                        .accessibilityLabel("Track Training Session")
                        .accessibilityIdentifier("addTrainingButton")
                }
                TennisSection("Training history") {
                    if store.selectedTraining.isEmpty {
                        EmptyStateView(title: "No training sessions recorded yet", message: "Use Track Training Session to save your first session.")
                    } else {
                        ForEach(store.selectedTraining) { session in
                            NavigationLink {
                                TrainingDetailView(session: session)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(store.trainingSummary(session))
                                }
                            }
                            .accessibilityLabel("Training session")
                            .accessibilityValue(store.trainingSummary(session, style: .accessibility))
                            .accessibilityAction(named: "Edit Training and Focus") {
                                sessionToEdit = session
                            }
                            .accessibilityActions {
                                if session.needsDetails && !session.isActive {
                                    Button("Review and Complete Training") {
                                        var draft = session
                                        draft.markDetailsComplete()
                                        sessionToEdit = draft
                                    }
                                }
                            }
                            .accessibilityAction(named: "Add to Calendar") {
                                addToCalendar(session)
                            }
                            .accessibilityAction(named: "Delete") {
                                sessionToDelete = session
                                confirmDelete = true
                            }
                        }
                    }
                }
            }
            .tennisThemedList()
            .navigationTitle("Training")
            .sheet(isPresented: $showingNewTraining) {
                if let session = store.makeDefaultTraining() {
                    TrainingEditorView(session: session)
                }
            }
            .sheet(item: $sessionToEdit) { session in
                TrainingEditorView(session: session)
            }
            .confirmationDialog("Delete this training session?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Training Session", role: .destructive) {
                    if let sessionToDelete {
                        store.deleteTraining(sessionToDelete)
                    }
                    sessionToDelete = nil
                }
                Button("Cancel", role: .cancel) { sessionToDelete = nil }
            }
        }
    }

    private func addToCalendar(_ session: TrainingSession) {
        Task {
            await store.addToCalendar(TennisCalendarMapper.event(for: session, coaches: store.data.setup.coaches, players: store.data.players))
        }
    }
}

struct TrainingDetailView: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State var session: TrainingSession
    @State private var editingTraining: TrainingSession?
    @State private var confirmDelete = false
    @State private var calendarMessage = ""

    var body: some View {
        TennisList {
            TennisSection("Summary") {
                Text(store.trainingSummary(session, style: .detailed))
                    .accessibilityAction(named: "Edit Training and Focus") { editingTraining = session }
                    .accessibilityAction(named: "Delete") { confirmDelete = true }
                    .accessibilityActions {
                        if session.needsDetails && !session.isActive {
                            Button("Review and Complete Training") {
                                var draft = session
                                draft.markDetailsComplete()
                                editingTraining = draft
                            }
                        }
                    }
                SummaryRow(title: "Outcome", value: session.sessionOutcome.fallback("not recorded"))
            }

            if store.data.settings.trackingMode == .power && session.hasSessionDetails {
                TennisSection("Body") {
                    SummaryRow(title: "Effort", value: session.effortLevel.rawValue)
                    SummaryRow(title: "Confidence", value: session.confidenceLevel.rawValue)
                    SummaryRow(title: "Energy", value: session.energyLevel.rawValue)
                    SummaryRow(title: "Pain", value: session.painLevel.rawValue)
                }
            }

            TennisSection("Notes") {
                Text(session.notes.fallback("No notes recorded."))
            }

            Section {
                Button("Add to Apple Calendar") {
                    addToCalendar()
                }
                if !calendarMessage.isBlank {
                    Text(calendarMessage)
                }
            }

            Section {
                Button("Delete training session", role: .destructive) { confirmDelete = true }
                    .accessibilityHidden(voiceOver)
            }
        }
        .tennisThemedList()
        .navigationTitle("Training detail")
        .onChange(of: store.data.trainingSessions) { _, sessions in
            if let updated = sessions.first(where: { $0.id == session.id }) { session = updated }
            else { dismiss() }
        }
        .toolbar {
            Button("Edit") { editingTraining = session }
                .accessibilityHidden(voiceOver)
        }
        .sheet(item: $editingTraining) { draft in
            TrainingEditorView(session: draft)
        }
        .confirmationDialog("Delete this training session?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Training Session", role: .destructive) {
                store.deleteTraining(session)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func addToCalendar() {
        Task {
            calendarMessage = await store.addToCalendar(TennisCalendarMapper.event(for: session, coaches: store.data.setup.coaches, players: store.data.players))
        }
    }

}

struct TrainingEditorView: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    @State var session: TrainingSession
    @State private var validationMessage = ""
    @State private var newPlayers: [PlayerProfile] = []
    @State private var linkedMatchIDs: [UUID] = []
    @State private var originalMatchIDs = Set<UUID>()
    @State private var loadedLinks = false

    var body: some View {
        NavigationStack {
            TennisForm {
                if !validationMessage.isBlank {
                    Text(validationMessage).accessibilityIdentifier("trainingValidation")
                }
                TennisSection("Session") {
                    CourtCaptureIdentity(athlete: store.data.players.first { $0.id == session.playerID }?.displayName ?? "Player unavailable", sport: session.court.sport, coached: session.court.enteredByCoachID != nil)
                    Picker("Training type", selection: $session.trainingType) {
                        ForEach(TrainingType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityIdentifier("trainingTypePicker")
                    TennisTrainingFocusPicker(focus: $session.focus, additionalFocus: $session.additionalFocus, sport: session.court.sport.sport)
                    DatePicker("Date", selection: $session.date, displayedComponents: .date)
                        .accessibilityIdentifier("trainingDatePicker")
                }
                DurationPicker(title: "Duration", minutes: Binding(
                    get: { session.durationMinutes },
                    set: { session.setManualDuration(minutes: $0) }
                ))
                TrainingEntryDetails(session: $session, newPlayers: $newPlayers, linkedMatchIDs: $linkedMatchIDs)
                if session.court.enteredByCoachID != nil {
                    Section("Session plan") { CourtPlanFields(plan: Binding(get: { session.court.plan ?? CourtSessionPlan() }, set: { session.court.plan = $0 })) }
                }
                if store.data.settings.trackingMode == .power {
                    TennisSection("Session ratings") {
                        TrainingRatingsFields(session: $session)
                    }
                }
            }
            .tennisThemedList()
            .navigationTitle("Training")
            .onAppear {
                guard !loadedLinks else { return }
                linkedMatchIDs = store.data.matches.filter { $0.playerID == session.playerID && $0.court.sport == session.court.sport && $0.trainingSessionID == session.id }.map(\.id)
                originalMatchIDs = Set(linkedMatchIDs); loadedLinks = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("saveTrainingButton")
                }
            }
            .onChange(of: session.context.coachIDs) { _, _ in session.context.coachName = "" }
            .onChange(of: session.context.participantIDs) { _, ids in
                if ids.isEmpty { session.context.participantNames = [] }
            }
        }
    }

    private func save() {
        guard session.durationMinutes > 0 else {
            validationMessage = "Enter a training duration."
            UIAccessibility.post(notification: .announcement, argument: validationMessage)
            return
        }
        session.needsDetails = session.context.participantsNeedDetails == true || session.context.coachesNeedDetails == true || session.context.needsOtherCoachName
        guard store.upsertTraining(session, newPlayers: newPlayers) else { validationMessage = store.lastAnnouncement; return }
        store.updateTrainingLinks(session, original: originalMatchIDs, selected: Set(linkedMatchIDs))
        dismiss()
    }
}
