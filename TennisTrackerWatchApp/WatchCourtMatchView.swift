import SwiftUI

struct WatchCourtMatchSetupView: View {
    @EnvironmentObject private var store: WatchTennisStore
    @Environment(\.dismiss) private var dismiss
    @State private var match: MatchRecord?
    @State private var score: CourtScoreSession?
    @State private var error = ""
    @AccessibilityFocusState private var errorFocused: Bool

    var body: some View {
        Form {
            if let match, score != nil {
                CourtCaptureIdentity(athlete: match.playerName, sport: match.court.sport, coached: match.court.enteredByCoachID != nil)
                if match.court.sport.sport != .custom {
                    TennisMatchPeopleFields(players: store.snapshot.players, match: peopleBinding)
                }
                CourtScoreSetupFields(score: scoreBinding, showsSideNames: match.court.sport.sport == .custom, doubles: match.matchType == .doubles)
                WatchVenueFields(venueID: field(\.venueID), venue: field(\.venue), location: field(\.location))
                TennisTournamentPicker(tournaments: store.scopedSnapshot.tournaments, tournamentID: field(\.tournamentID), customName: field(\.customTournamentName))
                TennisTrainingSessionPicker(sessions: store.scopedSnapshot.trainingSessions, coaches: store.snapshot.setup.coaches, selection: field(\.trainingSessionID))
                Button("Start live scoring") { start() }
                    .disabled(store.activeMatch != nil)
                    .accessibilityIdentifier("startCourtLiveScore")
            }
            if !error.isEmpty { Text(error).accessibilityFocused($errorFocused) }
        }
        .pickerStyle(.navigationLink)
        .navigationTitle("Live Score a Match")
        .onAppear {
            guard match == nil else { return }
            match = store.makeCourtMatch()
            score = match?.makeCourtScore()
        }
    }

    private func field<T>(_ key: WritableKeyPath<MatchRecord, T>) -> Binding<T> {
        Binding(get: { match![keyPath: key] }, set: { match?[keyPath: key] = $0 })
    }
    private var scoreBinding: Binding<CourtScoreSession> {
        Binding(get: { score! }, set: { score = $0; match?.court.rules = $0.rules })
    }
    private var peopleBinding: Binding<MatchRecord> {
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
    private func start() {
        guard var match, let score else { return }
        if let message = score.validationMessage { error = message; errorFocused = true; return }
        match.actualStart = Date(); match.actualFinish = nil
        match.date = Date(); match.hasStartTime = true; match.status = .inProgress
        if score.sport.sport == .custom {
            match.playerName = score.sides[0].name
            match.opponentName = score.sides.dropFirst().map(\.name).joined(separator: ", ")
        }
        match.applyCourtScore(score)
        if store.saveCourtMatch(match) { store.page = .score; dismiss() }
    }
}

struct WatchCourtScoreFields: View {
    @EnvironmentObject private var store: WatchTennisStore
    let match: MatchRecord
    @State private var confirmStop = false
    @State private var deleting = false

    var body: some View {
        CourtCaptureIdentity(athlete: match.playerName, sport: match.court.sport, coached: match.court.enteredByCoachID != nil)
        CourtScoreControls(score: Binding(get: { match.makeCourtScore() }, set: { value in
            var updated = match
            updated.applyCourtScore(value)
            updated.status = value.frame.complete ? .completed : .inProgress
            updated.actualFinish = value.frame.complete ? Date() : nil
            _ = store.saveCourtMatch(updated)
        }), changed: {})
        if match.court.score?.frame.complete == true {
            Button("Close match") { store.activeMatch = nil; store.page = .recent }
        } else {
            Button("End unfinished match") { confirmStop = true }
                .accessibilityHint("Keeps the actual score and records the match as retired, without inventing a winner.")
        }
        Button("Delete match", role: .destructive) { deleting = true }
            .sheet(isPresented: $deleting) {
                WatchDeleteSheet(isPresented: $deleting, deletion: TennisRecordDeletion(id: match.id, kind: .match))
            }
            .confirmationDialog("End this unfinished match?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("End match") {
                    var updated = match
                    updated.status = .completed; updated.result = .retired; updated.actualFinish = Date()
                    if store.saveCourtMatch(updated) { store.activeMatch = nil; store.page = .recent }
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}
