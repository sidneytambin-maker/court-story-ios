import SwiftUI
import UIKit

struct MatchesView: View {
    @EnvironmentObject private var store: TennisStore
    @State private var showingNewMatch = false
    @State private var showingLiveScorer = false
    @State private var liveMatchToResume: MatchRecord?
    @State private var matchToEdit: MatchRecord?
    @State private var matchToDelete: MatchRecord?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            TennisList {
                Section {
                    Button("Track Match Scoring") {
                        showingLiveScorer = true
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Opens a point by point scorer with player and opponent names.")

                    ForEach(store.resumableMatches()) { match in
                        Button("Resume Match Scoring, \(match.opponentSummary.fallback("match"))") {
                            liveMatchToResume = match
                            showingLiveScorer = true
                        }
                        .accessibilityHint("Continues this saved live score from where you left it.")
                    }
                    Button("Record Match") { showingNewMatch = true }
                        .accessibilityLabel("Record Match")
                        .accessibilityIdentifier("addMatchButton")
                }

                if store.selectedMatches.isEmpty {
                    Section {
                        EmptyStateView(title: "No matches recorded yet", message: "Use Record Match or Track Match Scoring.")
                    }
                } else {
                    let groups = TennisMatchListGroups(matches: store.selectedMatches)
                    ForEach(TennisMatchListGroup.allCases) { group in
                        let matches = groups[group]
                        if !matches.isEmpty {
                            MatchListSection(group: group, matches: matches, tournaments: store.selectedTournaments,
                                edit: { matchToEdit = $0 }, calendar: addToCalendar,
                                delete: { matchToDelete = $0; confirmDelete = true },
                                resume: { liveMatchToResume = $0; showingLiveScorer = true })
                        }
                    }
                }
            }
            .tennisThemedList()
            .navigationTitle("Matches")
            .sheet(isPresented: $showingNewMatch) {
                if let match = store.makeDefaultMatch() {
                    MatchEditorView(match: match)
                }
            }
            .sheet(item: $matchToEdit) { match in
                MatchEditorView(match: match)
            }
            .sheet(isPresented: $showingLiveScorer) {
                LiveMatchView(existingMatch: liveMatchToResume)
                    .onDisappear { liveMatchToResume = nil }
            }
            .confirmationDialog("Delete this match?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Match", role: .destructive) {
                    if let matchToDelete {
                        store.deleteMatch(matchToDelete)
                    }
                    matchToDelete = nil
                }
                Button("Cancel", role: .cancel) { matchToDelete = nil }
            }
        }
    }

    private func addToCalendar(_ match: MatchRecord) {
        Task {
            await store.addToCalendar(TennisCalendarMapper.event(for: match))
        }
    }

    private func scoreSummary(_ match: MatchRecord) -> String {
        TennisSummaryFormatter.matchSummary(match, tournaments: store.selectedTournaments).scoreText
    }
}

struct MatchDetailView: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    @State var match: MatchRecord
    @State private var showingEditor = false
    @State private var confirmDelete = false
    @State private var calendarMessage = ""

    var body: some View {
        TennisList {
            TennisSection("Summary") {
                SummaryRow(title: TennisSummaryFormatter.match(match, tournaments: store.selectedTournaments, style: .short), value: "\(match.matchType.rawValue). \(match.date.shortTennisDate).")
                SummaryRow(title: "Players", value: "\(match.playerTeam) against \(match.opponentSummary.fallback("opponent not recorded")).")
                SummaryRow(title: "Score", value: TennisSummaryFormatter.matchSummary(match).scoreText)
                SummaryRow(title: "Rules", value: "\(match.sightLevel.label). \(match.allowedBounces) bounces. Sudden-death deuce \(match.suddenDeathDeuce ? "on" : "off").")
                SummaryRow(title: "Place", value: [match.venue, match.location].filter { !$0.isBlank }.joined(separator: ", ").fallback("not recorded"))
                if !match.conditionsSummary.isBlank { SummaryRow(title: "Conditions", value: match.conditionsSummary) }
            }

            if store.data.settings.trackingMode == .power {
                TennisSection("Performance") {
                    SummaryRow(title: "Key stats", value: "\(match.aces) aces, \(match.doubleFaults) double faults, \(match.winners) winners, \(match.unforcedErrors) unforced errors.")
                    SummaryRow(title: "Strengths", value: match.matchStrengths.fallback("not recorded"))
                    SummaryRow(title: "Needs work", value: match.matchNeedsWork.fallback("not recorded"))
                    SummaryRow(title: "Next practice focus", value: match.nextPracticeFocus.fallback("not recorded"))
                }
            }

            TennisSection("Notes") {
                Text(match.notes.fallback(match.matchStory.fallback("No notes recorded.")))
            }

            Section {
                Button("Add to Apple Calendar") {
                    addToCalendar()
                }
                if !calendarMessage.isBlank {
                    Text(calendarMessage)
                }
            }

            Section {
                Button("Delete match", role: .destructive) { confirmDelete = true }
            }
        }
        .tennisThemedList()
        .navigationTitle("Match detail")
        .onChange(of: store.data.matches) { _, matches in
            if let updated = matches.first(where: { $0.id == match.id }) { match = updated }
            else { dismiss() }
        }
        .toolbar {
            Button("Edit") { showingEditor = true }
        }
        .sheet(isPresented: $showingEditor) {
            MatchEditorView(match: match)
        }
        .confirmationDialog("Delete this match?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Match", role: .destructive) {
                store.deleteMatch(match)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func addToCalendar() {
        Task {
            calendarMessage = await store.addToCalendar(TennisCalendarMapper.event(for: match))
        }
    }
}

struct MatchEditorView: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    @State var match: MatchRecord
    @State private var original: MatchRecord?
    @State private var validationMessage = ""
    @State private var courtScoreError = ""

    var body: some View {
        NavigationStack {
            TennisForm {
                if !validationMessage.isBlank { Text(validationMessage).accessibilityIdentifier("recordMatchValidation") }
                TennisSection("Players") {
                    CourtCaptureIdentity(athlete: store.data.players.first { $0.id == match.playerID }?.displayName ?? "Player unavailable", sport: match.court.sport, coached: match.court.enteredByCoachID != nil)
                    if match.court.sport.sport != .custom {
                        TennisMatchPeopleFields(players: store.data.players, match: $match, singlesTitle: "Opponent name", opponentFieldIdentifier: "matchOpponentNameField")
                    }
                }

                TennisSection("Match") {
                    if match.status != .inProgress, storedMatch?.status != .inProgress {
                        DatePicker("Date", selection: $match.date, displayedComponents: .date)
                            .accessibilityLabel("Match date")
                            .accessibilityValue(match.date.fullTennisDate)
                            .accessibilityIdentifier("matchDatePicker")
                        Toggle("Start time specified", isOn: $match.hasStartTime)
                            .accessibilityIdentifier("matchStartTimeSpecified")
                        if match.hasStartTime { FiveMinuteTimePicker(title: "Start time", date: $match.date) }
                    } else {
                        SummaryRow(title: "Match date and time", value: readOnlySchedule)
                            .accessibilityIdentifier("matchReadOnlySchedule")
                    }
                    OrderedChoicePicker(title: "Match round", selection: $match.matchPosition, values: MatchPosition.allCases) { $0.label }
                        .accessibilityIdentifier("matchRoundPicker")
                    if !match.usesCourtScoring {
                    OrderedChoicePicker(title: "Match format", selection: $match.matchFormat, values: MatchFormat.allCases) { $0.label }
                        .accessibilityIdentifier("matchFormatPicker")
                    }
                    else if match.court.sport.sport != .custom {
                        NavigationLink("Scoring rules") {
                            Form {
                                CourtRuleFields(sport: match.court.sport.sport,
                                    rules: Binding(get: { match.court.rules ?? match.makeCourtScore().rules }, set: { match.court.rules = $0 }),
                                    doubles: match.matchType == .doubles)
                            }.navigationTitle("Match rules")
                        }.accessibilityValue(match.court.rules?.formatSummary ?? "")
                    }
                }

                TennisSection("Result") {
                    Picker("Status", selection: $match.status) {
                        ForEach(MatchStatus.allCases) { status in Text(status.rawValue).tag(status) }
                    }
                    if match.status == .completed {
                        if match.usesCourtScoring { CourtRecordedScoreFields(match: $match, validationMessage: $courtScoreError) }
                        else { TennisRecordedScoreFields(match: $match) }
                    } else if match.status == .inProgress {
                        SummaryRow(title: "In-progress score", value: match.court.score?.summary ?? (match.liveScore == nil ? "No live score saved yet." : liveScoreSummary))
                    } else {
                        Text("No result needed for a scheduled match.")
                            .foregroundStyle(.secondary)
                    }
                }

                MatchEntryDetails(match: $match)
                if store.data.settings.trackingMode == .power {
                    TennisSection("Performance") {
                        NumberChoicePicker(title: "Aces", value: $match.aces, range: 0...99)
                            .accessibilityIdentifier("matchAces")
                        NumberChoicePicker(title: "Double faults", value: $match.doubleFaults, range: 0...99)
                        NumberChoicePicker(title: "Winners", value: $match.winners, range: 0...max(99, match.winners))
                        NumberChoicePicker(title: "Unforced errors", value: $match.unforcedErrors, range: 0...max(99, match.unforcedErrors))
                    }
                }
            }
            .tennisThemedList()
            .navigationTitle("Match")
            .onAppear { if original == nil { original = match } }
            .onChange(of: match.tournamentID) { _, _ in applyTournamentDefaults() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        keepDateInsideLinkedTournament()
                        if match.usesCourtScoring && match.status == .completed && !courtScoreError.isEmpty { store.announce(courtScoreError); return }
                        if match.status == .completed, !match.usesCourtScoring, let error = TennisRecordedScore.validationMessage(for: match) {
                            validationMessage = error; store.announce(error); return
                        }
                        match.needsDetails = match.opponentName.isBlank || match.opponentName == "Opponent"
                            || (match.matchType == .doubles && (match.partnerName.isBlank || match.opponent2Name.isBlank))
                            || (match.status == .completed && match.setScores.isBlank)
                        guard store.upsertMatch(match, original: original) else { validationMessage = store.lastAnnouncement; return }
                        dismiss()
                    }
                    .accessibilityIdentifier("saveMatchButton")
                }
            }
        }
    }

    private var storedMatch: MatchRecord? {
        store.data.matches.first { $0.id == match.id }
    }

    private var readOnlySchedule: String {
        let current = storedMatch ?? match
        return current.date.fullTennisDate + (current.hasStartTime ? " at \(current.date.shortTennisTime)" : "")
    }

    private var liveScoreSummary: String {
        guard let liveScore = match.liveScore else { return "No live score saved yet." }
        let sets = "sets \(liveScore.playerSets)-\(liveScore.opponentSets)"
        let games = "games \(liveScore.playerGames)-\(liveScore.opponentGames)"
        return "\(games), \(sets)."
    }

    private var linkedTournament: TournamentRecord? {
        guard let tournamentID = match.tournamentID else { return nil }
        return store.selectedTournaments.first { $0.id == tournamentID }
    }

    private func applyTournamentDefaults() {
        guard let tournament = linkedTournament else { return }
        match.date = tournament.date
        match.hasStartTime = tournament.hasStartTime && !tournament.isAllDay
        match.venueID = tournament.venueID
        match.venue = tournament.venue
        match.location = tournament.location
        if tournament.format == .roundRobin, match.matchPosition == .notSpecified {
            match.matchPosition = .roundRobin
        }
    }

    private func keepDateInsideLinkedTournament() {
        guard let tournament = linkedTournament else { return }
        let calendar = Calendar.current
        let matchDay = calendar.startOfDay(for: match.date)
        let startDay = calendar.startOfDay(for: tournament.date)
        let endDay = calendar.startOfDay(for: tournament.endDate)
        if matchDay < startDay {
            match.date = calendar.dateByKeepingTime(from: match.date, on: tournament.date)
        } else if matchDay > endDay {
            match.date = calendar.dateByKeepingTime(from: match.date, on: tournament.endDate)
        }
    }

    private func sightLevel(from category: String) -> SightLevel? {
        let normalized = category.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return nil }
        return SightLevel.allCases.first { $0.rawValue.uppercased().hasPrefix(normalized) }
    }

}

struct LiveMatchView: View {
    @EnvironmentObject private var store: TennisStore
    let existingMatch: MatchRecord?
    var body: some View {
        if existingMatch?.usesCourtScoring == true || existingMatch == nil {
            CourtLiveMatchView(existingMatch: existingMatch)
        } else { TennisLiveMatchView(existingMatch: existingMatch) }
    }
}

struct TennisLiveMatchView: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    let existingMatch: MatchRecord?

    @State private var match: MatchRecord?
    @State private var scorer = TennisScoringEngine()
    @State private var isScoring = false
    @State private var confirmDiscard = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            TennisList {
                if let match {
                    if isScoring {
                        scoringSections(match: match)
                    } else {
                        setupSections(match: match)
                    }
                } else {
                    EmptyStateView(title: "No player set up", message: "Create a player before live scoring.")
                }
            }
            .tennisThemedList()
            .navigationTitle(isScoring ? "Live score" : "Match setup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isScoring ? "Close" : "Cancel") {
                        if isScoring {
                            saveProgress(dismissAfterSave: true, quiet: true)
                        } else {
                            confirmDiscard = true
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !isScoring {
                        Button("Start") { startScoring() }
                            .accessibilityLabel("Begin Match Scoring")
                            .disabled(match == nil)
                            .accessibilityIdentifier("startConfiguredLiveScoringButton")
                    }
                }
            }
            .onAppear(perform: configure)
            .confirmationDialog("Discard this live match setup?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Setup", role: .destructive) { dismiss() }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Reset the recorded score?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset Score", role: .destructive) {
                    scorer.reset()
                    saveProgress(dismissAfterSave: false, quiet: true)
                    announce("Score reset.", force: true)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func setupSections(match: MatchRecord) -> some View {
        TennisSection("Format") {
            OrderedChoicePicker(title: "Match format", selection: binding(\.matchFormat), values: MatchFormat.allCases) { $0.label }
            Picker("Match type", selection: binding(\.matchType)) {
                ForEach(MatchKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
            }
            AccessibleDateTimeEditor(dateTitle: "Date", timeTitle: "Start time", date: binding(\.date), hasStartTime: binding(\.hasStartTime))
            OrderedChoicePicker(title: "Match round", selection: binding(\.matchPosition), values: MatchPosition.allCases) { $0.label }
                .accessibilityIdentifier("matchRoundPicker")
            Toggle("Expected duration known", isOn: binding(\.hasExpectedDuration))
            if match.hasExpectedDuration {
                DurationFields(minutes: binding(\.expectedDurationMinutes), minimumMinutes: 15)
            }
        }

        TennisSection("Players") {
            TextField("Player name", text: binding(\.playerName))
                .accessibilityIdentifier("livePlayerNameField")
            TennisMatchPeopleFields(players: store.data.players, match: Binding(get: { self.match ?? match }, set: { self.match = $0 }), showsKind: false, singlesTitle: "Opponent name", opponentFieldIdentifier: "liveOpponentNameField")
        }

        TennisSection("Place") {
            StoredVenuePicker(id: binding(\.venueID), venue: binding(\.venue), location: binding(\.location))
        }
        TennisSection("Conditions") {
            TennisMatchConditionsFields(match: Binding(get: { self.match ?? match }, set: { self.match = $0 }))
        }

        TennisSection("Rules") {
            OrderedChoicePicker(title: "Sight classification", selection: binding(\.sightLevel), values: SightLevel.allCases) { $0.label }
            .onChange(of: match.sightLevel) { _, newValue in
                self.match?.allowedBounces = newValue.allowedBounces
                self.match?.suddenDeathDeuce = newValue != .fullySighted
            }
            OrderedChoicePicker(title: "Allowed bounces", selection: binding(\.allowedBounces), values: [1, 2, 3]) { "\($0)" }
            Toggle("Sudden-death deuce", isOn: binding(\.suddenDeathDeuce))
                .accessibilityIdentifier("liveSuddenDeathToggle")
            Picker("Tie-break rule", selection: binding(\.tieBreakRule)) {
                ForEach(TieBreakRule.allCases) { rule in Text(rule.rawValue).tag(rule) }
            }
            if match.tieBreakRule == .manual {
                Picker("Tie-break target", selection: binding(\.tieBreakTarget)) {
                    ForEach([7, 10, 12, 21], id: \.self) { target in
                        Text("\(target)").tag(target)
                    }
                }
                .accessibilityValue("\(match.tieBreakTarget)")
                Toggle("Win tie-break by two", isOn: binding(\.tieBreakWinByTwo))
            }
        }

            Section {
                TennisTournamentPicker(tournaments: store.selectedTournaments, tournamentID: binding(\.tournamentID), customName: binding(\.customTournamentName))
                TennisTrainingSessionPicker(sessions: store.selectedTraining, coaches: store.data.setup.coaches, selection: binding(\.trainingSessionID))
        }

    }

    @ViewBuilder
    private func scoringSections(match: MatchRecord) -> some View {
        TennisSection("Score") {
            Text(scorer.fullScore)
                .font(.title2.bold())
                .accessibilityLabel("Current score")
                .accessibilityValue(scorer.fullScore)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityAction(named: "Hear full score") {
                    announce(scorer.fullScore, force: true)
                }
                .accessibilityAction(named: "Undo last point") {
                    announce(scorer.undo(), force: store.data.settings.scoreAnnouncementMode != .off)
                }
                .accessibilityAction(named: "Save Match Progress") {
                    saveProgress(dismissAfterSave: false)
                }
                .accessibilityAction(named: "Start tie-break") {
                    startTieBreak()
                }
                .accessibilityAction(named: "Finish Match") {
                    endMatch(winner: scorer.state.playerSets >= scorer.state.opponentSets ? .player : .opponent)
                }
        }

        TennisSection(match.matchType == .doubles ? "Team points" : "Points") {
            Button("Point to \(teamName(for: .player, match: match))") {
                score(.player)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("playerWinsPointButton")

            Button("Point to \(teamName(for: .opponent, match: match))") {
                score(.opponent)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("opponentWinsPointButton")
        }

        TennisSection("Tie-break") {
            Button("Start Tie-break") {
                startTieBreak()
            }
            .disabled(scorer.state.isTiebreak || scorer.state.isMatchComplete)

            if scorer.state.isTiebreak && match.tieBreakRule == .manual {
                Button("Finish tie-break for \(teamName(for: .player, match: match))") {
                    finishTieBreak(winner: .player)
                }
                Button("Finish tie-break for \(teamName(for: .opponent, match: match))") {
                    finishTieBreak(winner: .opponent)
                }
            }
        }

        TennisSection("Actions") {
            Button("Undo") {
                announce(scorer.undo(), force: store.data.settings.scoreAnnouncementMode != .off)
                saveProgress(dismissAfterSave: false, quiet: true)
            }
            .accessibilityIdentifier("undoScoreButton")
            Button("Save Match Progress") {
                saveProgress(dismissAfterSave: false)
            }
            .accessibilityIdentifier("saveLiveProgressButton")
            Button("Save Match Progress and Close") {
                saveProgress(dismissAfterSave: true)
            }
            Button("Hear full score") {
                announce(scorer.fullScore, force: true)
            }
            .accessibilityIdentifier("hearFullScoreButton")
            Button("Reset score", role: .destructive) {
                confirmReset = true
            }
            .accessibilityIdentifier("resetScoreButton")
            Button("Finish Match for \(teamName(for: .player, match: match))") {
                endMatch(winner: .player)
            }
            Button("Finish Match for \(teamName(for: .opponent, match: match))") {
                endMatch(winner: .opponent)
            }
        }
    }

    private func configure() {
        guard match == nil else { return }
        if let existingMatch {
            match = existingMatch
            scorer = TennisScoringEngine(
                playerName: existingMatch.playerTeam,
                opponentName: teamName(for: .opponent, match: existingMatch),
                suddenDeathDeuce: existingMatch.suddenDeathDeuce,
                tieBreakRule: existingMatch.tieBreakRule,
                tieBreakTarget: existingMatch.tieBreakTarget,
                tieBreakWinByTwo: existingMatch.tieBreakWinByTwo,
                setsNeededToWin: existingMatch.matchFormat.setsNeededToWin,
                snapshot: existingMatch.liveScore
            )
            isScoring = true
            return
        }
        match = store.makeDefaultMatch()
    }

    private func startScoring() {
        guard let match else { return }
        scorer = TennisScoringEngine(
            playerName: teamName(for: .player, match: match),
            opponentName: teamName(for: .opponent, match: match),
            suddenDeathDeuce: match.suddenDeathDeuce,
            tieBreakRule: match.tieBreakRule,
            tieBreakTarget: match.tieBreakTarget,
            tieBreakWinByTwo: match.tieBreakWinByTwo,
            setsNeededToWin: match.matchFormat.setsNeededToWin,
            snapshot: match.liveScore
        )
        isScoring = true
        saveProgress(dismissAfterSave: false, quiet: true)
    }

    private func score(_ winner: PointWinner) {
        let message = scorer.awardPoint(to: winner)
        if store.data.settings.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        saveProgress(dismissAfterSave: false, quiet: true)
        switch store.data.settings.scoreAnnouncementMode {
        case .automatic:
            announce(message, force: true)
        case .reduced:
            let name = winner == .player ? teamName(for: .player, match: match) : teamName(for: .opponent, match: match)
            announce("\(TennisSummaryFormatter.scoreAnnouncement(state: scorer.state, playerName: teamName(for: .player, match: match), opponentName: teamName(for: .opponent, match: match), suddenDeathDeuce: match?.suddenDeathDeuce ?? false)) Point to \(name).", force: true)
        case .off:
            store.announce(message)
        }
    }

    private func announce(_ message: String, force: Bool) {
        store.announce(message)
        if force {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private func startTieBreak() {
        announce(scorer.startTieBreak(), force: true)
        saveProgress(dismissAfterSave: false, quiet: true)
    }

    private func finishTieBreak(winner: PointWinner) {
        announce(scorer.finishTieBreak(winner: winner), force: true)
        saveProgress(dismissAfterSave: false, quiet: true)
    }

    private func endMatch(winner: PointWinner) {
        guard let match else { return }
        var finished = TennisWatchActivityFactory.finishMatch(match, score: scorer.state)
        finished.result = winner == .player ? .win : .loss
        store.upsertMatch(finished)
        announce(TennisSummaryFormatter.match(finished), force: true)
        dismiss()
    }

    private func saveProgress(dismissAfterSave: Bool, quiet: Bool = false) {
        guard var saved = match, store.selectedPlayerID != nil else { return }
        saved.liveScore = scorer.state.snapshot
        saved.status = scorer.state.isMatchComplete ? .completed : .inProgress
        saved.yourSetsWon = scorer.state.playerSets
        saved.opponentSetsWon = scorer.state.opponentSets
        saved.setScores = scorer.state.completedSetScores.joined(separator: ", ")
        saved.hadTiebreak = saved.setScores.contains("7-6") || saved.setScores.contains("6-7") || scorer.state.isTiebreak
        if scorer.state.isMatchComplete {
            saved.liveScore = nil
            saved.result = scorer.state.playerSets > scorer.state.opponentSets ? .win : .loss
        }
        match = saved
        store.upsertMatch(saved, audibleFeedback: !quiet || scorer.state.isMatchComplete)
        if !quiet {
            announce(scorer.state.isMatchComplete ? "Saved completed match." : "Saved match progress.", force: store.data.settings.scoreAnnouncementMode != .off)
        }
        if dismissAfterSave {
            dismiss()
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MatchRecord, Value>) -> Binding<Value> {
        Binding(
            get: { match![keyPath: keyPath] },
            set: { match![keyPath: keyPath] = $0 }
        )
    }

    private func teamName(for winner: PointWinner, match: MatchRecord?) -> String {
        guard let match else { return winner == .player ? "Player" : "Opponent" }
        if match.matchType == .doubles {
            switch winner {
            case .player:
                return [match.playerName, match.partnerName].filter { !$0.isBlank }.joined(separator: " and ").fallback("Your team")
            case .opponent:
                return [match.opponentName, match.opponent2Name].filter { !$0.isBlank }.joined(separator: " and ").fallback("Opponent team")
            }
        }
        return winner == .player ? match.playerName.fallback("Player") : match.opponentName.fallback("Opponent")
    }
}
