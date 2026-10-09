import SwiftUI

struct WatchCourtWorkspaceView: View {
    @EnvironmentObject private var store: WatchTennisStore
    var body: some View {
        Form {
            if let owner = store.workspaceOwner {
                Picker("Sport", selection: Binding(get: { store.courtSport.id }, set: store.selectCourtSport)) {
                    ForEach(owner.court.sports) { Text($0.sport.name).tag($0.id) }
                }.accessibilityIdentifier("watchWorkspaceSport")
                Picker("Role", selection: Binding(get: { store.courtRole }, set: store.selectCourtRole)) {
                    ForEach(CourtRole.allCases) { Text($0.rawValue).tag($0) }
                }.accessibilityIdentifier("watchWorkspaceRole")
                if store.courtRole == .coach {
                    Picker("Recording for", selection: Binding(get: { store.snapshot.court.activeAthleteID }, set: store.selectCourtAthlete)) {
                        Text("My own activity, \(owner.displayName)").tag(Optional<UUID>.none)
                        ForEach(store.roster) { Text($0.displayName).tag(Optional($0.id)) }
                    }.accessibilityIdentifier("watchRecordingAthlete")
                    NavigationLink("Players") { WatchCourtRosterView() }
                }
                NavigationLink("My Profile") { WatchCourtProfileEditor(player: owner) }
                NavigationLink("Add Sport") { WatchCourtAddSportView(player: owner) }
            }
        }.navigationTitle("Sport and Player").pickerStyle(.navigationLink)
    }
}

enum WatchCourtRosterRoute: Hashable {
    case player(UUID)
    case edit(UUID)
    case journal(UUID)
}

struct WatchCourtRosterDestination: View {
    @EnvironmentObject private var store: WatchTennisStore
    let route: WatchCourtRosterRoute

    var body: some View {
        switch route {
        case .player(let id): WatchCourtPlayerView(playerID: id)
        case .edit(let id):
            if let player = store.snapshot.players.first(where: { $0.id == id }) {
                WatchCourtProfileEditor(player: player)
            } else { Text("This player is no longer available.") }
        case .journal(let id): WatchCourtJournalView(athleteID: id)
        }
    }
}

struct WatchCourtRosterView: View {
    @EnvironmentObject private var store: WatchTennisStore
    @State private var showArchived = false
    @State private var newPlayer: PlayerProfile?
    private var players: [PlayerProfile] {
        store.snapshot.players.filter {
            $0.court.coachOwnerID == store.workspaceOwner?.id && $0.isArchived == showArchived &&
                $0.court.sports.contains { $0.sport == store.courtSport }
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
    var body: some View {
        List {
            Button("Add Player", systemImage: "person.badge.plus") {
                guard let owner = store.workspaceOwner else { return }
                var player = PlayerProfile()
                var profile = CourtProfile()
                profile.coachOwnerID = owner.id
                profile.sports = [CourtSportPreferences(sport: store.courtSport)]
                profile.selectedSportID = store.courtSport.id
                player.court = profile
                newPlayer = player
            }
            Toggle("Show archived players", isOn: $showArchived)
            ForEach(players) { player in
                NavigationLink(player.displayName, value: WatchCourtRosterRoute.player(player.id))
            }
            if players.isEmpty { Text(showArchived ? "No archived players for this sport." : "No players added for this sport.") }
        }.navigationTitle("Players")
            .sheet(item: $newPlayer) { player in NavigationStack { WatchCourtProfileEditor(player: player, isNew: true) } }
    }
}

private struct WatchCourtPlayerView: View {
    @EnvironmentObject private var store: WatchTennisStore
    let playerID: UUID
    @State private var confirmArchive = false
    private var player: PlayerProfile? { store.snapshot.players.first { $0.id == playerID } }
    var body: some View {
        List {
            if let player {
                CourtCaptureIdentity(athlete: player.displayName, sport: store.courtSport, coached: true)
                if !player.isArchived {
                    Button("Record for This Player") { store.selectCourtAthlete(player.id); store.page = .track }
                }
                NavigationLink("Edit Player", value: WatchCourtRosterRoute.edit(player.id))
                if CourtFeature.observations.isAvailable(in: store.snapshot.settings.trackingMode) {
                    NavigationLink("Journal and Progress", value: WatchCourtRosterRoute.journal(player.id))
                }
                if let preference = player.court.sports.first(where: { $0.sport == store.courtSport }) {
                    if !preference.primaryGoal.isBlank { Text("Goal: " + preference.primaryGoal) }
                    if !preference.developmentNotes.isBlank { Text(preference.developmentNotes) }
                    if let date = preference.reviewDate { Text("Review: " + date.formatted(date: .abbreviated, time: .omitted)) }
                }
                let records = store.snapshot.achievementRecords.filter { ($0.courtSport ?? .tennis) == store.courtSport }
                let totals = TennisMatchResultTotals.build(records: records, playerID: player.id)
                Text("Singles: " + totals.singles.summary).accessibilityElement(children: .combine)
                Text("Doubles: " + totals.doubles.summary).accessibilityElement(children: .combine)
                let planned = store.snapshot.trainingSessions.filter {
                    $0.playerID == playerID && $0.court.sport == store.courtSport && $0.actualStart == nil && $0.actualFinish == nil
                        && $0.date >= Calendar.current.startOfDay(for: Date()) && !store.snapshot.deletedRecordIDs.contains($0.id)
                }.sorted { $0.date < $1.date }
                if !planned.isEmpty {
                    Section("Planned training") {
                        ForEach(planned) { WatchTrainingRow(training: $0, identifier: "watchPlannedTraining") }
                    }
                }
                Button(player.isArchived ? "Restore Player" : "Archive Player", role: player.isArchived ? nil : .destructive) { confirmArchive = true }
            } else { Text("This player is no longer available.") }
        }.navigationTitle(player?.displayName ?? "Player")
            .confirmationDialog(player?.isArchived == true ? "Restore this player?" : "Archive this player and keep their history?", isPresented: $confirmArchive, titleVisibility: .visible) {
                if var player {
                    Button(player.isArchived ? "Restore Player" : "Archive Player") {
                        player.court.archivedAt = player.isArchived ? nil : Date()
                        player.court.modifiedAt = Date(); player.court.revision += 1
                        _ = store.saveCourtMutation(.profile(player))
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}

struct WatchCourtProfileEditor: View {
    @EnvironmentObject private var store: WatchTennisStore
    @State var player: PlayerProfile
    var isNew = false
    @State private var original: PlayerProfile?
    @State private var error = ""
    @AccessibilityFocusState private var errorFocused: Bool
    private var selected: Binding<CourtSportPreferences> {
        let draft = $player
        return Binding(get: { draft.wrappedValue.court.selected }, set: { value in
            if let index = draft.wrappedValue.court.sports.firstIndex(where: { $0.id == value.id }) {
                draft.wrappedValue.court.sports[index] = value
            }
        })
    }
    var body: some View {
        Form {
            TextField("Player name", text: $player.name).accessibilityIdentifier("watchCourtPlayerName")
            TextField("Preferred name", text: $player.preferredName)
            Text(player.selectedSport.name)
            TextField("Primary goal", text: selected.primaryGoal)
            TextField("Development notes", text: selected.developmentNotes)
            Toggle("Plan a review date", isOn: Binding(get: { selected.wrappedValue.reviewDate != nil }, set: { selected.wrappedValue.reviewDate = $0 ? Date() : nil }))
            if selected.wrappedValue.reviewDate != nil {
                WatchDateField(title: "Review date", date: Binding(get: { selected.wrappedValue.reviewDate ?? Date() }, set: { selected.wrappedValue.reviewDate = $0 }))
            }
            NavigationLink("Access Preferences") { [sport = player.selectedSport.sport, access = selected.access] in
                Form { CourtAccessFields(sport: sport, access: access) }.navigationTitle("Access Preferences")
            }
            NavigationLink("Default Match Format") { [sport = player.selectedSport.sport, rules = selected.rules] in
                Form { CourtRuleFields(sport: sport, rules: rules) }.navigationTitle("Match Format")
            }
            if player.court.selected.role == .coach && player.court.coachOwnerID == nil {
                NavigationLink("Coaching Profile") { [credentials = $player.court.coaching] in
                    Form { CourtCoachCredentialsFields(credentials: credentials) }.navigationTitle("Coaching Profile")
                }
            }
            if !error.isEmpty { Text(error).accessibilityFocused($errorFocused) }
            WatchSaveAndDismissButton(title: "Save Player", save: save).disabled(player.name.isBlank)
                .accessibilityIdentifier("watchSaveCourtPlayer")
        }.navigationTitle(isNew ? "Add Player" : "Edit Player").pickerStyle(.navigationLink)
            .onAppear {
                if original == nil {
                    original = player
                    if player.court.sports.contains(where: { $0.sport == store.courtSport }) { player.court.selectedSportID = store.courtSport.id }
                }
            }
    }
    private func save() -> Bool {
        if !isNew, let current = store.snapshot.players.first(where: { $0.id == player.id }), current != original {
            error = "This profile changed while you were editing. Go back and reopen it before saving. Your changes have not overwritten it."
            errorFocused = true; return false
        }
        player.court.modifiedAt = Date(); player.court.revision += 1
        if store.saveCourtMutation(.profile(player)) { return true }
        error = "Player could not be saved. Check the sport, access preferences and iPhone connection status."; errorFocused = true
        return false
    }
}

private struct WatchCourtAddSportView: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    let player: PlayerProfile
    @State private var sport = CourtSportSelection.tennis
    var body: some View {
        Form {
            CourtSportChoiceFields(selection: $sport)
            Button("Add Sport") {
                guard var current = store.snapshot.players.first(where: { $0.id == player.id }), current.court.select(sport) else { return }
                current.court.modifiedAt = Date(); current.court.revision += 1
                if store.saveCourtMutation(.profile(current)) { store.selectCourtAthlete(nil); dismiss() }
            }.disabled(!sport.isValid || player.court.sports.contains { $0.id == sport.id })
        }.navigationTitle("Add Sport").pickerStyle(.navigationLink)
    }
}
