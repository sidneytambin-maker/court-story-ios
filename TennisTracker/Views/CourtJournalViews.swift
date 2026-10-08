import SwiftUI

struct CourtObservationEditor: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    @State var observation: CourtObservation
    @State private var error = ""
    @State private var planned: TrainingSession?
    @State private var confirmDelete = false
    @AccessibilityFocusState private var errorFocused: Bool
    private var athlete: PlayerProfile? { store.data.players.first { $0.id == observation.athleteID } }

    var body: some View {
        NavigationStack {
            TennisForm {
                if CourtFeature.observations.isAvailable(in: store.data.settings.trackingMode), let athlete {
                    Section {
                        CourtCaptureIdentity(athlete: athlete.displayName, sport: observation.sport, coached: true)
                        DatePicker("Observation date", selection: $observation.date, displayedComponents: .date)
                        Picker("Focus", selection: $observation.focus) {
                            Text("Not specified").tag("")
                            ForEach(Array(Set(observation.sport.sport.focuses + (observation.focus.isBlank ? [] : [observation.focus]))).sorted(), id: \.self) { Text($0).tag($0) }
                        }
                        TextField("What happened", text: $observation.happened, axis: .vertical).accessibilityIdentifier("observationHappened")
                        TextField("Your interpretation", text: $observation.interpretation, axis: .vertical)
                            .accessibilityHint("Your coaching judgement, not a measured fact.")
                        TextField("Player perspective", text: $observation.playerPerspective, axis: .vertical)
                        TextField("Next action", text: $observation.nextAction, axis: .vertical).accessibilityIdentifier("observationNextAction")
                    }
                    if store.data.court.observations.contains(where: { $0.id == observation.id }) {
                        Section {
                            Button("Plan practice from this observation", systemImage: "calendar.badge.plus") {
                                if store.saveObservation(observation) {
                                    var draft = observation.practicePlan(on: Date().addingTimeInterval(86400))
                                    draft.court.rules = athlete.court.sports.first { $0.sport == observation.sport }?.rules
                                    draft.court.access = athlete.court.sports.first { $0.sport == observation.sport }?.access
                                    planned = draft
                                } else { error = store.lastAnnouncement; errorFocused = true }
                            }.disabled(observation.nextAction.isBlank || athlete.isArchived)
                            Button("Delete observation", role: .destructive) { confirmDelete = true }
                        }
                    }
                    if !error.isEmpty { Text(error).foregroundStyle(.red).accessibilityFocused($errorFocused) }
                } else { Text("Observations are available in Standard and Power modes. Existing notes are retained.") }
            }
            .navigationTitle("Observation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.saveObservation(observation) { dismiss() }
                        else { error = observation.validationMessage ?? store.lastAnnouncement; errorFocused = true }
                    }.disabled(!CourtFeature.observations.isAvailable(in: store.data.settings.trackingMode))
                        .accessibilityIdentifier("saveObservation")
                }
            }
            .sheet(item: $planned) { TrainingEditorView(session: $0) }
            .confirmationDialog("Delete this observation?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete observation", role: .destructive) { if store.removeCoachingRecord(observation.id) { dismiss() } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct CourtDrillEditor: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    @State var drill: CourtMeasuredDrill
    @State private var error = ""
    @State private var confirmDelete = false
    @AccessibilityFocusState private var errorFocused: Bool
    var body: some View {
        NavigationStack {
            TennisForm {
                if CourtFeature.measuredDrills.isAvailable(in: store.data.settings.trackingMode) {
                    Section {
                        CourtCaptureIdentity(athlete: store.data.players.first { $0.id == drill.athleteID }?.displayName ?? "Unavailable athlete", sport: drill.sport, coached: true)
                        TextField("Drill name", text: $drill.name).accessibilityIdentifier("drillName")
                        DatePicker("Measurement date", selection: $drill.date, displayedComponents: .date)
                        TextField("Focus", text: $drill.focus)
                        TextField("Successful attempts", value: $drill.successfulAttempts, format: .number).keyboardType(.numberPad).accessibilityIdentifier("successfulAttempts")
                        TextField("Total attempts", value: $drill.totalAttempts, format: .number).keyboardType(.numberPad).accessibilityIdentifier("totalAttempts")
                        TextField("Setup and distance", text: $drill.setup, axis: .vertical)
                        TextField("Conditions", text: $drill.conditions, axis: .vertical)
                        Toggle("Additional measurement", isOn: Binding(get: { drill.measurement != nil }, set: { drill.measurement = $0 ? 0 : nil }))
                        if drill.measurement != nil {
                            TextField("Measurement", value: Binding(get: { drill.measurement ?? 0 }, set: { drill.measurement = $0 }), format: .number).keyboardType(.decimalPad)
                            TextField("Unit", text: $drill.unit)
                        }
                        if drill.validationMessage == nil { Text(drill.summary) }
                    }
                    if store.data.court.drills.contains(where: { $0.id == drill.id }) {
                        Section { Button("Delete measured drill", role: .destructive) { confirmDelete = true } }
                    }
                    if !error.isEmpty { Text(error).foregroundStyle(.red).accessibilityFocused($errorFocused) }
                } else { Text("Measured drills are available in Power mode. Existing measurements are retained.") }
            }.navigationTitle("Measured drill")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.saveMeasuredDrill(drill) { dismiss() }
                        else { error = drill.validationMessage ?? store.lastAnnouncement; errorFocused = true }
                    }.disabled(!CourtFeature.measuredDrills.isAvailable(in: store.data.settings.trackingMode)).accessibilityIdentifier("saveMeasuredDrill")
                }
            }
            .confirmationDialog("Delete this measured drill?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete measured drill", role: .destructive) { if store.removeCoachingRecord(drill.id) { dismiss() } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct CourtJournalContent: View {
    @EnvironmentObject private var store: TennisStore
    let athleteID: UUID
    @State private var deleteID: UUID?
    private var observations: [CourtObservation] {
        store.data.court.observations.filter { $0.athleteID == athleteID && $0.sport == store.selectedSport }
            .sorted { $0.date > $1.date }
    }
    var body: some View {
        if CourtFeature.observations.isAvailable(in: store.data.settings.trackingMode), !observations.isEmpty {
            Section("Coaching journal") {
                ForEach(observations) { observation in
                    NavigationLink { CourtObservationEditor(observation: observation) } label: {
                        VStack(alignment: .leading) {
                            Text(observation.date, style: .date).font(.subheadline)
                            Text(observation.happened)
                            if !observation.nextAction.isBlank { Text("Next action: \(observation.nextAction)").font(.subheadline) }
                        }.accessibilityElement(children: .combine)
                    }.accessibilityAction(named: "Delete observation") { deleteID = observation.id }
                }
            }
            .confirmationDialog("Delete this observation?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } }), titleVisibility: .visible) {
                Button("Delete observation", role: .destructive) { if let deleteID { _ = store.removeCoachingRecord(deleteID) }; deleteID = nil }
                Button("Cancel", role: .cancel) { deleteID = nil }
            }
        }
    }
}
