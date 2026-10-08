import SwiftUI

struct CourtLiveMatchView: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    let existingMatch: MatchRecord?
    @State private var match: MatchRecord?
    @State private var score: CourtScoreSession?
    @State private var started = false
    @State private var error = ""
    @AccessibilityFocusState private var errorFocused: Bool

    var body: some View {
        NavigationStack {
            TennisForm {
                if let match, score != nil {
                    Section {
                        CourtCaptureIdentity(athlete: store.data.players.first { $0.id == match.playerID }?.displayName ?? "Player unavailable", sport: match.court.sport, coached: match.court.enteredByCoachID != nil)
                        if started {
                            CourtScoreControls(score: scoreBinding) { saveProgress() }
                        } else {
                            if match.court.sport.sport != .custom {
                                TennisMatchPeopleFields(players: store.data.players, match: namedMatchBinding)
                            }
                            CourtScoreSetupFields(score: scoreBinding, showsSideNames: match.court.sport.sport == .custom, doubles: match.matchType == .doubles)
                            StoredVenuePicker(id: matchBinding(\.venueID), venue: matchBinding(\.venue), location: matchBinding(\.location))
                            TennisTrainingSessionPicker(sessions: store.selectedTraining, coaches: store.data.setup.coaches, selection: matchBinding(\.trainingSessionID))
                            TennisTournamentPicker(tournaments: store.selectedTournaments, tournamentID: matchBinding(\.tournamentID), customName: matchBinding(\.customTournamentName))
                            Button("Start live scoring") { start() }.accessibilityIdentifier("startCourtLiveScore")
                        }
                    }
                } else { Text("Select an active player before recording a match.") }
                if !error.isEmpty { Text(error).accessibilityFocused($errorFocused) }
            }
            .navigationTitle(started ? "Live score" : "Match setup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(started ? "Close" : "Cancel") { if !started || saveProgress() { dismiss() } }
                }
            }
            .onAppear {
                guard match == nil else { return }
                match = existingMatch ?? store.makeDefaultMatch()
                score = match?.makeCourtScore()
                started = existingMatch?.court.score != nil && existingMatch?.status != .scheduled
            }
        }
    }

    private var scoreBinding: Binding<CourtScoreSession> {
        Binding(get: { score! }, set: { score = $0; match?.court.rules = $0.rules })
    }
    private var namedMatchBinding: Binding<MatchRecord> {
        Binding(get: { match! }, set: { value in
            match = value
            guard var current = score else { return }
            let sides = value.courtScoreSides
            for side in current.sides.indices {
                current.sides[side].name = sides[side].name
                current.sides[side].members = sides[side].members
            }
            if let rules = value.court.rules, rules != current.rules {
                current = CourtScoreSession(sport: value.court.sport, rules: rules, sides: current.sides)
            }
            score = current
        })
    }
    private func matchBinding<T>(_ key: WritableKeyPath<MatchRecord, T>) -> Binding<T> {
        Binding(get: { match![keyPath: key] }, set: { match?[keyPath: key] = $0 })
    }
    private func start() {
        guard let score else { return }
        if let message = score.validationMessage { error = message; errorFocused = true; return }
        match?.actualStart = Date()
        match?.date = Date()
        match?.hasStartTime = true
        if saveProgress() { started = true }
    }
    @discardableResult
    private func saveProgress() -> Bool {
        guard var match, let score else { return false }
        match.status = score.frame.complete ? .completed : .inProgress
        match.actualFinish = score.frame.complete ? Date() : nil
        if match.court.sport.sport == .custom {
            match.playerName = score.sides.first?.name ?? match.playerName
            match.opponentName = score.sides.dropFirst().map(\.name).joined(separator: ", ")
        }
        match.applyCourtScore(score)
        guard store.upsertMatch(match, audibleFeedback: false) else { error = store.lastAnnouncement; errorFocused = true; return false }
        self.match = match
        error = ""
        if store.data.settings.scoreAnnouncementMode == .automatic || score.frame.complete { store.announce(score.summary) }
        return true
    }
}
