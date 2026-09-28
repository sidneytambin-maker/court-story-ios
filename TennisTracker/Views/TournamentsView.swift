import SwiftUI

struct TournamentsView: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var showingNewTournament = false
    @State private var tournamentToEdit: TournamentRecord?
    @State private var tournamentToDelete: TournamentRecord?
    @State private var matchTournament: TournamentRecord?
    @State private var confirmDelete = false
    @State private var pendingTournamentFocus: UUID?
    @AccessibilityFocusState private var focusedTournamentID: UUID?

    private var upcoming: [TournamentRecord] {
        store.selectedTournaments.filter { !$0.isCompleted }.sorted { $0.date < $1.date }
    }

    private var completed: [TournamentRecord] {
        store.selectedTournaments.filter(\.isCompleted).sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                tournamentList
                    .onChange(of: pendingTournamentFocus) { _, id in
                        guard let id else { return }
                        guard voiceOver, store.selectedTournaments.contains(where: { $0.id == id }) else {
                            pendingTournamentFocus = nil
                            return
                        }
                        scroll.scrollTo(id, anchor: .center)
                    }
            }
            .tennisThemedList()
            .navigationTitle("Tournaments")
            .onDisappear { pendingTournamentFocus = nil }
            .onChange(of: voiceOver) { _, enabled in
                if !enabled { pendingTournamentFocus = nil }
            }
            .sheet(isPresented: $showingNewTournament) {
                if let tournament = store.makeDefaultTournament() {
                    TournamentEditorView(tournament: tournament)
                }
            }
            .sheet(item: $tournamentToEdit) { tournament in
                TournamentEditorView(tournament: tournament)
            }
            .sheet(item: $matchTournament) { tournament in
                if let match = store.makeDefaultMatch(tournamentID: tournament.id) {
                    MatchEditorView(match: match)
                }
            }
            .confirmationDialog("Delete this tournament?", isPresented: $confirmDelete, titleVisibility: .visible) {
                if let selectedTournament = tournamentToDelete, !store.linkedMatches(for: selectedTournament).isEmpty {
                    Button("Delete Tournament Only, Keep Matches", role: .destructive) {
                        store.deleteTournamentKeepingMatches(selectedTournament)
                        tournamentToDelete = nil
                    }
                    Button("Delete Tournament and Linked Matches", role: .destructive) {
                        store.deleteTournamentAndLinkedMatches(selectedTournament)
                        tournamentToDelete = nil
                    }
                } else {
                    Button("Delete Tournament", role: .destructive) {
                        if let selectedTournament = tournamentToDelete {
                            store.deleteTournamentKeepingMatches(selectedTournament)
                        }
                        tournamentToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { tournamentToDelete = nil }
            }
        }
    }

    private var tournamentList: some View {
        TennisList {
            Section {
                Button("Track Tournament") { showingNewTournament = true }
                    .accessibilityLabel("Track Tournament")
                    .accessibilityIdentifier("addTournamentButton")
            }
            if store.selectedTournaments.isEmpty {
                Section {
                    EmptyStateView(title: "No tournaments added yet", message: "Track an upcoming tournament, then link matches to it later.")
                }
            } else {
                TennisSection("Upcoming tournaments") {
                    if upcoming.isEmpty { Text("No upcoming tournaments.") }
                    else { ForEach(upcoming) { tournamentRow($0) } }
                }
                TennisSection("Completed tournaments") {
                    if completed.isEmpty { Text("No completed tournaments.") }
                    else { ForEach(completed) { tournamentRow($0) } }
                }
            }
        }
    }

    private func tournamentRow(_ tournament: TournamentRecord) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                TournamentDetailView(tournament: tournament)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tournament.name.fallback("Unnamed tournament"))
                    Label(tournament.statusText, systemImage: tournament.statusSymbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(TennisSummaryFormatter.tournament(tournament, matches: store.linkedMatches(for: tournament), includeName: false))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(tournament.name.fallback("Unnamed tournament"))
            .accessibilityValue(TennisSummaryFormatter.tournament(tournament, style: .accessibility, matches: store.linkedMatches(for: tournament), includeName: false))
            .accessibilityIdentifier("tournamentList." + tournament.id.uuidString)
            .accessibilityFocused($focusedTournamentID, equals: tournament.id)
            .onAppear {
                guard voiceOver, pendingTournamentFocus == tournament.id else { return }
                // Restore focus only when the replacement row has appeared in its new section.
                focusedTournamentID = tournament.id
                pendingTournamentFocus = nil
            }
            .accessibilityAction(named: tournament.completionActionTitle) {
                toggleCompletion(tournament.id)
            }
            .accessibilityAction(named: "Edit tournament") {
                tournamentToEdit = tournament
            }
            .accessibilityAction(named: "Add Match to Tournament") {
                matchTournament = tournament
            }
            .accessibilityAction(named: "Add to Calendar") {
                addToCalendar(tournament)
            }
            .accessibilityAction(named: "Delete tournament") {
                tournamentToDelete = tournament
                confirmDelete = true
            }
            Button {
                toggleCompletion(tournament.id)
            } label: {
                Label(tournament.completionActionTitle, systemImage: tournament.completionActionSymbol)
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .help(tournament.completionActionTitle)
            .accessibilityHidden(voiceOver)
        }
        .id(tournament.id)
    }

    private func toggleCompletion(_ id: UUID) {
        guard store.toggleTournamentCompletion(id), voiceOver else { return }
        focusedTournamentID = nil
        pendingTournamentFocus = id
    }

    private func addToCalendar(_ tournament: TournamentRecord) {
        Task {
            await store.addToCalendar(TennisCalendarMapper.event(for: tournament))
        }
    }
}

struct TournamentDetailView: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State var tournament: TournamentRecord
    @State private var showingEditor = false
    @State private var showingNewMatch = false
    @State private var confirmDelete = false
    @State private var calendarMessage = ""

    private var linkedMatches: [MatchRecord] {
        store.linkedMatches(for: tournament)
    }

    var body: some View {
        TennisList {
            TennisSection("Summary") {
                VStack(alignment: .leading, spacing: 12) {
                    SummaryRow(title: "Dates", value: TennisSummaryFormatter.dateRange(from: tournament.date, through: tournament.endDate))
                    if !tournament.venue.isBlank || !tournament.location.isBlank {
                        SummaryRow(title: "Venue", value: [tournament.venue, tournament.location].filter { !$0.isBlank }.joined(separator: ", "))
                    }
                    SummaryRow(title: "Status", value: tournament.statusText)
                    SummaryRow(title: "Format", value: tournament.format.rawValue)
                    SummaryRow(title: "Stage reached", value: tournament.stageReached.rawValue)
                    SummaryRow(title: "Finishing position", value: TournamentFinishingPosition.label(tournament.finishingPosition))
                    SummaryRow(title: "Matches", value: linkedMatches.isEmpty ? "No matches linked yet." : "\(linkedMatches.count) \(linkedMatches.count == 1 ? "match" : "matches") linked.")
                    if let start = tournament.actualStart, let finish = tournament.actualFinish {
                        SummaryRow(title: "Tracked duration", value: TennisDurationFormatter.text(seconds: finish.timeIntervalSince(start)))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tournament.name.fallback("Unnamed tournament"))
                .accessibilityValue(TennisSummaryFormatter.tournament(tournament, style: .detailed, matches: linkedMatches, includeName: false))
                .accessibilityAction(named: tournament.completionActionTitle) {
                    store.toggleTournamentCompletion(tournament.id)
                }
                .accessibilityIdentifier("tournamentDetailsSummary")
                Button {
                    store.toggleTournamentCompletion(tournament.id)
                } label: {
                    Label(tournament.completionActionTitle, systemImage: tournament.completionActionSymbol)
                }
                .accessibilityIdentifier("tournamentCompletionButton")
                .help(tournament.completionActionTitle)
                .accessibilityHidden(voiceOver)
            }

            TennisSection("Matches") {
                Button("Add Match to Tournament") { showingNewMatch = true }
                    .accessibilityIdentifier("addTournamentMatchButton")
                if linkedMatches.isEmpty {
                    Text("Tournament matches will appear here after they are saved.")
                } else {
                    ForEach(linkedMatches) { match in
                        NavigationLink {
                            MatchDetailView(match: match)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(TennisSummaryFormatter.match(match, tournaments: store.selectedTournaments, style: .short))
                                Text(match.matchPosition.rawValue)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel("Tournament match")
                        .accessibilityValue(TennisSummaryFormatter.match(match, tournaments: store.selectedTournaments, style: .accessibility))
                    }
                }
            }

            if !tournament.goal.isBlank {
                TennisSection("Goal") {
                    Text(tournament.goal)
                }
            }

            TennisSection("Notes") {
                Text(tournament.notes.fallback("No notes recorded."))
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
                Button("Delete tournament", role: .destructive) { confirmDelete = true }
            }
        }
        .tennisThemedList()
        .navigationTitle(tournament.name.fallback("Tournament"))
        .onChange(of: store.data.tournaments) { _, tournaments in
            if let updated = tournaments.first(where: { $0.id == tournament.id }) { tournament = updated }
            else { dismiss() }
        }
        .toolbar {
            Button("Edit") { showingEditor = true }
        }
        .sheet(isPresented: $showingEditor) {
            TournamentEditorView(tournament: tournament)
        }
        .sheet(isPresented: $showingNewMatch) {
            if let match = store.makeDefaultMatch(tournamentID: tournament.id) {
                MatchEditorView(match: match)
            }
        }
        .confirmationDialog("Delete this tournament?", isPresented: $confirmDelete, titleVisibility: .visible) {
            if linkedMatches.isEmpty {
                Button("Delete Tournament", role: .destructive) {
                    store.deleteTournamentKeepingMatches(tournament)
                }
            } else {
                Button("Delete Tournament Only, Keep Matches", role: .destructive) {
                    store.deleteTournamentKeepingMatches(tournament)
                }
                Button("Delete Tournament and Linked Matches", role: .destructive) {
                    store.deleteTournamentAndLinkedMatches(tournament)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func addToCalendar() {
        Task {
            calendarMessage = await store.addToCalendar(TennisCalendarMapper.event(for: tournament))
        }
    }

    private var dateRangeText: String {
        let base = "\(tournament.date.shortTennisDate), \(tournament.location.fallback("location not recorded"))."
        if Calendar.current.isDate(tournament.date, inSameDayAs: tournament.endDate) {
            return base
        }
        return "\(tournament.date.shortTennisDate) to \(tournament.endDate.shortTennisDate), \(tournament.location.fallback("location not recorded"))."
    }

    private func scoreSummary(_ match: MatchRecord) -> String {
        TennisSummaryFormatter.matchSummary(match, tournaments: store.selectedTournaments).scoreText
    }
}

struct TournamentEditorView: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    @State var tournament: TournamentRecord

    var body: some View {
        NavigationStack {
            TennisForm {
                TennisSection("Tournament") {
                    Picker("Regular tournament", selection: $tournament.templateID) {
                        Text("Other").tag(Optional<UUID>.none)
                        ForEach(store.data.setup.tournamentTemplates) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .onChange(of: tournament.templateID) { _, id in
                        if let template = store.data.setup.tournamentTemplates.first(where: { $0.id == id }) {
                            tournament.name = template.name
                            tournament.format = template.format
                            tournament.venueID = template.venueID
                            if let venue = store.data.setup.venues.first(where: { $0.id == template.venueID }) {
                                tournament.venue = venue.name; tournament.location = venue.town
                            }
                        }
                    }
                    TextField("Name", text: $tournament.name)
                        .accessibilityIdentifier("tournamentNameField")
                    StoredVenuePicker(id: $tournament.venueID, venue: $tournament.venue, location: $tournament.location)
                    Toggle("All-day tournament", isOn: $tournament.isAllDay)
                    AccessibleDateTimeEditor(
                        dateTitle: "Start date",
                        timeTitle: "Start time",
                        date: $tournament.date,
                        hasStartTime: $tournament.hasStartTime,
                        allowsUnspecifiedTime: !tournament.isAllDay
                    )
                        .accessibilityIdentifier("tournamentStartDatePicker")
                    DatePicker("End date", selection: $tournament.endDate, in: Calendar.current.startOfDay(for: tournament.date)..., displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .accessibilityLabel("Tournament end date")
                        .accessibilityValue(tournament.endDate.fullTennisDate)
                        .accessibilityHint("Opens the native date picker. The end date cannot be before the start date.")
                        .accessibilityIdentifier("tournamentEndDatePicker")
                }

                TennisSection("Progress and result") {
                    Picker("Status", selection: $tournament.effectiveStatus) {
                        ForEach(TournamentResult.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityValue(tournament.effectiveStatus.rawValue)
                    .accessibilityIdentifier("tournamentStatusPicker")
                    Picker("Stage reached", selection: $tournament.stageReached) {
                        ForEach(TournamentStage.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityValue(tournament.stageReached.rawValue)
                    .accessibilityIdentifier("tournamentStagePicker")
                    Picker("Finishing position", selection: $tournament.finishingPosition) {
                        Text("Not recorded").tag(Optional<Int>.none)
                        ForEach(TournamentFinishingPosition.allValues, id: \.self) { position in
                            Text(TournamentFinishingPosition.label(position)).tag(Optional(position))
                        }
                    }
                    .accessibilityValue(TournamentFinishingPosition.label(tournament.finishingPosition))
                    .accessibilityHint("Optional final finishing position, independent of stage reached.")
                    .accessibilityIdentifier("tournamentFinishingPositionPicker")
                }

                TennisOptionalSection("More tournament details", mode: store.data.settings.trackingMode, identifier: "tournamentOptionalDetails") {
                    TextField("Category", text: $tournament.category)
                    Picker("Format", selection: $tournament.format) {
                        ForEach(TournamentFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityIdentifier("tournamentFormatPicker")
                    NumberChoicePicker(title: "Matches expected or played", value: $tournament.matchesPlayed, range: 0...99, suffix: "matches")
                        .accessibilityIdentifier("tournamentMatchesPlayedPicker")
                    TextField("Goal", text: $tournament.goal, axis: .vertical)
                    TextField("Notes", text: $tournament.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("tournamentNotesField")
                }
            }
            .tennisThemedList()
            .navigationTitle("Tournament")
            .onChange(of: tournament.date) { _, date in
                if Calendar.current.startOfDay(for: tournament.endDate) < Calendar.current.startOfDay(for: date) { tournament.endDate = date }
            }
            .onChange(of: tournament.isAllDay) { _, isAllDay in
                if isAllDay {
                    tournament.hasStartTime = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if tournament.endDate < tournament.date {
                            tournament.endDate = tournament.date
                        }
                        store.upsertTournament(tournament)
                        dismiss()
                    }
                    .accessibilityIdentifier("saveTournamentButton")
                }
            }
        }
    }
}
