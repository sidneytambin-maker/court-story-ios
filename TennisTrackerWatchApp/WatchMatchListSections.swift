import SwiftUI

struct WatchRecentMatchSections: View {
    let matches: [MatchRecord]

    var body: some View {
        let groups = TennisMatchListGroups(matches: matches)
        ForEach(TennisMatchListGroup.allCases) { group in
            let rows = group == .history ? groups.recentHistory(limit: 5) : groups[group]
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { WatchMatchRow(match: $0) }
                } header: {
                    Text(group.title).accessibilityAddTraits(.isHeader)
                }
            }
        }
    }

}

struct WatchMatchScoringChoices: View {
    @EnvironmentObject private var store: WatchTennisStore

    var body: some View {
        let groups = TennisMatchListGroups(matches: store.snapshot.matches)
        if groups[.inProgress].isEmpty && groups[.upcoming].isEmpty {
            Text("No unfinished matches")
        }
        ForEach([TennisMatchListGroup.inProgress, .upcoming]) { group in
            let matches = groups[group]
            if !matches.isEmpty {
                Section {
                    ForEach(matches) { match in
                        let summary = TennisSummaryFormatter.matchSummary(match, tournaments: store.snapshot.tournaments)
                        Button { store.beginMatch(match) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(summary.headline).font(.headline)
                                Text(match.playerTeam + " vs " + match.opponentSummary).font(.body)
                                Text(summary.scheduleText).font(.footnote)
                            }.fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Score \(match.playerTeam) against \(match.opponentSummary)")
                        .accessibilityValue(summary.headline + ". " + summary.scheduleText)
                    }
                } header: {
                    Text(group.title).accessibilityAddTraits(.isHeader)
                }
            }
        }
    }
}
