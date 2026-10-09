import SwiftUI

struct WatchCourtJournalView: View {
    @EnvironmentObject private var store: WatchTennisStore
    let athleteID: UUID
    @State private var observation: CourtObservation?
    @State private var drill: CourtMeasuredDrill?
    @State private var deleting: UUID?
    private var athlete: PlayerProfile? { store.snapshot.players.first { $0.id == athleteID } }
    private var observations: [CourtObservation] {
        store.snapshot.court.observations.filter { $0.athleteID == athleteID && $0.sport == store.courtSport }
            .sorted { $0.date > $1.date }
    }
    private var drills: [CourtMeasuredDrill] {
        store.snapshot.court.drills.filter { $0.athleteID == athleteID && $0.sport == store.courtSport }
            .sorted { $0.date > $1.date }
    }
    var body: some View {
        List {
            if let athlete, let coach = store.workspaceOwner {
                CourtCaptureIdentity(athlete: athlete.displayName, sport: store.courtSport, coached: true)
                NavigationLink("Progress by Period") {
                    WatchCourtProgressView(athleteID: athleteID, sport: store.courtSport)
                }.accessibilityHint("Review this player's results, training, focus and goals for the selected period.")
                if CourtFeature.observations.isAvailable(in: store.snapshot.settings.trackingMode) {
                    if !athlete.isArchived {
                        Button("Add Observation", systemImage: "square.and.pencil") {
                            observation = CourtObservation(athleteID: athleteID, coachID: coach.id, sport: store.courtSport)
                        }.accessibilityIdentifier("watchAddObservation")
                    }
                    if !observations.isEmpty {
                        Section("Observations") {
                            ForEach(observations) { entry in
                                Button { observation = entry } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.date, style: .date).font(.caption)
                                        Text(entry.happened)
                                        if !entry.nextAction.isBlank { Text("Next: " + entry.nextAction).font(.footnote) }
                                    }.accessibilityElement(children: .combine)
                                }.accessibilityHint("Opens the observation to edit or plan practice.")
                                    .accessibilityAction(named: "Delete observation") { deleting = entry.id }
                            }
                        }
                    }
                }
                if CourtFeature.measuredDrills.isAvailable(in: store.snapshot.settings.trackingMode) {
                    if !athlete.isArchived {
                        Button("Record Measured Drill", systemImage: "chart.bar") {
                            drill = CourtMeasuredDrill(athleteID: athleteID, coachID: coach.id, sport: store.courtSport)
                        }.accessibilityIdentifier("watchAddMeasuredDrill")
                    }
                    if !drills.isEmpty {
                        Section("Measured drills") {
                            ForEach(drills) { entry in
                                Button { drill = entry } label: {
                                    VStack(alignment: .leading) {
                                        Text(entry.date, style: .date).font(.caption)
                                        Text(entry.summary)
                                    }.accessibilityElement(children: .combine)
                                }.accessibilityAction(named: "Delete measured drill") { deleting = entry.id }
                            }
                            if let newest = drills.first, let previous = drills.dropFirst().first(where: { newest.isComparable(to: $0) }),
                               let current = newest.proportion, let old = previous.proportion {
                                Text("\(newest.name): \(Int((current * 100).rounded())) percent successful, compared with \(Int((old * 100).rounded())) percent previously in the same recorded setup and conditions.")
                            }
                            Text("Compare only drills with matching setup, focus, conditions and units. These are recorded attempts, not an ability rating.").font(.footnote)
                        }
                    }
                }
                if CourtFeature.media.isAvailable(in: store.snapshot.settings.trackingMode) {
                    let media = store.snapshot.court.media.filter { $0.athleteID == athleteID && $0.sport == store.courtSport }
                    if !media.isEmpty {
                        Section("Media on iPhone") {
                            ForEach(media) { entry in
                                NavigationLink {
                                    List {
                                        Text(entry.description.fallback(entry.kind == .video ? "Video clip" : "Photo"))
                                        ForEach(entry.moments) { moment in
                                            Text("\(TennisDurationFormatter.text(seconds: moment.seconds)), \(moment.description). \(moment.observation) \(moment.nextAction)")
                                        }
                                        Text("Open this player's journal in Court Story on iPhone to view the original photo or play the video. Media files stay on iPhone.")
                                    }.navigationTitle("Media Details")
                                } label: { Text(entry.description.fallback(entry.kind == .video ? "Video clip" : "Photo")) }
                            }
                        }
                    }
                }
                if store.snapshot.settings.trackingMode == .basic {
                    Text("The journal is available in Standard and Power modes. Your existing notes and measurements are retained.")
                }
            } else { Text("This player is no longer available.") }
        }.navigationTitle("Player Journal")
            .sheet(item: $observation) { value in NavigationStack { WatchCourtObservationEditor(draft: value) } }
            .sheet(item: $drill) { value in NavigationStack { WatchCourtDrillEditor(draft: value) } }
            .confirmationDialog("Delete this coaching record?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let deleting { _ = store.saveCourtMutation(.deleteCoaching(deleting)) }; deleting = nil }
                Button("Cancel", role: .cancel) { deleting = nil }
            }
    }
}

private struct WatchCourtProgressView: View {
    @EnvironmentObject private var store: WatchTennisStore
    let athleteID: UUID
    let sport: CourtSportSelection
    @State private var days = 30
    private var through: Date { Date() }
    private var from: Date { Calendar.current.date(byAdding: .day, value: -days, to: through) ?? through }
    private var report: CourtProgressReport? {
        CourtProgressReport.make(athleteID: athleteID, sport: sport, data: store.snapshot.courtLibrary,
                                 from: from, through: through, includeGoal: true)
    }
    var body: some View {
        List {
            if let report {
                CourtCaptureIdentity(athlete: report.athlete, sport: sport, coached: true)
                Picker("Period", selection: $days) {
                    Text("Last 7 days").tag(7)
                    Text("Last 30 days").tag(30)
                    Text("Last 90 days").tag(90)
                    Text("Last year").tag(365)
                }.accessibilityIdentifier("watchProgressPeriod")
                Text("\(report.from.fullTennisDate) to \(report.through.fullTennisDate)")
                ForEach(report.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title).font(.headline)
                        Text(row.value)
                    }.accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.title).accessibilityValue(row.value)
                        .accessibilityIdentifier("watchProgress." + row.title)
                }
                if CourtFeature.measuredDrills.isAvailable(in: store.snapshot.settings.trackingMode) {
                    let drills = store.snapshot.court.drills.filter {
                        $0.athleteID == athleteID && $0.sport == sport && $0.date >= from && $0.date <= through
                            && !store.snapshot.court.deletedIDs.contains($0.id)
                    }.sorted { $0.date > $1.date }
                    ForEach(drills) { drill in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(drill.date, style: .date).font(.caption)
                            Text(drill.summary)
                            Text(drill.setup).font(.footnote)
                            Text(drill.conditions).font(.footnote)
                        }.accessibilityElement(children: .combine)
                    }
                    if !drills.isEmpty {
                        Text("Compare matching setups, focuses, conditions and units. Recorded attempts are not an ability rating.").font(.footnote)
                    }
                }
                Text("Recorded activity only. Missing records do not mean no activity took place.").font(.footnote)
            } else { Text("This player or sport is no longer available.") }
        }.navigationTitle("Player Progress").pickerStyle(.navigationLink)
    }
}

private struct WatchCourtObservationEditor: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: CourtObservation
    @State private var original: CourtObservation?
    @State private var error = ""
    @State private var plan: TrainingSession?
    @AccessibilityFocusState private var errorFocused: Bool
    var body: some View {
        Form {
            if CourtFeature.observations.isAvailable(in: store.snapshot.settings.trackingMode) {
                CourtCaptureIdentity(athlete: store.snapshot.players.first { $0.id == draft.athleteID }?.displayName ?? "Unavailable player", sport: draft.sport, coached: true)
                DatePicker("Observation date", selection: $draft.date, displayedComponents: .date)
                Picker("Focus", selection: $draft.focus) {
                    Text("Not specified").tag("")
                    ForEach(Array(Set(draft.sport.sport.focuses + (draft.focus.isBlank ? [] : [draft.focus]))).sorted(), id: \.self) { Text($0).tag($0) }
                }
                TextField("What happened", text: $draft.happened)
                TextField("Your interpretation", text: $draft.interpretation).accessibilityHint("Coaching judgement, not a measured fact.")
                TextField("Player perspective", text: $draft.playerPerspective)
                TextField("Next action", text: $draft.nextAction)
                if !error.isEmpty { Text(error).accessibilityFocused($errorFocused) }
                Button("Save Observation") { if save() { dismiss() } }
                if !draft.nextAction.isBlank, let player = store.snapshot.players.first(where: { $0.id == draft.athleteID }), !player.isArchived {
                    Button("Plan Practice") {
                        if save() {
                            var session = draft.practicePlan(on: Date().addingTimeInterval(86400))
                            let preference = player.court.sports.first { $0.sport == draft.sport }
                            session.court.access = preference?.access; session.court.rules = preference?.rules
                            plan = session
                        }
                    }
                }
            } else { Text("Choose Standard or Power mode to edit observations. Your notes are retained.") }
            Button("Cancel", role: .cancel) { dismiss() }
        }.navigationTitle("Observation").pickerStyle(.navigationLink)
            .onAppear { if original == nil { original = draft } }
            .sheet(item: $plan) { value in NavigationStack { WatchTrainingEditor(draft: value) } }
    }
    private func save() -> Bool {
        if let current = store.snapshot.court.observations.first(where: { $0.id == draft.id }), current != original {
            error = "This observation changed. Reopen it to see the latest version before saving."; errorFocused = true; return false
        }
        draft.revision += 1; draft.modifiedAt = Date()
        if store.saveCourtMutation(.observation(draft)) { original = draft; return true }
        error = draft.validationMessage ?? store.lastAnnouncement; errorFocused = true; return false
    }
}

private struct WatchCourtDrillEditor: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: CourtMeasuredDrill
    @State private var original: CourtMeasuredDrill?
    @State private var error = ""
    @AccessibilityFocusState private var errorFocused: Bool
    var body: some View {
        Form {
            if CourtFeature.measuredDrills.isAvailable(in: store.snapshot.settings.trackingMode) {
                CourtCaptureIdentity(athlete: store.snapshot.players.first { $0.id == draft.athleteID }?.displayName ?? "Unavailable player", sport: draft.sport, coached: true)
                TextField("Drill name", text: $draft.name)
                DatePicker("Measurement date", selection: $draft.date, displayedComponents: .date)
                TextField("Focus", text: $draft.focus)
                TextField("Successful attempts", value: $draft.successfulAttempts, format: .number)
                TextField("Total attempts", value: $draft.totalAttempts, format: .number)
                TextField("Setup and distance", text: $draft.setup)
                TextField("Conditions", text: $draft.conditions)
                Toggle("Additional measurement", isOn: Binding(get: { draft.measurement != nil }, set: { draft.measurement = $0 ? 0 : nil }))
                if draft.measurement != nil {
                    TextField("Measurement", value: Binding(get: { draft.measurement ?? 0 }, set: { draft.measurement = $0 }), format: .number)
                    TextField("Unit", text: $draft.unit)
                }
                if !error.isEmpty { Text(error).accessibilityFocused($errorFocused) }
                Button("Save Measured Drill") { save() }
            } else { Text("Choose Power mode to record measured drills. Existing measurements are retained.") }
            Button("Cancel", role: .cancel) { dismiss() }
        }.navigationTitle("Measured Drill")
            .onAppear { if original == nil { original = draft } }
    }
    private func save() {
        if let current = store.snapshot.court.drills.first(where: { $0.id == draft.id }), current != original {
            error = "This drill changed. Reopen it to see the latest version before saving."; errorFocused = true; return
        }
        draft.revision += 1; draft.modifiedAt = Date()
        if store.saveCourtMutation(.drill(draft)) { dismiss() }
        else { error = draft.validationMessage ?? store.lastAnnouncement; errorFocused = true }
    }
}
