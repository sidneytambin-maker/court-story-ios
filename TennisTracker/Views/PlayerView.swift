import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var store: TennisStore
    @State private var editingPlayer: PlayerProfile?
    @State private var deletingPlayer: PlayerProfile?
    @State private var confirmDelete = false
    var partnersOnly = false

    var body: some View {
        TennisList {
            Section {
                ForEach(store.data.players.filter { !partnersOnly || $0.isRegularPartner }) { player in
                    Button { editingPlayer = player } label: {
                        VStack(alignment: .leading) {
                            Text(player.displayName)
                            Text([player.sightLevel.label, player.club].filter { !$0.isBlank }.joined(separator: ", "))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityValue(player.isRegularPartner ? "Regular doubles partner" : "")
                    .accessibilityAction(named: "Edit Player") { editingPlayer = player }
                    .accessibilityAction(named: "Delete Player") { deletingPlayer = player; confirmDelete = true }
                }
                Button("Add Player") {
                    var player = PlayerProfile()
                    player.sightLevel = .notKnown
                    player.bCategory = "Not known"
                    player.isRegularPartner = partnersOnly
                    editingPlayer = player
                }
                .accessibilityIdentifier("addPlayerButton")
            }
            if !partnersOnly, let player = store.selectedPlayer {
                Section("Current player") {
                    Picker("Track activity for", selection: Binding(
                        get: { store.selectedPlayerID },
                        set: { id in if let value = store.data.players.first(where: { $0.id == id }) { store.selectPlayer(value) } }
                    )) {
                        ForEach(store.data.players) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    Button("Edit current player") { editingPlayer = player }
                        .accessibilityIdentifier("editCurrentPlayerButton")
                }
            }
        }
        .tennisThemedList()
        .navigationTitle(partnersOnly ? "Doubles Partners" : "Players")
        .sheet(item: $editingPlayer) { PlayerEditorView(player: $0) }
        .confirmationDialog("Delete player? Historical activity will be kept.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Player", role: .destructive) {
                if let deletingPlayer { store.deletePlayer(deletingPlayer) }
                deletingPlayer = nil
            }
            Button("Cancel", role: .cancel) { deletingPlayer = nil }
        }
    }
}

struct PlayerEditorView: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    @State var player: PlayerProfile
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            TennisForm {
                Section("Player") {
                    TextField("Full name", text: $player.name)
                        .accessibilityIdentifier("playerNameField")
                    OrderedChoicePicker(title: "Sight classification", selection: $player.sightLevel, values: SightLevel.allCases) { $0.label }
                    .accessibilityIdentifier("editSightLevelPicker")
                    .onChange(of: player.sightLevel) { _, level in
                        player.bCategory = level.label
                        player.playerMode = level == .fullySighted ? .standardTennis : .blindTennis
                    }
                    Picker("Handedness", selection: $player.playingHand) {
                        Text("Not known").tag("")
                        Text("Right-handed").tag("Right-handed")
                        Text("Left-handed").tag("Left-handed")
                        Text("Both hands").tag("Both hands")
                        if !["", "Right-handed", "Left-handed", "Both hands"].contains(player.playingHand) {
                            Text(player.playingHand).tag(player.playingHand)
                        }
                    }
                    .accessibilityLabel("Handedness")
                    .accessibilityValue(player.playingHand.fallback("Not known"))
                    .accessibilityIdentifier("playerHandednessPicker")
                    Picker("Usual bounce allowance", selection: $player.bounceAllowance) {
                        Text(player.sightLevel == .notKnown ? "Not known" : "Classification default: \(player.sightLevel.allowedBounces)")
                            .tag(Optional<Int>.none)
                        ForEach(1...3, id: \.self) { Text("\($0)").tag(Optional($0)) }
                    }
                    Toggle("Regular doubles partner", isOn: $player.isRegularPartner)
                    TextField("Club or team", text: $player.club)
                    TextField("Notes", text: $player.profileNotes, axis: .vertical)
                }
                Section("Player defaults") {
                    TextField("Personal tennis goal", text: $player.primaryGoal, axis: .vertical)
                        .accessibilityHint("Appears in What to work on on your dashboard.")
                    TextField("Coaching priority", text: $player.coachingFocus, axis: .vertical)
                        .accessibilityHint("An area to discuss or practise with your coach. Also available in dashboard Goals and Priorities.")
                    OrderedChoicePicker(title: "Default Match Format", selection: $player.defaultMatchFormat, values: MatchFormat.allCases) { $0.label }
                    .accessibilityIdentifier("playerDefaultFormatPicker")
                    Picker("Preferred match type", selection: $player.preferredMatchType) {
                        ForEach(MatchKind.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Picker("Tracking mode", selection: $player.trackingMode) {
                        ForEach(TrackingMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                if store.data.players.contains(where: { $0.id == player.id }) {
                    Section {
                        Button("Delete Player", role: .destructive) { confirmDelete = true }
                            .accessibilityIdentifier("deletePlayerButton")
                    }
                }
            }
            .tennisThemedList()
            .navigationTitle("Player Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("cancelPlayerButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.upsertPlayer(player); dismiss() }
                        .disabled(player.name.isBlank)
                        .accessibilityIdentifier("savePlayerButton")
                }
            }
            .confirmationDialog("Delete player? Historical activity will be kept.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Player", role: .destructive) { store.deletePlayer(player); dismiss() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
