import Foundation
import UIKit

@MainActor
final class TennisStore: ObservableObject {
    @Published private(set) var data = AppData()
    @Published private(set) var storageError: String?
    @Published var lastAnnouncement = "Court Story ready."
    var announcementDelivery: (String) -> Void = { message in
        guard UIAccessibility.isVoiceOverRunning else { return }
        let speech = NSAttributedString(string: message, attributes: [.accessibilitySpeechQueueAnnouncement: true])
        UIAccessibility.post(notification: .announcement, argument: speech)
    }

    private let storeURL: URL

    init(storeURL: URL? = nil) {
        if let storeURL {
            self.storeURL = storeURL
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("TennisTracker", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.storeURL = directory.appendingPathComponent("tennis-tracker-data.json")
        }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-store") {
            try? FileManager.default.removeItem(at: self.storeURL)
        }
        #endif
        load()
        if storageError == nil { migrateIfNeeded() }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-match-list") {
            data = TennisMatchListUITestFixture.make()
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-tournament-outcome") {
            data = TennisTournamentUITestFixture.make()
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-tournament-summary") {
            data = TennisTournamentSummaryUITestFixture.make()
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-manual-duration") ||
           ProcessInfo.processInfo.arguments.contains("-ui-testing-legacy-duration") {
            data = TennisRegressionFixtures.manualDurationCorrection(
                alreadyCorrected: ProcessInfo.processInfo.arguments.contains("-ui-testing-legacy-duration"))
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-venue-dashboard") {
            data = TennisRegressionFixtures.venueAndDashboard()
            data.onboardingCompleted = true
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-match-update") {
                for name in ["Chris", "Sam", "Jo"] {
                    var person = PlayerProfile(); person.name = name; data.players.append(person)
                }
                data.trainingSessions[0].focus = ""
                var focused = data.trainingSessions[0]; focused.id = UUID()
                focused.date = focused.date.addingTimeInterval(-600)
                focused.focus = "Serve and return"; focused.practiceResult = nil
                data.trainingSessions.append(focused)
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-theme-classic") { data.settings.theme = .classic }
            if ProcessInfo.processInfo.arguments.contains("-ui-theme-contrast") { data.settings.theme = .highContrast }
        }
        if !ProcessInfo.processInfo.arguments.contains("-test-notification-warm"),
           let route = TennisNotificationTestSupport.route(training: data.trainingSessions, matches: data.matches, tournaments: data.tournaments) {
            TennisNotificationInbox.enqueue(route.url)
        }
        #endif
    }

    var needsOnboarding: Bool {
        storageError == nil && !data.onboardingCompleted
    }

    var selectedPlayer: PlayerProfile? {
        guard let id = data.selectedPlayerID else { return data.players.first { !$0.isArchived } }
        return data.players.first { $0.id == id && !$0.isArchived }
    }

    var selectedPlayerID: UUID? {
        selectedPlayer?.id
    }

    var selectedMatches: [MatchRecord] {
        guard let id = selectedPlayerID else { return [] }
        return TennisMatchChronology.ordered(data.matches.filter { $0.playerID == id && $0.court.sport == selectedSport })
    }

    var selectedTraining: [TrainingSession] {
        guard let id = selectedPlayerID else { return [] }
        return data.trainingSessions.filter { $0.playerID == id && $0.court.sport == selectedSport }.sorted { $0.date > $1.date }
    }

    var selectedTournaments: [TournamentRecord] {
        guard let id = selectedPlayerID else { return [] }
        return data.tournaments.filter { $0.playerID == id && $0.court.sport == selectedSport }.sorted { $0.date > $1.date }
    }

    func selectPlayer(_ player: PlayerProfile) {
        guard !player.isArchived else { return }
        data.court.ownerPlayerID = player.id
        data.court.activeAthleteID = nil
        data.selectedPlayerID = player.id
        saveAndAnnounce("Selected \(player.displayName).")
    }

    func upsertPlayer(_ player: PlayerProfile) {
        guard !player.name.isBlank else { return }
        upsert(player, in: \.players)
        if data.selectedPlayerID == nil {
            data.selectedPlayerID = player.id
        }
        saveAndAnnounce("Saved player \(player.displayName).")
    }

    func deletePlayer(_ player: PlayerProfile) {
        _ = archiveCourtPlayer(player.id, archived: true)
    }

    func updateSetup(_ setup: TennisSetup) {
        data.setup = setup
        saveAndAnnounce("Saved Tennis Setup.")
    }

    func trainingSummary(_ session: TrainingSession, style: TennisSummaryStyle = .long, now: Date = Date()) -> String {
        TennisSummaryFormatter.training(session, style: style, now: now, coaches: data.setup.coaches, players: data.players)
    }

    @discardableResult
    func upsertMatch(_ match: MatchRecord, original: MatchRecord? = nil, audibleFeedback: Bool = true) -> Bool {
        guard !data.deletedRecordIDs.contains(match.id) else { return false }
        let wasCompleted = data.matches.first { $0.id == match.id }?.status == .completed
        let beforeAchievements = TennisAchievement.earnedIDs(records: data.achievementRecords, playerID: match.playerID)
        var latest = match
        if let original, let current = data.matches.first(where: { $0.id == match.id }) {
            let metadata = TennisMatchDetailEdits.roundAndSchedule(match, current: current, original: original)
            latest.matchPosition = metadata.matchPosition
            latest.date = metadata.date
            latest.hasStartTime = metadata.hasStartTime
        }
        latest.revision = max(latest.revision, data.matches.first(where: { $0.id == match.id })?.revision ?? 0)
        var saved = TennisRecordConflictResolver.prepareLocalMatch(latest)
        if saved.playerName.isBlank {
            saved.playerName = data.players.first { $0.id == saved.playerID }?.displayName ?? "Player"
        }
        if saved.allowedBounces == 0 {
            saved.allowedBounces = saved.sightLevel.allowedBounces
        }
        if saved.status == .completed {
            saved.liveScore = nil
        }
        var candidate = data
        if let index = candidate.matches.firstIndex(where: { $0.id == saved.id }) { candidate.matches[index] = saved }
        else { candidate.matches.append(saved) }
        let event = TennisAchievement.feedback(before: beforeAchievements, records: candidate.achievementRecords, playerID: match.playerID,
            settings: data.settings.sounds, otherwise: saved.status == .completed && !wasCompleted ? .completion : .save)
        return saveCourtCandidate(candidate, announcement: audibleFeedback ? "Saved match against \(match.opponentSummary.fallback("opponent not recorded"))." : "", feedback: audibleFeedback ? event : nil)
    }

    func deleteMatch(_ match: MatchRecord) {
        data.delete(TennisRecordDeletion(id: match.id, kind: .match))
        saveAndAnnounce("Deleted match.")
    }

    @discardableResult
    func upsertTraining(_ session: TrainingSession, newPlayers: [PlayerProfile] = [], newCoaches: [TennisCoach] = []) -> Bool {
        guard !data.deletedRecordIDs.contains(session.id) else { return false }
        var candidate = data
        let now = Date()
        let beforeAchievements = TennisAchievement.earnedIDs(records: data.achievementRecords, playerID: session.playerID)
        for player in newPlayers where !player.name.isBlank && !data.players.contains(where: { $0.id == player.id }) {
            candidate.players.append(player)
        }
        for coach in newCoaches where !coach.name.isBlank && !data.setup.coaches.contains(where: { $0.id == coach.id }) {
            candidate.setup.coaches.append(coach)
        }
        var latest = session
        let existing = data.trainingSessions.first { $0.id == session.id }
        if let existing { latest.retainManualDuration(from: existing) }
        // An older editor cannot erase the live workout completed on the Watch.
        if latest.workout == nil || existing?.workout?.workoutID != nil { latest.workout = existing?.workout ?? latest.workout }
        if latest.trackedOnWatch == nil { latest.trackedOnWatch = existing?.trackedOnWatch }
        if latest.actualStart == nil { latest.actualStart = existing?.actualStart }
        if latest.actualFinish == nil, let finished = existing?.actualFinish {
            latest.actualFinish = finished
            if latest.durationSource != .manual { latest.durationMinutes = existing?.durationMinutes ?? latest.durationMinutes }
        }
        latest.context.captureLegacyNames(coaches: candidate.setup.coaches, players: candidate.players)
        latest.revision = max(latest.revision, data.trainingSessions.first(where: { $0.id == session.id })?.revision ?? 0)
        let saved = TennisRecordConflictResolver.prepareLocalTraining(latest)
        if let index = candidate.trainingSessions.firstIndex(where: { $0.id == saved.id }) { candidate.trainingSessions[index] = saved }
        else { candidate.trainingSessions.append(saved) }
        let completed = saved.isRecordedTraining(at: now) && existing?.isRecordedTraining(at: now) != true
        let event = TennisAchievement.feedback(before: beforeAchievements, records: candidate.achievementRecords, playerID: session.playerID,
            settings: data.settings.sounds, otherwise: completed ? .completion : .save)
        return saveCourtCandidate(candidate, announcement: "Saved training at \(session.placeText).", feedback: event)
    }

    func deleteTraining(_ session: TrainingSession) {
        data.delete(TennisRecordDeletion(id: session.id, kind: .training))
        saveAndAnnounce("Deleted training session.")
    }

    func updateTrainingLinks(_ session: TrainingSession, original: Set<UUID>, selected: Set<UUID>) {
        guard data.trainingSessions.contains(where: { $0.id == session.id }), !data.deletedRecordIDs.contains(session.id) else { return }
        let changes = TennisTrainingLinks.changes(sessionID: session.id, playerID: session.playerID, matches: data.matches, original: original, selected: selected)
        for match in changes { upsert(TennisRecordConflictResolver.prepareLocalMatch(match), in: \.matches) }
        if !changes.isEmpty { saveAndAnnounce("Training session and linked matches saved.") }
    }

    @discardableResult
    func upsertTournament(_ tournament: TournamentRecord) -> Bool {
        guard !data.deletedRecordIDs.contains(tournament.id) else { return false }
        let beforeAchievements = TennisAchievement.earnedIDs(records: data.achievementRecords, playerID: tournament.playerID)
        var latest = tournament
        latest.revision = max(latest.revision, data.tournaments.first(where: { $0.id == tournament.id })?.revision ?? 0)
        let saved = TennisRecordConflictResolver.prepareLocalTournament(latest)
        var candidate = data
        if let index = candidate.tournaments.firstIndex(where: { $0.id == saved.id }) { candidate.tournaments[index] = saved }
        else { candidate.tournaments.append(saved) }
        let event = TennisAchievement.feedback(before: beforeAchievements, records: candidate.achievementRecords, playerID: tournament.playerID,
            settings: data.settings.sounds, otherwise: .save)
        return saveCourtCandidate(candidate, announcement: "Saved tournament \(tournament.name.fallback("unnamed tournament")).", feedback: event)
    }

    @discardableResult
    func toggleTournamentCompletion(_ id: UUID) -> Bool {
        guard storageError == nil, !data.deletedRecordIDs.contains(id),
              let index = data.tournaments.firstIndex(where: { $0.id == id }) else { return false }
        let updated = data.tournaments[index].togglingCompletion()
        var savedData = data
        savedData.tournaments[index] = updated
        do {
            try persist(savedData)
            data = savedData
            publishSavedData()
            announce(updated.completionAnnouncement)
            return true
        } catch {
            announce("Tournament status could not be saved. Please try again.")
            return false
        }
    }

    func linkedMatches(for tournament: TournamentRecord) -> [MatchRecord] {
        TennisMatchChronology.ordered(data.matches.filter {
            $0.playerID == tournament.playerID && $0.tournamentID == tournament.id && $0.court.sport == tournament.court.sport
        })
    }

    func deleteTournamentKeepingMatches(_ tournament: TournamentRecord) {
        data.delete(TennisRecordDeletion(id: tournament.id, kind: .tournament))
        saveAndAnnounce("Deleted tournament and kept linked matches.")
    }

    func deleteTournamentAndLinkedMatches(_ tournament: TournamentRecord) {
        data.delete(TennisRecordDeletion(id: tournament.id, kind: .tournament, includeLinkedMatches: true))
        saveAndAnnounce("Deleted tournament and linked matches.")
    }

    func deleteTournament(_ tournament: TournamentRecord) {
        deleteTournamentKeepingMatches(tournament)
    }

    func updateSettings(_ settings: AppSettings) {
        var saved = settings
        saved.announceScores = settings.scoreAnnouncementMode != .off
        data.settings = saved
        saveAndAnnounce("Saved settings.")
    }

    func completeMatchDetails(_ id: UUID) {
        guard let index = data.matches.firstIndex(where: { $0.id == id }) else { return }
        data.matches[index].needsDetails = false
        data.matches[index] = TennisRecordConflictResolver.prepareLocalMatch(data.matches[index])
        saveAndAnnounce("Marked match details complete.")
    }

    func completeTrainingDetails(_ id: UUID) {
        guard let index = data.trainingSessions.firstIndex(where: { $0.id == id }) else { return }
        data.trainingSessions[index].markDetailsComplete()
        data.trainingSessions[index] = TennisRecordConflictResolver.prepareLocalTraining(data.trainingSessions[index])
        saveAndAnnounce("Marked training details complete.")
    }

    func completeTournamentDetails(_ id: UUID) {
        guard let index = data.tournaments.firstIndex(where: { $0.id == id }) else { return }
        data.tournaments[index].needsDetails = false
        data.tournaments[index] = TennisRecordConflictResolver.prepareLocalTournament(data.tournaments[index])
        saveAndAnnounce("Marked tournament details complete.")
    }

    func applyWatchCommand(_ command: TennisWatchSyncCommand) {
        guard storageError == nil else { return }
        if case .deleteRecord = command {} else if let id = command.recordID, data.deletedRecordIDs.contains(id) { save(); return }
        switch command {
        case .court(let mutation):
            var candidate = data
            if mutation.apply(to: &candidate) { _ = saveCourtCandidate(candidate, announcement: "Coaching changes synced from Apple Watch.") }
        case .deleteRecord(let deletion):
            data.delete(deletion)
            saveAndAnnounce("Deleted activity from Apple Watch.")
        case .snapshotReceived:
            break
        case .requestSnapshot:
            save()
            announce("Apple Watch sync refreshed.")
        case .requestActivity(let id):
            IPhoneWatchSyncService.shared.sendSnapshot(data, including: id)
        case .upsertMatch(let match):
            mergeWatchMatch(match)
            saveAndAnnounce("Synced match from Apple Watch.")
        case .upsertTraining(let session):
            mergeWatchTraining(session)
            saveAndAnnounce("Synced training from Apple Watch.")
        case .upsertTournament(let tournament):
            mergeWatchTournament(tournament)
            saveAndAnnounce("Synced tournament from Apple Watch.")
        case .markMatchDetailsComplete(let id):
            completeMatchDetails(id)
        case .markTrainingDetailsComplete(let id):
            completeTrainingDetails(id)
        case .markTournamentDetailsComplete(let id):
            completeTournamentDetails(id)
        }
    }

    func makeDefaultMatch(tournamentID: UUID? = nil) -> MatchRecord? {
        guard let player = selectedPlayer else { return nil }
        var match = MatchRecord(playerID: player.id)
        match.court = CourtActivity(player: playerForSelectedSport(player), coachID: capturingCoachID)
        match.date = TennisScheduling.fiveMinuteDate(match.date)
        match.playerName = player.displayName
        match.matchFormat = player.defaultMatchFormat
        match.matchType = data.settings.defaultMatchType
        match.sightLevel = player.sightLevel
        match.allowedBounces = player.bounceAllowance ?? player.sightLevel.allowedBounces
        if let allowance = match.court.access?.allowedBounces(for: match.court.sport.sport) { match.allowedBounces = allowance }
        match.suddenDeathDeuce = player.playerMode == .blindTennis
        match.tournamentID = tournamentID
        if let tournamentID, let tournament = data.tournaments.first(where: { $0.id == tournamentID }) {
            match.date = tournament.date
            match.hasStartTime = tournament.hasStartTime && !tournament.isAllDay
            match.venueID = tournament.venueID
            match.venue = tournament.venue
            match.location = tournament.location
            // Tournament classification is not an override of this athlete's rules.
            match.matchPosition = tournament.format == .roundRobin ? .roundRobin : .notSpecified
        }
        match.courtSurface = player.preferredSurface.isBlank ? .notSpecified : CourtSurface(rawValue: player.preferredSurface) ?? .notSpecified
        return match
    }

    func resumableMatches() -> [MatchRecord] {
        selectedMatches.filter { $0.status == .inProgress && $0.liveScore != nil }
    }

    func makeDefaultTournament() -> TournamentRecord? {
        guard let player = selectedPlayer else { return nil }
        var tournament = TournamentRecord(playerID: player.id)
        tournament.court = CourtActivity(player: playerForSelectedSport(player), coachID: capturingCoachID)
        tournament.date = TennisScheduling.fiveMinuteDate(tournament.date)
        tournament.endDate = max(tournament.date, tournament.endDate)
        tournament.category = player.bCategory
        return tournament
    }

    func makeDefaultTraining() -> TrainingSession? {
        guard let player = selectedPlayer else { return nil }
        var training = TrainingSession(playerID: player.id)
        training.court = CourtActivity(player: playerForSelectedSport(player), coachID: capturingCoachID)
        training.date = TennisScheduling.fiveMinuteDate(training.date)
        return training
    }

    @discardableResult
    func completeOnboarding(player: PlayerProfile, settings: AppSettings, setup: TennisSetup = TennisSetup(), additionalPlayers: [PlayerProfile] = []) -> Bool {
        guard needsOnboarding, data.players.isEmpty, !player.name.isBlank else { return false }
        var completed = data
        completed.players = [player] + additionalPlayers
        completed.selectedPlayerID = player.id
        completed.court.ownerPlayerID = player.id
        completed.court.deviceOwnerPlayerID = player.id
        completed.settings = settings
        completed.setup = setup
        completed.onboardingCompleted = true
        do {
            try persist(completed)
            data = completed
            publishSavedData()
            announce("Setup complete. Welcome, \(player.displayName).")
            return true
        } catch {
            announce("Setup could not be saved. Your choices are still here. Please try again.")
            return false
        }
    }

    func retryLoading() {
        storageError = nil
        load()
        if storageError == nil { migrateIfNeeded() }
    }

    func backupData() throws -> Data {
        guard storageError == nil else { throw TennisBackupError.unreadableStore }
        return try JSONEncoder.tennisTracker.encode(data)
    }

    func restoreBackup(_ backup: AppData) throws {
        guard storageError == nil, !data.onboardingCompleted, data.players.isEmpty,
              data.matches.isEmpty, data.trainingSessions.isEmpty, data.tournaments.isEmpty else {
            throw TennisBackupError.destinationNotEmpty
        }
        try TennisBackup.validate(backup)
        var restored = backup
        // Preserve every record ID, but never reuse a Watch transport identity from another installation.
        restored.libraryID = UUID()
        restored.migrateCourtProfiles()
        restored.onboardingCompleted = true
        try persist(restored)
        data = restored
        publishSavedData()
        announce("Private backup restored. \(restored.matches.count) matches, \(restored.trainingSessions.count) training sessions and \(restored.tournaments.count) tournaments.")
    }

    func announce(_ message: String) {
        lastAnnouncement = message
        announcementDelivery(message)
    }

    private func upsert<T: Identifiable & Equatable>(_ item: T, in keyPath: WritableKeyPath<AppData, [T]>) where T.ID == UUID {
        if let index = data[keyPath: keyPath].firstIndex(where: { $0.id == item.id }) {
            data[keyPath: keyPath][index] = item
        } else {
            data[keyPath: keyPath].append(item)
        }
        data.removeDeletedRecords()
    }

    private func mergeWatchMatch(_ incoming: MatchRecord) {
        guard let index = data.matches.firstIndex(where: { $0.id == incoming.id }) else {
            data.matches.append(incoming)
            return
        }
        let existing = data.matches[index]
        if TennisRecordConflictResolver.shouldReplace(
            incomingRevision: incoming.revision,
            incomingModifiedAt: incoming.modifiedAt,
            existingRevision: existing.revision,
            existingModifiedAt: existing.modifiedAt
        ) {
            data.matches[index] = incoming
        }
    }

    private func mergeWatchTraining(_ incoming: TrainingSession) {
        var incoming = incoming
        if incoming.trackedOnWatch == nil { incoming.trackedOnWatch = data.trainingSessions.first { $0.id == incoming.id }?.trackedOnWatch }
        guard let index = data.trainingSessions.firstIndex(where: { $0.id == incoming.id }) else {
            data.trainingSessions.append(incoming)
            return
        }
        let existing = data.trainingSessions[index]
        data.trainingSessions[index] = TennisRecordConflictResolver.mergeTraining(incoming: incoming, existing: existing)
    }

    private func mergeWatchTournament(_ incoming: TournamentRecord) {
        guard let index = data.tournaments.firstIndex(where: { $0.id == incoming.id }) else {
            data.tournaments.append(incoming)
            return
        }
        let existing = data.tournaments[index]
        if TennisRecordConflictResolver.shouldReplace(
            incomingRevision: incoming.revision,
            incomingModifiedAt: incoming.modifiedAt,
            existingRevision: existing.revision,
            existingModifiedAt: existing.modifiedAt
        ) {
            data.tournaments[index] = incoming
        }
    }

    private func saveAndAnnounce(_ message: String, feedback: TennisFeedbackEvent? = nil) {
        guard save() else { announce("Changes could not be saved. Please try again."); return }
        if let feedback, UIApplication.shared.applicationState == .active {
            TennisSoundPlayer.shared.feedback(feedback, settings: data.settings.sounds)
        }
        announce(message)
    }

    private func load() {
        do {
            let savedData = try Data(contentsOf: storeURL)
            let decoded = try TennisBackup.decodeStoredLibrary(savedData)
            data = decoded
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            do { try persist(data) } catch { storageError = "Your tennis library could not be created. No records have been changed. Try again when storage is available." }
        } catch {
            storageError = "Your saved tennis library could not be read. It has not been replaced or erased. Unlock your iPhone and try again. Keep this installation if the problem continues."
        }
    }

    private func persist(_ value: AppData) throws {
        let encoded = try JSONEncoder.tennisTracker.encode(value)
        try encoded.write(to: storeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    @discardableResult
    private func save() -> Bool {
        guard storageError == nil else { return false }
        data.removeDeletedRecords()
        do {
            try persist(data)
        } catch { return false }
        publishSavedData()
        return true
    }

    private func publishSavedData() {
        let saved = data
        Task {
            await TennisNotificationService.shared.rescheduleAll(for: saved)
        }
        #if os(iOS)
        IPhoneWatchSyncService.shared.sendSnapshot(data)
        #endif
    }

    private func sightLevel(from category: String) -> SightLevel? {
        let normalized = category.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return nil }
        return SightLevel.allCases.first { $0.rawValue.uppercased().hasPrefix(normalized) }
    }

    private func migrateIfNeeded() {
        if data.dataVersion < 9 {
            // Add reusable places without changing historical record IDs or text.
            let places = data.matches.map { ($0.venue, $0.location) } + data.trainingSessions.map { ($0.venue, $0.location) }
            for (name, town) in places where !name.isBlank {
                if !data.setup.venues.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame && $0.town == town }) {
                    var venue = TennisVenue(); venue.name = name; venue.town = town
                    data.setup.venues.append(venue)
                }
            }
            data.dataVersion = 9
            save()
        }
        if data.dataVersion < 10 {
            for index in data.trainingSessions.indices {
                let context = data.trainingSessions[index].context
                guard context.coachIDs.isEmpty, !context.coachName.isBlank else { continue }
                let name = context.coachName.trimmingCharacters(in: .whitespacesAndNewlines)
                var coach = data.setup.coaches.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame } ?? TennisCoach()
                coach.name = name
                if !data.setup.coaches.contains(where: { $0.id == coach.id }) { data.setup.coaches.append(coach) }
                data.trainingSessions[index].context.coachIDs = [coach.id]
            }
            data.dataVersion = 10
            save()
        }
        if data.dataVersion < 11 {
            data.dataVersion = 11
            if !save() { storageError = "Your library update could not be saved. Your original records remain on this iPhone. Please try again." }
        }
        if data.dataVersion < 12 {
            var migrated = data
            migrated.migrateCourtProfiles()
            do {
                try persist(migrated)
                data = migrated
            } catch {
                storageError = "Your sport-profile update could not be saved. Your original records remain unchanged. Please try again."
            }
        }
    }
}

extension TennisStore {
    var workspaceOwner: PlayerProfile? {
        data.players.first { $0.id == data.court.ownerPlayerID } ?? selectedPlayer
    }
    var selectedSport: CourtSportSelection { workspaceOwner?.selectedSport ?? .tennis }
    var courtRole: CourtRole { workspaceOwner?.court.selected.role ?? .player }
    var capturingCoachID: UUID? {
        guard courtRole == .coach, let owner = workspaceOwner, selectedPlayerID != owner.id else { return nil }
        return owner.id
    }
    var roster: [PlayerProfile] {
        guard let owner = workspaceOwner else { return [] }
        return data.players.filter { $0.court.coachOwnerID == owner.id && !$0.isArchived && $0.court.sports.contains { $0.sport == selectedSport } }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func playerForSelectedSport(_ player: PlayerProfile) -> PlayerProfile {
        var copy = player
        if copy.court.sports.contains(where: { $0.sport == selectedSport }) { copy.court.selectedSportID = selectedSport.id }
        return copy
    }

    @discardableResult
    private func saveCourtCandidate(_ candidate: AppData, announcement: String, feedback: TennisFeedbackEvent? = nil) -> Bool {
        guard storageError == nil else { return false }
        if let message = CourtLibraryValidation.message(in: candidate) { announce(message); return false }
        do {
            try persist(candidate)
            data = candidate
            publishSavedData()
            if let feedback, UIApplication.shared.applicationState == .active { TennisSoundPlayer.shared.feedback(feedback, settings: data.settings.sounds) }
            if !announcement.isBlank { announce(announcement) }
            return true
        } catch {
            announce("Changes could not be saved. Your original records are unchanged and your draft is still available.")
            return false
        }
    }

    @discardableResult
    func saveCourtProfile(_ player: PlayerProfile) -> Bool {
        guard !player.name.isBlank else { announce("Enter a name."); return false }
        var candidate = data
        var saved = player
        saved.court.modifiedAt = Date()
        saved.court.revision = (data.players.first { $0.id == player.id }?.court.revision ?? 0) + 1
        if let index = candidate.players.firstIndex(where: { $0.id == player.id }) { candidate.players[index] = saved }
        else { candidate.players.append(saved) }
        return saveCourtCandidate(candidate, announcement: "Saved \(player.displayName).")
    }

    @discardableResult
    func selectCourtSport(_ sport: CourtSportSelection) -> Bool {
        guard var owner = workspaceOwner, owner.court.select(sport) else { return false }
        var candidate = data
        guard let index = candidate.players.firstIndex(where: { $0.id == owner.id }) else { return false }
        owner.court.revision += 1; owner.court.modifiedAt = Date()
        candidate.players[index] = owner
        candidate.court.activeAthleteID = nil
        candidate.selectedPlayerID = owner.id
        return saveCourtCandidate(candidate, announcement: "\(sport.name) selected. Your other sports and records are retained.")
    }

    @discardableResult
    func selectCourtRole(_ role: CourtRole) -> Bool {
        guard var owner = workspaceOwner else { return false }
        var preferences = owner.court.selected
        preferences.role = role
        guard owner.court.update(preferences) else { return false }
        var candidate = data
        guard let index = candidate.players.firstIndex(where: { $0.id == owner.id }) else { return false }
        owner.court.revision += 1; owner.court.modifiedAt = Date()
        candidate.players[index] = owner
        candidate.court.activeAthleteID = nil
        candidate.selectedPlayerID = owner.id
        return saveCourtCandidate(candidate, announcement: "\(role.rawValue) mode selected for \(selectedSport.name).")
    }

    @discardableResult
    func selectCourtAthlete(_ id: UUID?) -> Bool {
        guard let owner = workspaceOwner else { return false }
        if let id {
            guard courtRole == .coach, roster.contains(where: { $0.id == id }) else { return false }
        }
        var candidate = data
        candidate.court.activeAthleteID = id
        candidate.selectedPlayerID = id ?? owner.id
        return saveCourtCandidate(candidate, announcement: id.flatMap { athlete in roster.first { $0.id == athlete }?.displayName }
            .map { "Recording for \($0)." } ?? "Recording your own activity.")
    }

    @discardableResult
    func archiveCourtPlayer(_ id: UUID, archived: Bool) -> Bool {
        guard let index = data.players.firstIndex(where: { $0.id == id }) else { return false }
        if archived && (data.matches.contains { $0.playerID == id && $0.status == .inProgress } ||
            data.trainingSessions.contains { $0.playerID == id && $0.isActive } ||
            data.tournaments.contains { $0.playerID == id && $0.actualStart != nil && $0.actualFinish == nil }) {
            announce("Finish this player's active activity before archiving.")
            return false
        }
        var candidate = data
        candidate.players[index].court.archivedAt = archived ? Date() : nil
        candidate.players[index].court.modifiedAt = Date(); candidate.players[index].court.revision += 1
        if archived && candidate.court.activeAthleteID == id { candidate.court.activeAthleteID = nil; candidate.selectedPlayerID = candidate.court.ownerPlayerID }
        if archived && candidate.court.ownerPlayerID == id {
            candidate.court.ownerPlayerID = candidate.players.first { !$0.isArchived }?.id
            candidate.court.activeAthleteID = nil; candidate.selectedPlayerID = candidate.court.ownerPlayerID
        }
        return saveCourtCandidate(candidate, announcement: archived ? "Player archived. History and media are retained." : "Player restored to the roster.")
    }

    @discardableResult
    func saveObservation(_ record: CourtObservation) -> Bool {
        guard CourtFeature.observations.isAvailable(in: data.settings.trackingMode), !data.court.deletedIDs.contains(record.id) else { return false }
        var candidate = data
        var next = record
        next.modifiedAt = Date()
        next.revision = (data.court.observations.first { $0.id == record.id }?.revision ?? 0) + 1
        candidate.court.observations.removeAll { $0.id == next.id }
        candidate.court.observations.append(next)
        return saveCourtCandidate(candidate, announcement: "Observation saved for the selected athlete.")
    }

    @discardableResult
    func saveMeasuredDrill(_ record: CourtMeasuredDrill) -> Bool {
        guard CourtFeature.measuredDrills.isAvailable(in: data.settings.trackingMode), !data.court.deletedIDs.contains(record.id) else { return false }
        var candidate = data
        var next = record
        next.modifiedAt = Date(); next.revision = (data.court.drills.first { $0.id == record.id }?.revision ?? 0) + 1
        candidate.court.drills.removeAll { $0.id == next.id }; candidate.court.drills.append(next)
        return saveCourtCandidate(candidate, announcement: "Measured drill saved.")
    }

    @discardableResult
    func removeCoachingRecord(_ id: UUID) -> Bool {
        var candidate = data
        candidate.court.observations.removeAll { $0.id == id }
        candidate.court.drills.removeAll { $0.id == id }
        candidate.court.media.removeAll { $0.id == id }
        candidate.court.deletedIDs.insert(id)
        return saveCourtCandidate(candidate, announcement: "Coaching record deleted.")
    }
}
