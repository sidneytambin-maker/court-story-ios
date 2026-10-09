import SwiftUI

struct WatchTrainingEditor: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: TrainingSession
    @State private var linkedMatchIDs: [UUID] = []
    @State private var originalMatchIDs = Set<UUID>()
    @State private var loadedLinks = false
    @State private var durationWasEdited = false

    private var current: TrainingSession? { store.snapshot.trainingSessions.first { $0.id == draft.id } }

    var body: some View {
        Form {
            Picker("Training type", selection: $draft.trainingType) {
                ForEach(TrainingType.allCases) { Text($0.rawValue).tag($0) }
            }
            TennisTrainingFocusPicker(focus: $draft.focus, additionalFocus: $draft.additionalFocus, sport: draft.court.sport.sport)
            if !draft.isActive && current?.isActive != true {
                Section("Duration") {
                    DurationFields(minutes: Binding(
                        get: { draft.durationMinutes },
                        set: { draft.setManualDuration(minutes: $0); durationWasEdited = true }
                    ), minimumMinutes: 1)
                    .pickerStyle(.navigationLink)
                }
            }
            TennisCoachPicker(coaches: store.snapshot.setup.coaches, context: $draft.context)
            NavigationLink("Players Present") {
                WatchPlayerChoices(players: store.snapshot.players.filter { $0.id != draft.playerID }, selectedIDs: $draft.context.participantIDs, otherSelected: .constant(false), allowsOther: false)
            }
            .accessibilityValue(draft.context.participantSummary(in: store.snapshot.players).fallback("None"))
            .onChange(of: draft.context.participantIDs) { _, _ in draft.context.participantNames = [] }
            WatchVenueFields(venueID: $draft.context.venueID, venue: $draft.venue, location: $draft.location)
            TennisTournamentPicker(tournaments: store.snapshot.scoped(playerID: draft.playerID, sport: draft.court.sport).tournaments, tournamentID: $draft.context.tournamentID, customName: $draft.context.customTournamentName)
            TennisLinkedMatchesPicker(matches: store.snapshot.scoped(playerID: draft.playerID, sport: draft.court.sport).matches, sessionID: draft.id, selected: $linkedMatchIDs)
            TextField("Notes", text: $draft.notes)
            Toggle("Include session feedback", isOn: $draft.hasSessionDetails)
            if draft.hasSessionDetails {
                TextField("Session outcome", text: $draft.sessionOutcome)
                OrderedChoicePicker(title: "Effort", selection: $draft.effortLevel, values: RatingLevel.allCases) { $0.rawValue }
            }
            Toggle("Details complete", isOn: Binding(get: { !draft.needsDetails }, set: { draft.needsDetails = !$0 }))
        }
        .navigationTitle("Edit Training")
        .onAppear {
            guard !loadedLinks else { return }
            linkedMatchIDs = store.snapshot.matches.filter { $0.trainingSessionID == draft.id }.map(\.id)
            originalMatchIDs = Set(linkedMatchIDs); loadedLinks = true
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    draft.context.captureLegacyNames(coaches: store.snapshot.setup.coaches, players: store.snapshot.players)
                    if draft.context.needsOtherCoachName { draft.needsDetails = true }
                    store.updateTrainingDetails(draft, durationWasEdited: durationWasEdited)
                    store.updateTrainingLinks(draft, original: originalMatchIDs, selected: Set(linkedMatchIDs))
                    dismiss()
                }
            }
        }
    }
}

struct WatchMatchEditor: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: MatchRecord
    @State private var original: MatchRecord?
    @State private var validationMessage = ""
    @State private var courtScoreError = ""

    var body: some View {
        Form {
            if !validationMessage.isBlank { Text(validationMessage) }
            if draft.court.sport.sport != .custom {
                TennisMatchPeopleFields(players: store.snapshot.players, match: $draft, showsKind: draft.status != .inProgress)
            }
            if draft.status != .inProgress, store.snapshot.matches.first(where: { $0.id == draft.id })?.status != .inProgress {
                WatchMatchScheduleFields(match: $draft)
            }
            OrderedChoicePicker(title: "Match round", selection: $draft.matchPosition, values: MatchPosition.allCases) { $0.label }
                .accessibilityIdentifier("matchRoundPicker")
            WatchVenueFields(venueID: $draft.venueID, venue: $draft.venue, location: $draft.location)
            TennisTournamentPicker(tournaments: store.snapshot.scoped(playerID: draft.playerID, sport: draft.court.sport).tournaments, tournamentID: $draft.tournamentID, customName: $draft.customTournamentName)
            TennisTrainingSessionPicker(sessions: store.snapshot.scoped(playerID: draft.playerID, sport: draft.court.sport).trainingSessions, coaches: store.snapshot.setup.coaches, selection: $draft.trainingSessionID)
            if draft.status == .completed {
                if draft.usesCourtScoring {
                    CourtRecordedScoreFields(match: $draft, validationMessage: $courtScoreError)
                } else {
                OrderedChoicePicker(title: "Match format", selection: $draft.matchFormat, values: MatchFormat.allCases) { $0.label }
                TennisRecordedScoreFields(match: $draft)
                }
            }
            Section("Conditions") { TennisMatchConditionsFields(match: $draft) }
            TextField("Next practice focus", text: $draft.nextPracticeFocus)
                .accessibilityHint("Your latest completed match review appears in What to work on on the iPhone dashboard.")
            TextField("Notes", text: $draft.notes)
            Toggle("Details complete", isOn: Binding(get: { !draft.needsDetails }, set: { draft.needsDetails = !$0 }))
        }
        .navigationTitle("Edit Match")
        .pickerStyle(.navigationLink)
        .onAppear { if original == nil { original = draft } }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if draft.usesCourtScoring {
                        if !courtScoreError.isEmpty { validationMessage = courtScoreError; store.announce(courtScoreError); return }
                        store.updateMatchDetails(draft, original: original); dismiss(); return
                    }
                    if draft.status == .completed, let error = TennisManualMatchEntry.validationMessage(for: draft) {
                        validationMessage = error; store.announce(error)
                    } else { store.updateMatchDetails(draft, original: original); dismiss() }
                }
            }
        }
    }
}

struct WatchTournamentEditor: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: TournamentRecord
    var isNew = false

    var body: some View {
        Form {
            TextField("Tournament name", text: $draft.name)
            WatchDateField(title: "Start date", date: $draft.date)
                .onChange(of: draft.date) { _, date in if draft.endDate < date { draft.endDate = date } }
            WatchDateField(title: "End date", date: $draft.endDate)
                .onChange(of: draft.endDate) { _, date in if date < draft.date { draft.endDate = draft.date } }
            WatchVenueFields(venueID: $draft.venueID, venue: $draft.venue, location: $draft.location)
            Picker("Stage reached", selection: $draft.stageReached) {
                ForEach(TournamentStage.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityValue(draft.stageReached.rawValue)
            .accessibilityIdentifier("watchTournamentStagePicker")
            Picker("Finishing position", selection: $draft.finishingPosition) {
                Text("Not recorded").tag(Optional<Int>.none)
                ForEach(TournamentFinishingPosition.allValues, id: \.self) { position in
                    Text(TournamentFinishingPosition.label(position)).tag(Optional(position))
                }
            }
            .accessibilityValue(TournamentFinishingPosition.label(draft.finishingPosition))
            .accessibilityHint("Optional final finishing position, independent of stage reached.")
            .accessibilityIdentifier("watchTournamentFinishingPositionPicker")
            TextField("Notes", text: $draft.notes)
            Toggle("Details complete", isOn: Binding(get: { !draft.needsDetails }, set: { draft.needsDetails = !$0 }))
        }
        .navigationTitle(isNew ? "Add Tournament" : "Edit Tournament")
        .pickerStyle(.navigationLink)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if isNew { store.saveTournamentRecord(draft) } else { store.updateTournamentDetails(draft) }
                    dismiss()
                }.disabled(draft.name.isBlank)
            }
        }
    }
}

struct WatchVenueFields: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Binding var venueID: UUID?
    @Binding var venue: String
    @Binding var location: String

    var body: some View {
        TennisVenuePicker(choices: store.snapshot.availableVenueChoices, locations: store.snapshot.setup.locations.map(\.name),
            venueID: $venueID, venue: $venue, location: $location)
    }
}

struct WatchDateField: View {
    let title: String
    @Binding var date: Date
    private let calendar = Calendar.current

    var body: some View {
        NavigationLink(title) {
            Form {
                OrderedChoicePicker(title: "Day", selection: component(.day), values: Array(calendar.range(of: .day, in: .month, for: date) ?? 1..<32)) { String($0) }
                OrderedChoicePicker(title: "Month", selection: component(.month), values: Array(1...12)) { calendar.monthSymbols[$0 - 1] }
                OrderedChoicePicker(title: "Year", selection: component(.year), values: Array(min(1900, calendar.component(.year, from: date))...max(2100, calendar.component(.year, from: date)))) { String($0) }
            }.navigationTitle(title)
        }.accessibilityValue(date.fullTennisDate)
    }

    private func component(_ component: Calendar.Component) -> Binding<Int> {
        Binding(get: { calendar.component(component, from: date) }, set: { value in
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            parts.setValue(value, for: component)
            let requestedDay = parts.day ?? 1
            parts.day = 1
            guard let first = calendar.date(from: parts), let range = calendar.range(of: .day, in: .month, for: first) else { return }
            parts.day = min(requestedDay, range.count)
            date = calendar.date(from: parts) ?? date
        })
    }
}
