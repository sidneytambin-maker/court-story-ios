import SwiftUI

struct MatchListSection: View {
    let group: TennisMatchListGroup
    let matches: [MatchRecord]
    let tournaments: [TournamentRecord]
    let edit: (MatchRecord) -> Void
    let calendar: (MatchRecord) -> Void
    let delete: (MatchRecord) -> Void
    let resume: (MatchRecord) -> Void

    var body: some View {
        TennisSection(group.title) {
            ForEach(matches) { match in
                NavigationLink { MatchDetailView(match: match) } label: {
                    MatchListRow(match: match, group: group, tournaments: tournaments)
                }
                .accessibilityLabel("Match")
                .accessibilityValue(TennisSummaryFormatter.match(match, tournaments: tournaments, style: .accessibility))
                .accessibilityIdentifier("matchList." + match.id.uuidString)
                .accessibilityAction(named: "Edit match") { edit(match) }
                .accessibilityAction(named: "Add to Calendar") { calendar(match) }
                .accessibilityAction(named: "Delete match") { delete(match) }
                .modifier(MatchResumeAction(match: match, resume: { resume(match) }))
            }
        }
    }
}

private struct MatchListRow: View {
    let match: MatchRecord
    let group: TennisMatchListGroup
    let tournaments: [TournamentRecord]

    private var tournament: String {
        match.tournamentID.flatMap { id in tournaments.first { $0.id == id }?.name } ?? match.customTournamentName ?? ""
    }

    var body: some View {
        let summary = TennisSummaryFormatter.matchSummary(match, tournaments: tournaments)
        VStack(alignment: .leading, spacing: 5) {
            Label(summary.headline, systemImage: group.symbol)
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(match.playerTeam + " vs " + match.opponentSummary.fallback("Opponent not recorded"))
                .font(.headline)
            if !tournament.isBlank { Text(tournament).font(.subheadline.weight(.medium)) }
            Text(summary.scheduleText)
                .font(.subheadline)
            if match.status != .scheduled {
                Text((match.status == .completed ? match.result.rawValue + ". " : "") + summary.scoreText)
                    .font(.body).monospacedDigit()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 3)
    }
}

private struct MatchResumeAction: ViewModifier {
    let match: MatchRecord
    let resume: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if match.status == .inProgress && match.liveScore != nil {
            content.accessibilityAction(named: "Resume Match Scoring") { resume() }
        } else {
            content
        }
    }
}
