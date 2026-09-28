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
        guard let id = data.selectedPlayerID else { return data.players.first }
        return data.players.first { $0.id == id } ?? data.players.first
    }

    var selectedPlayerID: UUID? {
        selectedPlayer?.id
    }

    var selectedMatches: [MatchRecord] {
        guard let id = selectedPlayerID else { return [] }
        return data.matches.filter { $0.playerID == id }.sorted { $0.date > $1.date }
    }

    var selectedTraining: [TrainingSession] {
        guard let id = selectedPlayerID else { return [] }
        return data.trainingSessions.filter { $0.playerID == id }.sorted { $0.date > $1.date }
    }

    var selectedTournaments: [TournamentRecord] {
        guard let id = selectedPlayerID else { return [] }
        return data.tournaments.filter { $0.playerID == id }.sorted { $0.date > $1.date }
    }

    func selectPlayer(_ player: PlayerProfile) {
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
        data.players.removeAll { $0.id == player.id }
        if data.selectedPlayerID == player.id { data.selectedPlayerID = data.players.first?.id }
        saveAndAnnounce("Deleted player \(player.displayName). Historical activity kept.")
    }

    func updateSetup(_ setup: TennisSetup) {
        data.setup = setup
        saveAndAnnounce("Saved Tennis Setup.")
    }

    func trainingSummary(_ session: TrainingSession, style: TennisSummaryStyle = .long, now: Date = Date()) -> String {
        TennisSummaryFormatter.training(session, style: style, now: now, coaches: data.setup.coaches, players: data.players)
    }

    func upsertMatch(_ match: MatchRecord, audibleFeedback: Bool = true) {
        guard !data.deletedRecordIDs.contains(match.id) else { return }
        let wasCompleted = data.matches.first { $0.id == match.id }?.status == .completed
        let beforeAchievements = TennisAchievement.earnedIDs(records: data.achievementRecords, playerID: match.playerID)
        var latest = match
        latest.revision = max(latest.revision, data.matches.first(where: { $0.id == match.id })?.revision ?? 0)
        var saved = TennisRecordConflictResolver.prepareLocalMatch(latest)
        if saved.playerName.isBlank {
            saved.playerName = selectedPlayer?.displayName ?? "Player"
        }
        if saved.allowedBounces == 0 {
            saved.allowedBounces = saved.sightLevel.allowedBounces
        }
        if saved.status == .completed {
            saved.liveScore = nil
        }
        upsert(saved, in: \.matches)
        let event = TennisAchievement.feedback(before: beforeAchievements, records: data.achievementRecords, playerID: match.playerID,
            settings: data.settings.sounds, otherwise: saved.status == .completed && !wasCompleted ? .completion : .save)
        saveAndAnnounce("Saved match against \(match.opponentSummary.fallback("opponent not recorded")).", feedback: audibleFeedback ? event : nil)
    }

    func deleteMatch(_ match: MatchRecord) {
        data.delete(TennisRecordDeletion(id: match.id, kind: .match))
        saveAndAnnounce("Deleted match.")
    }

    func upsertTraining(_ session: TrainingSession, newPlayers: [PlayerProfile] = [], newCoaches: [TennisCoach] = []) {
        guard !data.deletedRecordIDs.contains(session.id) else { return }
        let now = Date()
        let beforeAchievements = TennisAchievement.earnedIDs(records: data.achievementRecords, playerID: session.playerID)
        for player in newPlayers where !player.name.isBlank && !data.players.contains(where: { $0.id == player.id }) {
            data.players.append(player)
        }
        for coach in newCoaches where !coach.name.isBlank && !data.setup.coaches.contains(where: { $0.id == coach.id }) {
            data.setup.coaches.append(coach)
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
        latest.context.captureLegacyNames(coaches: data.setup.coaches, players: data.players)
        latest.revision = max(latest.revision, data.trainingSessions.first(where: { $0.id == session.id })?.revision ?? 0)
        let saved = TennisRecordConflictResolver.prepareLocalTraining(latest)
        upsert(saved, in: \.trainingSessions)
        let completed = saved.isRecordedTraining(at: now) && existing?.isRecordedTraining(at: now) != true
        let event = TennisAchievement.feedback(before: beforeAchievements, records: data.achievementRecords, playerID: session.playerID,
            settings: data.settings.sounds, otherwise: completed ? .completion : .save)
        saveAndAnnounce("Saved training at \(session.placeText).", feedback: event)
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

    func upsertTournament(_ tournament: TournamentRecord) {
        guard !data.deletedRecordIDs.contains(tournament.id) else { return }
        let beforeAchievements = TennisAchievement.earnedIDs(records: data.achievementRecords, playerID: tournament.playerID)
        var latest = tournament
        latest.revision = max(latest.revision, data.tournaments.first(where: { $0.id == tournament.id })?.revision ?? 0)
        let saved = TennisRecordConflictResolver.prepareLocalTournament(latest)
        upsert(saved, in: \.tournaments)
        let event = TennisAchievement.feedback(before: beforeAchievements, records: data.achievementRecords, playerID: tournament.playerID,
            settings: data.settings.sounds, otherwise: .save)
        saveAndAnnounce("Saved tournament \(tournament.name.fallback("unnamed tournament")).", feedback: event)
    }

    func toggleTournamentCompletion(_ id: UUID) {
        guard storageError == nil, !data.deletedRecordIDs.contains(id),
              let index = data.tournaments.firstIndex(where: { $0.id == id }) else { return }
        let updated = data.tournaments[index].togglingCompletion()
        var savedData = data
        savedData.tournaments[index] = updated
        do {
            try persist(savedData)
            data = savedData
            publishSavedData()
            announce(updated.completionAnnouncement)
        } catch {
            announce("Tournament status could not be saved. Please try again.")
        }
    }

    func linkedMatches(for tournament: TournamentRecord) -> [MatchRecord] {
        data.matches
            .filter { $0.playerID == tournament.playerID && $0.tournamentID == tournament.id }
            .sorted { $0.date > $1.date }
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
        match.date = TennisScheduling.fiveMinuteDate(match.date)
        match.playerName = player.displayName
        match.matchFormat = player.defaultMatchFormat
        match.matchType = data.settings.defaultMatchType
        match.sightLevel = player.sightLevel
        match.allowedBounces = player.bounceAllowance ?? player.sightLevel.allowedBounces
        match.suddenDeathDeuce = player.playerMode == .blindTennis
        match.tournamentID = tournamentID
        if let tournamentID, let tournament = data.tournaments.first(where: { $0.id == tournamentID }) {
            match.date = tournament.date
            match.hasStartTime = tournament.hasStartTime && !tournament.isAllDay
            match.venueID = tournament.venueID
            match.venue = tournament.venue
            match.location = tournament.location
            match.sightLevel = sightLevel(from: tournament.category) ?? player.sightLevel
            match.allowedBounces = match.sightLevel.allowedBounces
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
        tournament.date = TennisScheduling.fiveMinuteDate(tournament.date)
        tournament.endDate = max(tournament.date, tournament.endDate)
        tournament.category = player.bCategory
        return tournament
    }

    func makeDefaultTraining() -> TrainingSession? {
        guard let player = selectedPlayer else { return nil }
        var training = TrainingSession(playerID: player.id)
        training.date = TennisScheduling.fiveMinuteDate(training.date)
        return training
    }

    @discardableResult
    func completeOnboarding(player: PlayerProfile, settings: AppSettings, setup: TennisSetup = TennisSetup(), additionalPlayers: [PlayerProfile] = []) -> Bool {
        guard needsOnboarding, data.players.isEmpty, !player.name.isBlank else { return false }
        var completed = data
        completed.players = [player] + additionalPlayers
        completed.selectedPlayerID = player.id
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
        restored.dataVersion = 11
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
    }
}
