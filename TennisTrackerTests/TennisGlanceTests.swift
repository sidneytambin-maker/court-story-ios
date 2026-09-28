import XCTest
@testable import TennisTracker

final class TennisGlanceTests: XCTestCase {
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12))!

    func testNearestScheduledEventWinsAcrossActivityTypes() {
        let player = PlayerProfile()
        var snapshot = TennisWatchSnapshot()
        var training = TrainingSession(playerID: player.id)
        training.date = now.addingTimeInterval(7200); training.hasStartTime = true
        var match = MatchRecord(playerID: player.id)
        match.status = .scheduled; match.date = now.addingTimeInterval(3600); match.hasStartTime = true
        match.playerName = "Example Player"; match.opponentName = "Fictional Opponent"
        snapshot.trainingSessions = [training]; snapshot.matches = [match]
        let glance = TennisGlance.make(snapshot: snapshot, now: now)
        XCTAssertEqual(glance.title, "Next match")
        XCTAssertEqual(glance.destination, .today)
        XCTAssertTrue(glance.accessibilitySummary.contains("Example Player will play Fictional Opponent"))
    }

    func testAllDayTrainingTodayIsNotDiscardedAfterMidnight() {
        var training = TrainingSession(playerID: UUID())
        training.date = Calendar.current.startOfDay(for: now); training.hasStartTime = false
        var snapshot = TennisWatchSnapshot(); snapshot.trainingSessions = [training]
        XCTAssertEqual(TennisGlance.make(snapshot: snapshot, now: now).destination, .today)
        training.actualFinish = now
        snapshot.trainingSessions = [training]
        XCTAssertEqual(TennisGlance.make(snapshot: snapshot, now: now).destination, .track)
    }

    func testTournamentUsesFullRangeAndOnlySelectedPlayer() {
        let player = UUID()
        var tournament = TournamentRecord(playerID: player)
        tournament.name = "Regional Open"; tournament.date = now
        tournament.endDate = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        var snapshot = TennisWatchSnapshot(); snapshot.selectedPlayerID = player
        snapshot.tournaments = [tournament]
        let glance = TennisGlance.make(snapshot: snapshot, now: now)
        XCTAssertEqual(glance.detail, "7 to 8 September 2026")
        XCTAssertEqual(glance.circularDetail, "7/9-8/9")
        snapshot.selectedPlayerID = UUID()
        XCTAssertEqual(TennisGlance.make(snapshot: snapshot, now: now).destination, .track)
    }

    func testDoublesLeadHasCompleteVoiceOverNamesAndCompactVisualTeam() {
        var player = PlayerProfile(); player.name = "Example Player"
        var match = TennisWatchActivityFactory.match(player: player, kind: .doubles, startDate: now)
        match.partnerName = "Sample Partner"; match.opponentName = "Fictional Opponent"; match.opponent2Name = "Imaginary Rival"
        match.liveScore?.playerGames = 4; match.liveScore?.opponentGames = 3
        var snapshot = TennisWatchSnapshot(); snapshot.matches = [match]
        let glance = TennisGlance.make(snapshot: snapshot, now: now)
        XCTAssertEqual(glance.title, "Exa/Sam")
        XCTAssertEqual(glance.detail, "4-3")
        for name in ["Example Player", "Sample Partner", "Fictional Opponent", "Imaginary Rival"] { XCTAssertTrue(glance.accessibilitySummary.contains(name)) }
        XCTAssertTrue(glance.accessibilitySummary.contains("lead 4 games to 3"))
        XCTAssertEqual(glance.destination.url.absoluteString, "tennistracker://watch/score")
    }

    func testSavedMatchDoesNotAnnounceAnOngoingLead() {
        var match = TennisWatchActivityFactory.match(player: PlayerProfile(), kind: .singles, startDate: now.addingTimeInterval(-7 * 3600))
        match.liveScore?.playerGames = 4
        var snapshot = TennisWatchSnapshot(); snapshot.matches = [match]
        let glance = TennisGlance.make(snapshot: snapshot, now: now)
        XCTAssertTrue(glance.isStale)
        XCTAssertEqual(glance.relevanceScore, 0)
        XCTAssertTrue(glance.accessibilitySummary.hasPrefix("Saved match:"))
        XCTAssertFalse(glance.accessibilitySummary.contains("leads"))
        XCTAssertFalse(glance.accessibilitySummary.contains("is playing"))
    }

    func testActiveMatchWithoutScoreDoesNotInventOne() {
        var match = TennisWatchActivityFactory.match(player: PlayerProfile(), kind: .singles, startDate: now)
        match.liveScore = nil
        var snapshot = TennisWatchSnapshot(); snapshot.matches = [match]
        let glance = TennisGlance.make(snapshot: snapshot, now: now)
        XCTAssertEqual(glance.destination, .score)
        XCTAssertEqual(glance.detail, "In progress")
        XCTAssertTrue(glance.accessibilitySummary.contains("score not recorded"))
    }

    func testTrainingUsesSharedCoachSummaryAndTimelineDate() {
        let coach = TennisCoach(name: "Chris")
        var training = TennisWatchActivityFactory.trainingSession(playerID: UUID(), startDate: now.addingTimeInterval(-120))
        training.context.coachIDs = [coach.id]
        var snapshot = TennisWatchSnapshot(); snapshot.trainingSessions = [training]; snapshot.setup.coaches = [coach]
        let glance = TennisGlance.make(snapshot: snapshot, now: now.addingTimeInterval(60))
        XCTAssertTrue(glance.accessibilitySummary.contains("Coaches: Chris"))
        XCTAssertTrue(glance.accessibilitySummary.contains("3 minutes elapsed"))
        XCTAssertEqual(glance.destination, .live)
        XCTAssertGreaterThan(glance.relevanceScore, 0)
    }
}
