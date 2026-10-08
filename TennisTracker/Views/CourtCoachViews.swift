import SwiftUI
import Charts

struct CourtWorkspaceSwitcher: View {
    @EnvironmentObject private var store: TennisStore
    var body: some View {
        if let owner = store.workspaceOwner {
            Picker("Sport", selection: Binding(get: { store.selectedSport.id }, set: { id in
                if let sport = owner.court.sports.first(where: { $0.id == id }) { _ = store.selectCourtSport(sport.sport) }
            })) { ForEach(owner.court.sports) { Text($0.sport.name).tag($0.id) } }
                .accessibilityIdentifier("workspaceSportPicker")
            Picker("Role", selection: Binding(get: { store.courtRole }, set: { _ = store.selectCourtRole($0) })) {
                ForEach(CourtRole.allCases) { Text($0.rawValue).tag($0) }
            }.accessibilityIdentifier("workspaceRolePicker")
            if store.courtRole == .coach {
                Picker("Recording for", selection: Binding(get: { store.data.court.activeAthleteID }, set: { _ = store.selectCourtAthlete($0) })) {
                    Text("My own activity, \(owner.displayName)").tag(Optional<UUID>.none)
                    ForEach(store.roster) { Text($0.displayName).tag(Optional($0.id)) }
                }.accessibilityIdentifier("recordingAthletePicker")
            }
        }
    }
}

struct CourtCaptureIdentity: View {
    let athlete: String
    let sport: CourtSportSelection
    var coached = false
    var body: some View {
        Label("\(athlete), \(sport.name)\(coached ? ", coached activity" : "")", systemImage: coached ? "person.2" : "person")
            .font(.subheadline.weight(.semibold))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("captureAthleteIdentity")
    }
}

struct CourtCoachDashboard: View {
    @EnvironmentObject private var store: TennisStore
    private var planned: [TrainingSession] {
        store.data.trainingSessions.filter { $0.court.enteredByCoachID == store.workspaceOwner?.id &&
            $0.court.sport == store.selectedSport && $0.actualFinish == nil }
            .sorted { $0.date < $1.date }
    }
    var body: some View {
        NavigationStack {
            TennisList {
                Section {
                    TennisDashboardHeader(name: store.workspaceOwner?.displayName ?? "Coach")
                    CourtWorkspaceSwitcher()
                }
                Section {
                    NavigationLink("Your players", destination: CourtRosterView())
                    NavigationLink("Record or plan activity", destination: CourtRecordHub())
                    NavigationLink("Your own progress") { DashboardView().onAppear { _ = store.selectCourtAthlete(nil) } }
                }
                if !planned.isEmpty {
                    Section("Planned and active sessions") {
                        ForEach(planned.prefix(10)) { session in
                            NavigationLink {
                                TrainingDetailView(session: session)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(store.data.players.first { $0.id == session.playerID }?.displayName ?? "Archived player").font(.headline)
                                    Text(store.trainingSummary(session)).font(.subheadline)
                                }.accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                let reviews = store.roster.filter { $0.court.sports.first { $0.sport == store.selectedSport }?.reviewDate.map { $0 <= Date() } == true }
                if !reviews.isEmpty {
                    Section("Reviews due") { ForEach(reviews) { player in
                        NavigationLink(player.displayName) { CourtAthleteDetail(athleteID: player.id) }
                    } }
                }
                let stories = store.data.court.observations.filter { $0.coachID == store.workspaceOwner?.id && $0.sport == store.selectedSport }
                    .sorted { $0.date > $1.date }
                if CourtFeature.observations.isAvailable(in: store.data.settings.trackingMode), !stories.isEmpty {
                    Section("Recent player stories") { ForEach(stories.prefix(5)) { story in
                        NavigationLink {
                            CourtObservationEditor(observation: story)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(store.data.players.first { $0.id == story.athleteID }?.displayName ?? "Archived player").font(.headline)
                                Text(story.happened).lineLimit(3)
                                Text(story.date, style: .date).font(.caption)
                            }.accessibilityElement(children: .combine)
                        }
                    } }
                }
            }.navigationTitle("Coach dashboard").tennisThemedList()
        }
    }
}

struct CourtRosterView: View {
    @EnvironmentObject private var store: TennisStore
    @State private var search = ""
    @State private var includeArchived = false
    @State private var editing: PlayerProfile?
    @State private var archiveTarget: PlayerProfile?
    private var players: [PlayerProfile] {
        store.data.players.filter { $0.court.coachOwnerID == store.workspaceOwner?.id &&
            (includeArchived || !$0.isArchived) && $0.court.sports.contains { $0.sport == store.selectedSport } &&
            (search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search)) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
    var body: some View {
        TennisList {
            Section {
                CourtWorkspaceSwitcher()
                Toggle("Include archived players", isOn: $includeArchived)
                Button("Add player", systemImage: "person.badge.plus") {
                    guard let owner = store.workspaceOwner else { return }
                    var player = PlayerProfile()
                    player.court = CourtProfile()
                    player.court.sports = [CourtSportPreferences(sport: store.selectedSport)]
                    player.court.selectedSportID = store.selectedSport.id
                    player.court.coachOwnerID = owner.id
                    editing = player
                }.accessibilityIdentifier("addCoachedPlayer")
            }
            if players.isEmpty { Text("No players match this sport and filter.") }
            ForEach(players) { player in
                NavigationLink { CourtAthleteDetail(athleteID: player.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.displayName).font(.headline)
                        Text(player.isArchived ? "Archived, history retained" : playerForSport(player).court.selected.primaryGoal.fallback("No goal recorded"))
                            .font(.subheadline)
                    }.accessibilityElement(children: .combine)
                }
                .accessibilityAction(named: "Edit player") { editing = player }
                .accessibilityAction(named: player.isArchived ? "Restore player" : "Archive player") { archiveTarget = player }
                .swipeActions { Button(player.isArchived ? "Restore" : "Archive") { archiveTarget = player } }
            }
        }
        .navigationTitle("Players").tennisThemedList().searchable(text: $search, prompt: "Find a player")
        .sheet(item: $editing) { CourtProfileEditor(player: $0) }
        .confirmationDialog("Change player status?", isPresented: Binding(get: { archiveTarget != nil }, set: { if !$0 { archiveTarget = nil } }), titleVisibility: .visible) {
            if let target = archiveTarget {
                Button(target.isArchived ? "Restore player" : "Archive, keeping history and media") {
                    _ = store.archiveCourtPlayer(target.id, archived: !target.isArchived); archiveTarget = nil
                }
            }
            Button("Cancel", role: .cancel) { archiveTarget = nil }
        }
    }
    private func playerForSport(_ player: PlayerProfile) -> PlayerProfile { store.playerForSelectedSport(player) }
}

struct CourtProfileEditor: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    @State var player: PlayerProfile
    @State private var addingSport = false
    @State private var sportToAdd = CourtSportSelection.tennis
    @State private var error = ""
    @AccessibilityFocusState private var errorFocused: Bool
    private var preference: Binding<CourtSportPreferences> {
        Binding(get: { player.court.selected }, set: { value in
            if let index = player.court.sports.firstIndex(where: { $0.id == value.id }) { player.court.sports[index] = value }
        })
    }
    var body: some View {
        NavigationStack {
            TennisForm {
                Section("Profile") {
                    TextField("Name", text: $player.name).textContentType(.name).accessibilityIdentifier("courtProfileName")
                    TextField("Preferred name", text: $player.preferredName)
                    Picker("Sport preferences", selection: $player.court.selectedSportID) {
                        ForEach(player.court.sports) { Text($0.sport.name).tag($0.id) }
                    }
                    Button("Add another sport", systemImage: "plus") { addingSport = true }
                    Picker("Role for this sport", selection: preference.role) { ForEach(CourtRole.allCases) { Text($0.rawValue).tag($0) } }
                    TextField("Primary goal", text: preference.primaryGoal, axis: .vertical)
                        .accessibilityHint("Appears in this player's progress for the selected sport.")
                    TextField("Development notes", text: preference.developmentNotes, axis: .vertical)
                    Toggle("Plan a review date", isOn: Binding(get: { preference.wrappedValue.reviewDate != nil }, set: { preference.wrappedValue.reviewDate = $0 ? Date() : nil }))
                    if preference.wrappedValue.reviewDate != nil {
                        DatePicker("Review date", selection: Binding(get: { preference.wrappedValue.reviewDate ?? Date() }, set: { preference.wrappedValue.reviewDate = $0 }), displayedComponents: .date)
                    }
                    NavigationLink("Access and playing preferences") {
                        Form { CourtAccessFields(sport: preference.wrappedValue.sport.sport, access: preference.access) }
                            .navigationTitle(player.displayName)
                    }.accessibilityValue(preference.wrappedValue.access.summary)
                    NavigationLink("Future match defaults") {
                        Form { CourtRuleFields(sport: preference.wrappedValue.sport.sport, rules: preference.rules) }
                            .navigationTitle("Match defaults")
                    }.accessibilityHint("Changes future matches only. Existing records retain their rules.")
                    if preference.wrappedValue.role == .coach {
                        NavigationLink("Coaching profile") { Form { CourtCoachCredentialsFields(credentials: $player.court.coaching) } }
                    }
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red).accessibilityFocused($errorFocused) }
            }
            .navigationTitle("\(player.court.coachOwnerID == nil ? "My" : "Player") profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.saveCourtProfile(player) { dismiss() }
                        else { error = store.lastAnnouncement; errorFocused = true }
                    }.accessibilityIdentifier("saveCourtProfile")
                }
            }
            .sheet(isPresented: $addingSport) {
                NavigationStack {
                    Form { CourtSportChoiceFields(selection: $sportToAdd) }
                        .navigationTitle("Add sport")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { addingSport = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") { if player.court.select(sportToAdd) { addingSport = false } }.disabled(!sportToAdd.isValid)
                            }
                        }
                }
            }
        }
    }
}

struct CourtAthleteDetail: View {
    @EnvironmentObject private var store: TennisStore
    let athleteID: UUID
    @State private var editing = false
    private var athlete: PlayerProfile? { store.data.players.first { $0.id == athleteID } }
    var body: some View {
        TennisList {
            if let athlete {
                Section {
                    CourtCaptureIdentity(athlete: athlete.displayName, sport: store.selectedSport, coached: true)
                    if athlete.isArchived { Text("Archived. History and media are retained. Restore the player in Players to record new activity.") }
                    else {
                        NavigationLink("Record or plan activity") { CourtRecordHub().onAppear { _ = store.selectCourtAthlete(athleteID) } }
                    }
                    Button("Edit player", systemImage: "pencil") { editing = true }
                }
                CourtAthleteProgressContent(athleteID: athleteID)
                CourtJournalContent(athleteID: athleteID)
            } else { Text("This player is unavailable. No activity will be recorded against another player.") }
        }
        .navigationTitle(athlete?.displayName ?? "Player unavailable").tennisThemedList()
        .sheet(isPresented: $editing) { if let athlete { CourtProfileEditor(player: athlete) } }
    }
}

struct CourtRecordHub: View {
    @EnvironmentObject private var store: TennisStore
    @State private var observation: CourtObservation?
    @State private var drill: CourtMeasuredDrill?
    var body: some View {
        TennisList {
            Section {
                CourtWorkspaceSwitcher()
                if let athlete = store.selectedPlayer {
                    CourtCaptureIdentity(athlete: athlete.displayName, sport: store.selectedSport, coached: store.capturingCoachID != nil)
                }
                NavigationLink("Matches and live scoring") { MatchesView() }
                NavigationLink("Training and session plans") { TrainingView() }
                NavigationLink("Tournaments") { TournamentsView() }
            }
            if CourtFeature.observations.isAvailable(in: store.data.settings.trackingMode), let athlete = store.selectedPlayer, let coach = store.capturingCoachID {
                Section {
                    if CourtFeature.observations.isAvailable(in: store.data.settings.trackingMode) {
                        Button("Record observation", systemImage: "text.bubble") {
                            observation = CourtObservation(athleteID: athlete.id, coachID: coach, sport: store.selectedSport)
                        }.accessibilityIdentifier("addCoachingObservation")
                    }
                    if CourtFeature.measuredDrills.isAvailable(in: store.data.settings.trackingMode) {
                        Button("Record measured drill", systemImage: "scope") {
                            drill = CourtMeasuredDrill(athleteID: athlete.id, coachID: coach, sport: store.selectedSport)
                        }.accessibilityIdentifier("addMeasuredDrill")
                    }
                }
            }
        }.navigationTitle("Record").tennisThemedList()
        .sheet(item: $observation) { CourtObservationEditor(observation: $0) }
        .sheet(item: $drill) { CourtDrillEditor(drill: $0) }
    }
}

struct CourtProgressView: View {
    @EnvironmentObject private var store: TennisStore
    var body: some View {
        TennisList {
            Section { CourtWorkspaceSwitcher() }
            if let id = store.selectedPlayerID { CourtAthleteProgressContent(athleteID: id) }
        }.navigationTitle("Progress").tennisThemedList()
    }
}

struct CourtAthleteProgressContent: View {
    @EnvironmentObject private var store: TennisStore
    let athleteID: UUID
    @State private var days = 30
    private var since: Date { Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast }
    private var matches: [MatchRecord] { store.data.matches.filter { $0.playerID == athleteID && $0.court.sport == store.selectedSport && $0.date >= since && $0.date <= Date() && $0.status == .completed } }
    private var training: [TrainingSession] { store.data.trainingSessions.filter { $0.playerID == athleteID && $0.court.sport == store.selectedSport && ($0.actualStart ?? $0.date) >= since && $0.isRecordedTraining(at: Date()) } }
    private var drills: [CourtMeasuredDrill] { store.data.court.drills.filter { $0.athleteID == athleteID && $0.sport == store.selectedSport && $0.date >= since && $0.date <= Date() && $0.validationMessage == nil }.sorted { $0.date < $1.date } }
    var body: some View {
        Section("Progress") {
            Picker("Period", selection: $days) { Text("Last 7 days").tag(7); Text("Last 30 days").tag(30); Text("Last 90 days").tag(90); Text("Last year").tag(365) }
            SummaryRow(title: "Completed matches", value: "\(matches.count)")
            SummaryRow(title: "Results", value: "\(matches.filter { $0.result == .win }.count) wins, \(matches.filter { $0.result == .loss }.count) losses, \(matches.filter { $0.result == .draw }.count) draws")
            SummaryRow(title: "Training", value: "\(training.count) sessions, " + TennisDurationFormatter.text(seconds: training.reduce(0) { $0 + TennisDurationFormatter.trainingSeconds($1) }))
            if let person = store.data.players.first(where: { $0.id == athleteID }),
               let sport = person.court.sports.first(where: { $0.sport == store.selectedSport }) {
                SummaryRow(title: "Goal", value: sport.primaryGoal.fallback("No goal recorded"))
                if !sport.developmentNotes.isBlank && store.data.settings.trackingMode != .basic { Text(sport.developmentNotes) }
                if let date = sport.reviewDate { Text("Review date, \(date.fullTennisDate)") }
            }
        }
        let focuses = Dictionary(grouping: training.flatMap { $0.specificFocusSelections }, by: { $0 }).map { (name: $0.key, count: $0.value.count) }.sorted { $0.name < $1.name }
        if !focuses.isEmpty {
            Section("Training focus") {
                Chart(focuses, id: \.name) { focus in
                    BarMark(x: .value("Sessions", focus.count), y: .value("Focus", focus.name)).foregroundStyle(.green)
                }.frame(height: max(120, CGFloat(focuses.count * 32))).accessibilityHidden(true)
                ForEach(focuses, id: \.name) { focus in
                    SummaryRow(title: focus.name, value: "\(focus.count) of \(training.count) completed sessions")
                }
            }
        }
        if CourtFeature.measuredDrills.isAvailable(in: store.data.settings.trackingMode), !drills.isEmpty {
            Section("Measured drills") {
                Text("\(drills.count) recorded measurements in this period. Different drills or conditions are not treated as one ability score.")
                ForEach(drills) { drill in
                    NavigationLink { CourtDrillEditor(drill: drill) } label: {
                        Text("\(drill.date.shortTennisDate), \(drill.summary)")
                    }
                }
                if let first = drills.first, let last = drills.last, first.id != last.id {
                    Text(first.isComparable(to: last) ? "Comparable setup and conditions: \(first.summary), then \(last.summary)." : "Comparability warning: setup, conditions or drill differ. Review the individual measurements.")
                }
            }
        }
    }
}
