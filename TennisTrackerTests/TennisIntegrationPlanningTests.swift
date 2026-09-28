import XCTest
@testable import TennisTracker

final class TennisIntegrationPlanningTests: XCTestCase {
    func testNotificationPlannerUsesRealUpcomingItems() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var data = AppData()
        var settings = AppSettings()
        settings.matchRemindersEnabled = true
        settings.trainingRemindersEnabled = true
        settings.tournamentRemindersEnabled = true
        settings.reminderLeadMinutes = 60
        data.settings = settings

        let player = PlayerProfile()
        let playerID = player.id
        var match = MatchRecord(playerID: playerID)
        match.date = now.addingTimeInterval(3_600)
        match.hasStartTime = true
        match.status = .scheduled
        match.playerName = "Sidney"
        match.opponentName = "Klaudia"
        data.matches = [match]

        var session = TrainingSession(playerID: playerID)
        session.date = now.addingTimeInterval(7_200)
        data.trainingSessions = [session]

        var tournament = TournamentRecord(playerID: playerID)
        tournament.name = "Regional Open"
        tournament.date = now.addingTimeInterval(10_800)
        tournament.endDate = tournament.date
        data.tournaments = [tournament]

        let planned = TennisNotificationPlanner.plannedRequests(data: data, now: now)

        XCTAssertEqual(planned.count, 3)
        XCTAssertEqual(planned.first?.title, "Upcoming match")
        XCTAssertTrue(planned.map(\.deepLink.absoluteString).contains { $0.contains("tennistracker://match/") })
    }

    func testCalendarMapperBuildsMatchEvent() {
        let playerID = UUID()
        var match = MatchRecord(playerID: playerID)
        match.opponentName = "Klaudia"
        match.playerName = "Alex"
        match.venue = "Indoor Centre"
        match.location = "London"
        match.expectedDurationMinutes = 75
        match.hasExpectedDuration = true
        match.hasStartTime = true
        match.date = Date(timeIntervalSince1970: 1_800_000_000)

        let event = TennisCalendarMapper.event(for: match)

        XCTAssertEqual(event.title, "Tennis: Alex versus Klaudia")
        XCTAssertEqual(event.location, "Indoor Centre, London")
        XCTAssertEqual(event.endDate.timeIntervalSince(event.startDate), 75 * 60)
        XCTAssertTrue(event.deepLink.absoluteString.contains("tennistracker://match/"))
    }
}
