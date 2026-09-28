import SwiftUI

struct TennisPersonPicker: View {
    let title: String
    let players: [PlayerProfile]
    @Binding var selection: UUID?
    @Binding var name: String
    var regularPartnersFirst = false
    var fieldIdentifier = ""

    private var sorted: [PlayerProfile] {
        players.sorted {
            if regularPartnersFirst && $0.isRegularPartner != $1.isRegularPartner { return $0.isRegularPartner }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Other").tag(Optional<UUID>.none)
            ForEach(sorted) { player in
                Text(player.displayName + (regularPartnersFirst && player.isRegularPartner ? ", regular partner" : ""))
                    .tag(Optional(player.id))
            }
        }
        .accessibilityIdentifier("activityPersonPicker." + title)
        .onChange(of: selection) { _, id in
            name = players.first(where: { $0.id == id })?.displayName ?? ""
        }
        if selection == nil {
            TextField(title, text: $name).accessibilityIdentifier(fieldIdentifier)
        }
    }
}
