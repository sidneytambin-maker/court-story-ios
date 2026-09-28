import XCTest
@testable import TennisTracker

final class TennisTournamentSummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func tournament() -> TournamentRecord {
        var tournament = TournamentRecord(playerID: UUID())
        tournament.modifiedAt = now
        tournament.name = "Example Open"
        tournament.date = now.addingTimeInterval(86400)
        tournament.endDate = now.addingTimeInterval(2 * 86400)
        return tournament
    }

    private func match(in tournament: TournamentRecord, status: MatchStatus, result: MatchResult = .win) -> MatchRecord {
        var match = MatchRecord(playerID: tournament.playerID)
        match.modifiedAt = now
        match.tournamentID = tournament.id; match.status = status; match.result = result
        match.date = tournament.date.addingTimeInterval(3600)
        return match
    }

    func testTwoScheduledLinkedMatchesAreAnnouncedAcrossAllSummaryStyles() {
        let tournament = tournament()
        let matches = [match(in: tournament, status: .scheduled), match(in: tournament, status: .scheduled)]
        for style in [TennisSummaryStyle.short, .long, .accessibility, .detailed] {
            let text = TennisSummaryFormatter.tournament(tournament, style: style, matches: matches)
            XCTAssertTrue(text.hasSuffix("2 scheduled matches."), text)
            for absent in ["No matches", "completed matches", " win", " loss", "0 scheduled", "0 matches"] {
                XCTAssertFalse(text.contains(absent), text)
            }
        }
    }

    func testMixedStatusesCountOnlyCompletedOutcomes() {
        let tournament = tournament()
        let matches = [match(in: tournament, status: .scheduled), match(in: tournament, status: .scheduled, result: .loss),
            match(in: tournament, status: .inProgress, result: .win), match(in: tournament, status: .completed, result: .win),
            match(in: tournament, status: .completed, result: .loss), match(in: tournament, status: .completed, result: .draw),
            match(in: tournament, status: .completed, result: .retired)]
        let text = TennisSummaryFormatter.tournament(tournament, matches: matches)
        XCTAssertTrue(text.hasSuffix("2 scheduled matches, 1 match in progress, 4 completed matches: 1 win and 1 loss and 1 draw and 1 retirement."), text)
        XCTAssertFalse(text.contains("3 wins"))
        XCTAssertFalse(text.contains("2 losses"))
    }

    func testNoLinkedMatchesAndUnrelatedRecordsDoNotInventResults() {
        let tournament = tournament()
        var unrelated = match(in: tournament, status: .completed); unrelated.tournamentID = UUID()
        var otherPlayer = match(in: tournament, status: .scheduled); otherPlayer.playerID = UUID()
        for records in [[MatchRecord](), [unrelated, otherPlayer]] {
            let text = TennisSummaryFormatter.tournament(tournament, linkedMatchCount: 99, matches: records)
            XCTAssertTrue(text.hasSuffix("No matches linked yet."), text)
            XCTAssertFalse(text.contains("99")); XCTAssertFalse(text.contains("win"))
        }
    }

    func testUnrelatedRecordsAreExcludedFromActualLinkedCounts() {
        let tournament = tournament()
        let linked = match(in: tournament, status: .scheduled)
        var unrelated = match(in: tournament, status: .scheduled); unrelated.tournamentID = UUID()
        let text = TennisSummaryFormatter.tournament(tournament, linkedMatchCount: 99, matches: [linked, unrelated])
        XCTAssertTrue(text.hasSuffix("1 scheduled match."), text)
        XCTAssertFalse(text.contains("99")); XCTAssertFalse(text.contains("2 scheduled"))
    }

    func testCountOnlyFallbackMeansLinkedNotCompletedAndHandlesSingular() {
        let tournament = tournament()
        for style in [TennisSummaryStyle.short, .long, .accessibility, .detailed] {
            XCTAssertTrue(TennisSummaryFormatter.tournament(tournament, linkedMatchCount: 1, style: style).hasSuffix("1 linked match."))
            let text = TennisSummaryFormatter.tournament(tournament, linkedMatchCount: 2, style: style)
            XCTAssertTrue(text.hasSuffix("2 linked matches."), text)
            XCTAssertFalse(text.contains("matches recorded")); XCTAssertFalse(text.contains("completed matches"))
        }
        XCTAssertTrue(TennisSummaryFormatter.tournament(tournament).hasSuffix("No matches linked yet."))
    }

    func testCompletedResultsAndIndependentTournamentOutcomeRemainVisible() {
        var tournament = tournament(); tournament.stageReached = .semiFinal; tournament.finishingPosition = 3
        let original = tournament
        let matches = [match(in: tournament, status: .completed, result: .win),
            match(in: tournament, status: .completed, result: .win), match(in: tournament, status: .completed, result: .loss)]
        let text = TennisSummaryFormatter.tournament(tournament, style: .detailed, matches: matches)
        XCTAssertTrue(text.hasSuffix("3 completed matches: 2 wins and 1 loss."), text)
        XCTAssertTrue(text.contains(tournament.outcomeSummary))
        XCTAssertFalse(text.contains("0 draws")); XCTAssertFalse(text.contains("0 scheduled"))
        XCTAssertEqual(tournament, original)
    }

    func testInProgressOnlyHasNoCompletedOrDefaultWinClaim() {
        let tournament = tournament()
        let text = TennisSummaryFormatter.tournament(tournament, matches: [match(in: tournament, status: .inProgress)])
        XCTAssertTrue(text.hasSuffix("1 match in progress."), text)
        XCTAssertFalse(text.contains("completed match")); XCTAssertFalse(text.contains("win"))
    }

    func testUpcomingWatchGlanceUsesActualScheduledLinks() {
        let tournament = tournament()
        var snapshot = TennisWatchSnapshot()
        snapshot.selectedPlayerID = tournament.playerID
        snapshot.tournaments = [tournament]
        snapshot.matches = [match(in: tournament, status: .scheduled), match(in: tournament, status: .scheduled)]
        let glance = TennisGlance.make(snapshot: snapshot, now: now)
        XCTAssertEqual(glance.title, tournament.name)
        XCTAssertTrue(glance.accessibilitySummary.contains("2 scheduled matches"))
        XCTAssertFalse(glance.accessibilitySummary.contains("No matches"))
    }

    func testTrainingLinksIncludeScheduledActiveAndCompletedMatches() {
        let tournament = tournament()
        let matches = MatchStatus.allCases.map { match(in: tournament, status: $0) }
        let sessionID = UUID()
        let changes = TennisTrainingLinks.changes(sessionID: sessionID, playerID: tournament.playerID,
            matches: matches, original: [], selected: Set(matches.map(\.id)))
        XCTAssertEqual(changes.count, 3)
        for original in matches {
            var expected = original; expected.trainingSessionID = sessionID
            XCTAssertEqual(changes.first { $0.id == original.id }, expected)
        }
    }

    func testWatchRetainsFullLinkedHistoryOnlyForIncludedTournaments() throws {
        let tournament = tournament()
        var omittedTournament = tournament; omittedTournament.id = UUID(); omittedTournament.finalResult = .completed
        omittedTournament.date = now.addingTimeInterval(-100 * 86400); omittedTournament.endDate = omittedTournament.date
        let linked = (0..<40).map { index -> MatchRecord in
            var record = match(in: tournament, status: .completed)
            record.date = now.addingTimeInterval(-Double(45 + index) * 86400)
            return record
        }
        var unrelated = match(in: omittedTournament, status: .completed); unrelated.date = omittedTournament.date
        var data = AppData(); data.tournaments = [tournament, omittedTournament]; data.matches = linked + [unrelated]
        let original = data
        let snapshot = try JSONDecoder.tennisTracker.decode(TennisWatchSnapshot.self,
            from: JSONEncoder.tennisTracker.encode(TennisWatchSnapshot(data: data, now: now)))
        XCTAssertEqual(snapshot.tournaments, [tournament])
        XCTAssertEqual(Set(snapshot.matches.map(\.id)), Set(linked.map(\.id)))
        XCTAssertEqual(snapshot.matches.count, linked.count)
        for record in linked { XCTAssertEqual(snapshot.matches.first { $0.id == record.id }, record) }
        XCTAssertTrue(TennisSummaryFormatter.tournament(tournament, matches: snapshot.matches).hasSuffix("40 completed matches: 40 wins."))
        XCTAssertEqual(data, original)
    }

    func testExplicitOldTournamentRequestIncludesItsLinkedMatches() {
        var tournament = tournament(); tournament.finalResult = .completed
        tournament.date = now.addingTimeInterval(-100 * 86400); tournament.endDate = tournament.date
        let linked = [match(in: tournament, status: .completed), match(in: tournament, status: .completed, result: .loss)]
        var unrelated = linked[0]; unrelated.id = UUID(); unrelated.tournamentID = nil
        var data = AppData(); data.tournaments = [tournament]; data.matches = linked + [unrelated]
        let ordinary = TennisWatchSnapshot(data: data, now: now)
        XCTAssertTrue(ordinary.tournaments.isEmpty); XCTAssertTrue(ordinary.matches.isEmpty)
        let requested = TennisWatchSnapshot(data: data, now: now, including: tournament.id)
        XCTAssertEqual(requested.requestedActivityID, tournament.id); XCTAssertEqual(requested.requestedActivityFound, true)
        XCTAssertEqual(requested.tournaments, [tournament]); XCTAssertEqual(requested.matches, linked)
        XCTAssertTrue(TennisSummaryFormatter.tournament(tournament, matches: requested.matches).hasSuffix("2 completed matches: 1 win and 1 loss."))
    }

    private func historicalLibrary() -> AppData {
        var tournament = tournament(); tournament.finalResult = .completed
        tournament.date = now.addingTimeInterval(-100 * 86400); tournament.endDate = tournament.date
        var player = PlayerProfile(); player.id = tournament.playerID; player.name = "Example Player"
        var data = AppData(); data.players = [player]; data.selectedPlayerID = player.id
        data.tournaments = [tournament]
        data.matches = [match(in: tournament, status: .completed), match(in: tournament, status: .completed, result: .loss)]
        return data
    }

    func testOpenHistoricalTournamentKeepsLinkedMatchesAfterOrdinarySnapshot() throws {
        let data = historicalLibrary(), tournament = data.tournaments[0]
        let requested = TennisWatchSnapshot(data: data, now: now, including: tournament.id)
        var ordinary = TennisWatchSnapshot(data: data, now: now.addingTimeInterval(1))
        XCTAssertTrue(ordinary.tournaments.isEmpty); XCTAssertTrue(ordinary.matches.isEmpty)
        ordinary.retainOpenActivities([tournament.id], from: requested)
        XCTAssertEqual(ordinary.tournaments, data.tournaments); XCTAssertEqual(ordinary.matches, data.matches)
        let restored = try JSONDecoder.tennisTracker.decode(TennisWatchSnapshot.self,
            from: JSONEncoder.tennisTracker.encode(ordinary))
        XCTAssertEqual(restored.matches, data.matches)
        XCTAssertTrue(TennisSummaryFormatter.tournament(tournament, matches: restored.matches).hasSuffix("2 completed matches: 1 win and 1 loss."))
        var repeated = TennisWatchSnapshot(data: data, now: now.addingTimeInterval(2))
        repeated.retainOpenActivities([tournament.id], from: ordinary)
        XCTAssertEqual(repeated.matches, data.matches)
    }

    func testOpenHistoricalTournamentRetentionHonoursBothTombstoneSetsAndOwnerPresence() {
        let data = historicalLibrary(), tournament = data.tournaments[0]
        let requested = TennisWatchSnapshot(data: data, now: now, including: tournament.id)
        for deleteLocally in [false, true] {
            var local = requested
            var ordinary = TennisWatchSnapshot(data: data, now: now.addingTimeInterval(1))
            if deleteLocally { local.deletedRecordIDs.insert(data.matches[0].id) }
            else { ordinary.deletedRecordIDs.insert(data.matches[0].id) }
            ordinary.retainOpenActivities([tournament.id], from: local)
            XCTAssertEqual(ordinary.matches, [data.matches[1]])
            XCTAssertEqual(ordinary.tournaments, [tournament])
        }
        for deletedID in [tournament.id, tournament.playerID] {
            for deleteLocally in [false, true] {
                var local = requested
                var ordinary = TennisWatchSnapshot(data: data, now: now.addingTimeInterval(1))
                if deleteLocally { local.deletedRecordIDs.insert(deletedID) }
                else { ordinary.deletedRecordIDs.insert(deletedID) }
                ordinary.retainOpenActivities([tournament.id], from: local)
                XCTAssertTrue(ordinary.tournaments.isEmpty); XCTAssertTrue(ordinary.matches.isEmpty)
            }
        }
        var removedPlayer = TennisWatchSnapshot(data: data, now: now.addingTimeInterval(1)); removedPlayer.players = []
        removedPlayer.retainOpenActivities([tournament.id], from: requested)
        XCTAssertTrue(removedPlayer.tournaments.isEmpty); XCTAssertTrue(removedPlayer.matches.isEmpty)
        var otherLibrary = TennisWatchSnapshot(data: data, now: now.addingTimeInterval(1)); otherLibrary.libraryID = UUID()
        otherLibrary.retainOpenActivities([tournament.id], from: requested)
        XCTAssertTrue(otherLibrary.tournaments.isEmpty); XCTAssertTrue(otherLibrary.matches.isEmpty)
    }

    func testOpenTournamentRetentionNeverReplacesNewerMatchOrFreshLinkedSet() {
        let data = historicalLibrary(), tournament = data.tournaments[0]
        let requested = TennisWatchSnapshot(data: data, now: now, including: tournament.id)
        var unlinked = data.matches[0]; unlinked.tournamentID = nil; unlinked.revision += 1
        unlinked.notes = "New phone edit"
        var ordinary = TennisWatchSnapshot(data: data, now: now.addingTimeInterval(1)); ordinary.matches = [unlinked]
        ordinary.retainOpenActivities([tournament.id], from: requested)
        XCTAssertEqual(ordinary.matches, [unlinked, data.matches[1]])
        var fresh = TennisWatchSnapshot(data: data, now: now.addingTimeInterval(1), including: tournament.id)
        fresh.matches = [data.matches[1]]
        fresh.retainOpenActivities([tournament.id], from: requested)
        XCTAssertEqual(fresh.matches, [data.matches[1]])
        var closed = TennisWatchSnapshot(data: data, now: now.addingTimeInterval(1))
        closed.retainOpenActivities([], from: requested)
        XCTAssertTrue(closed.tournaments.isEmpty); XCTAssertTrue(closed.matches.isEmpty)
    }
}
