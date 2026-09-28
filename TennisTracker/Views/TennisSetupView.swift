import SwiftUI

struct TennisSetupView: View {
    var body: some View {
        TennisList {
            NavigationLink("Players") { PlayerView() }
            NavigationLink("Regular Doubles Partners") { PlayerView(partnersOnly: true) }
            NavigationLink("Coaches") { SetupRecordsView(kind: .coach) }
            NavigationLink("Training Venues") { SetupRecordsView(kind: .trainingVenue) }
            NavigationLink("Match Venues") { SetupRecordsView(kind: .matchVenue) }
            NavigationLink("Regular Tournaments") { SetupRecordsView(kind: .tournament) }
            NavigationLink("Regular Locations") { SetupRecordsView(kind: .location) }
        }
        .navigationTitle("Tennis Setup")
    }
}

private enum SetupKind: String {
    case coach = "Coach", trainingVenue = "Training Venue", matchVenue = "Match Venue"
    case tournament = "Regular Tournament", location = "Location"
    var isVenue: Bool { self == .trainingVenue || self == .matchVenue }
    var listTitle: String {
        switch self {
        case .coach: return "Coaches"
        case .trainingVenue: return "Training Venues"
        case .matchVenue: return "Match Venues"
        case .tournament: return "Regular Tournaments"
        case .location: return "Regular Locations"
        }
    }
}

private struct SetupDraft: Identifiable {
    var id = UUID()
    var name = ""
    var detail = ""
    var address = ""
    var notes = ""
    var venueID: UUID?
    var playerID: UUID?
    var format: TournamentFormat = .other
    var training = true
    var matches = true
}

private struct SetupRecordsView: View {
    @EnvironmentObject private var store: TennisStore
    let kind: SetupKind
    @State private var editing: SetupDraft?
    @State private var deleting: SetupDraft?
    @State private var confirmDelete = false

    private var records: [SetupDraft] {
        let setup = store.data.setup
        switch kind {
        case .coach:
            return setup.coaches.map { SetupDraft(id: $0.id, name: $0.name, detail: $0.organisation, notes: $0.notes, playerID: $0.playerID) }
        case .trainingVenue, .matchVenue:
            return setup.venues.filter { kind == .trainingVenue ? $0.usedForTraining : $0.usedForMatches }
                .map { SetupDraft(id: $0.id, name: $0.name, detail: $0.town, address: $0.address, notes: $0.notes, training: $0.usedForTraining, matches: $0.usedForMatches) }
        case .tournament:
            return setup.tournamentTemplates.map { SetupDraft(id: $0.id, name: $0.name, venueID: $0.venueID, format: $0.format) }
        case .location:
            return setup.locations.map { SetupDraft(id: $0.id, name: $0.name) }
        }
    }

    var body: some View {
        TennisList {
            ForEach(records) { item in
                Button(item.name) { editing = item }
                    .accessibilityAction(named: "Edit \(kind.rawValue)") { editing = item }
                    .accessibilityAction(named: "Delete \(kind.rawValue)") { deleting = item; confirmDelete = true }
            }
            Button("Add \(kind.rawValue)") { editing = SetupDraft() }
        }
        .navigationTitle(kind.listTitle)
        .sheet(item: $editing) { draft in
            SetupRecordEditor(kind: kind, draft: draft, save: save)
        }
        .confirmationDialog("Delete \(deleting?.name ?? kind.rawValue)? Saved activity will be kept.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete \(kind.rawValue)", role: .destructive) {
                guard let deleting else { return }
                var setup = store.data.setup
                switch kind {
                case .coach: setup.coaches.removeAll { $0.id == deleting.id }
                case .trainingVenue, .matchVenue: setup.venues.removeAll { $0.id == deleting.id }
                case .tournament: setup.tournamentTemplates.removeAll { $0.id == deleting.id }
                case .location: setup.locations.removeAll { $0.id == deleting.id }
                }
                store.updateSetup(setup)
                self.deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        }
    }

    private func save(_ item: SetupDraft) {
        var setup = store.data.setup
        switch kind {
        case .coach:
            setup.coaches.removeAll { $0.id == item.id }
            setup.coaches.append(TennisCoach(id: item.id, name: item.name, organisation: item.detail, notes: item.notes, playerID: item.playerID))
        case .trainingVenue, .matchVenue:
            setup.venues.removeAll { $0.id == item.id }
            setup.venues.append(TennisVenue(id: item.id, name: item.name, town: item.detail, address: item.address, notes: item.notes, usedForTraining: item.training, usedForMatches: item.matches))
        case .tournament:
            setup.tournamentTemplates.removeAll { $0.id == item.id }
            setup.tournamentTemplates.append(TennisTournamentTemplate(id: item.id, name: item.name, venueID: item.venueID, format: item.format))
        case .location:
            setup.locations.removeAll { $0.id == item.id }
            setup.locations.append(TennisLocation(id: item.id, name: item.name))
        }
        store.updateSetup(setup)
    }
}

private struct SetupRecordEditor: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    let kind: SetupKind
    @State var draft: SetupDraft
    let save: (SetupDraft) -> Void

    var body: some View {
        NavigationStack {
            TennisForm {
                TextField("Name", text: $draft.name)
                if kind == .coach {
                    TextField("Club or organisation", text: $draft.detail)
                    Picker("Also a player", selection: $draft.playerID) {
                        Text("Not linked").tag(Optional<UUID>.none)
                        ForEach(store.data.players) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    .onChange(of: draft.playerID) { _, id in
                        if let player = store.data.players.first(where: { $0.id == id }), draft.name.isBlank { draft.name = player.name }
                    }
                }
                if kind.isVenue {
                    TextField("Town or city", text: $draft.detail)
                    TextField("Address", text: $draft.address, axis: .vertical)
                    Toggle("Training venue", isOn: $draft.training)
                    Toggle("Match venue", isOn: $draft.matches)
                }
                if kind == .tournament {
                    Picker("Usual venue", selection: $draft.venueID) {
                        Text("No venue").tag(Optional<UUID>.none)
                        ForEach(store.data.setup.venues) { Text($0.summary).tag(Optional($0.id)) }
                    }
                    Picker("Format", selection: $draft.format) {
                        ForEach(TournamentFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                if kind == .coach || kind.isVenue { TextField("Notes", text: $draft.notes, axis: .vertical) }
            }
            .navigationTitle(kind.rawValue)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(draft); dismiss() }
                        .disabled(draft.name.isBlank || (kind.isVenue && !draft.training && !draft.matches))
                }
            }
        }
    }
}

struct StoredVenuePicker: View {
    @EnvironmentObject private var store: TennisStore
    @Binding var id: UUID?
    @Binding var venue: String
    @Binding var location: String
    var training = false

    var body: some View {
        TennisVenuePicker(choices: TennisVenueChoice.build(setup: store.data.setup, matches: store.data.matches,
            training: store.data.trainingSessions, tournaments: store.data.tournaments),
            locations: store.data.setup.locations.map(\.name), venueID: $id, venue: $venue, location: $location)
    }
}
