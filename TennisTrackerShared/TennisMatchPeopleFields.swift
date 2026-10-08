import SwiftUI

struct TennisMatchPeopleFields: View {
    let players: [PlayerProfile]
    @Binding var match: MatchRecord
    var showsKind = true
    var singlesTitle = "Opponent"
    var opponentFieldIdentifier = ""

    var body: some View {
        if showsKind {
            Picker("Singles or doubles", selection: $match.matchType) {
                ForEach(match.court.sport.sport == .padel ? [.doubles] : MatchKind.allCases) { Text($0.rawValue).tag($0) }
            }.accessibilityIdentifier("matchKindPicker")
                .onChange(of: match.matchType) { _, kind in
                    guard match.usesCourtScoring else { return }
                    match.court.rules = (match.court.rules ?? .standard(for: match.court.sport.sport))
                        .forMatchKind(sport: match.court.sport.sport, doubles: kind == .doubles)
                }
        }
        if match.matchType == .doubles {
            TennisPersonPicker(title: "Your doubles partner", players: choices(excluding: [match.opponentID, match.opponent2ID]),
                selection: $match.partnerID, name: $match.partnerName, regularPartnersFirst: true)
        }
        TennisPersonPicker(title: match.matchType == .doubles ? "First opponent" : singlesTitle,
            players: choices(excluding: match.matchType == .doubles ? [match.partnerID, match.opponent2ID] : []),
            selection: $match.opponentID, name: $match.opponentName, fieldIdentifier: opponentFieldIdentifier)
        if match.matchType == .doubles {
            TennisPersonPicker(title: "Opponent's doubles partner", players: choices(excluding: [match.partnerID, match.opponentID]),
                selection: $match.opponent2ID, name: $match.opponent2Name)
        }
    }

    private func choices(excluding ids: [UUID?]) -> [PlayerProfile] {
        players.filter { $0.id != match.playerID && !ids.contains($0.id) }
    }
}
