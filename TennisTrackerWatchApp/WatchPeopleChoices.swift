import SwiftUI

struct WatchPlayerChoices: View {
    let players: [PlayerProfile]
    @Binding var selectedIDs: [UUID]
    @Binding var otherSelected: Bool
    var allowsOther = true

    var body: some View {
        TennisChoiceList {
            ForEach(players) { player in
                TennisSelectionRow(name: player.displayName, id: player.id, selectedIDs: $selectedIDs)
            }
            if allowsOther { Toggle("Other", isOn: $otherSelected) }
        }.navigationTitle("Players Present")
    }
}
