import SwiftUI

struct MatchEntryDetails: View {
    @EnvironmentObject private var store: TennisStore
    @Binding var match: MatchRecord

    var body: some View {
        TennisOptionalSection("Match details", mode: store.data.settings.trackingMode, identifier: "matchEntryDetails") {
            StoredVenuePicker(id: $match.venueID, venue: $match.venue, location: $match.location)
            Toggle("Start time specified", isOn: $match.hasStartTime)
            if match.hasStartTime { FiveMinuteTimePicker(title: "Start time", date: $match.date) }
            TennisTrainingSessionPicker(sessions: store.selectedTraining, coaches: store.data.setup.coaches, selection: $match.trainingSessionID)
            TennisTournamentPicker(tournaments: store.selectedTournaments, tournamentID: $match.tournamentID, customName: $match.customTournamentName)
            if let tournament = store.selectedTournaments.first(where: { $0.id == match.tournamentID }) {
                SummaryRow(title: "Tournament date range", value: tournament.date.shortTennisDate + " to " + tournament.endDate.shortTennisDate)
            }
            TennisMatchConditionsFields(match: $match)
            DisclosureGroup("Additional match details") {
                MatchRulesFields(match: $match)
            }
            TextField("Next practice focus", text: $match.nextPracticeFocus, axis: .vertical)
                .accessibilityHint("Your latest completed match review appears in Training & goals on the dashboard.")
            TextField("Notes", text: $match.notes, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityIdentifier("matchNotesField")
        }
    }
}

private struct MatchRulesFields: View {
    @Binding var match: MatchRecord

    var body: some View {
        TextField("Player name", text: $match.playerName)
            .accessibilityIdentifier("matchPlayerNameField")
        Toggle("Expected duration known", isOn: $match.hasExpectedDuration)
        if match.hasExpectedDuration { DurationFields(minutes: $match.expectedDurationMinutes, minimumMinutes: 15) }
        OrderedChoicePicker(title: "Sight classification", selection: $match.sightLevel, values: SightLevel.allCases) { $0.label }
            .onChange(of: match.sightLevel) { _, value in
                match.allowedBounces = value.allowedBounces
                match.suddenDeathDeuce = value != .fullySighted
            }
        OrderedChoicePicker(title: "Allowed bounces", selection: $match.allowedBounces, values: [1, 2, 3]) { "\($0) bounces" }
        Toggle("Sudden-death deuce", isOn: $match.suddenDeathDeuce)
            .accessibilityIdentifier("matchSuddenDeathToggle")
        Picker("Tie-break rule", selection: $match.tieBreakRule) {
            ForEach(TieBreakRule.allCases) { Text($0.rawValue).tag($0) }
        }
        if match.tieBreakRule == .manual {
            OrderedChoicePicker(title: "Tie-break target", selection: $match.tieBreakTarget, values: [7, 10, 12, 21]) { "\($0) points" }
            Toggle("Win tie-break by two", isOn: $match.tieBreakWinByTwo)
        }
    }
}
