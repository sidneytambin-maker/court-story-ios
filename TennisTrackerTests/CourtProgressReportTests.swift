import XCTest
@testable import TennisTracker

final class CourtProgressReportTests: XCTestCase {
    func testReportFiltersAthleteSportPeriodStatusAndPrivateDetails() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var person = PlayerProfile(); person.name = "Demo Athlete"
        person.court.sports[0].primaryGoal = "Private goal"
        person.court.sports[0].developmentNotes = "Private development"
        var data = AppData(); data.players = [person]
        var match = MatchRecord(playerID: person.id); match.date = now.addingTimeInterval(-100); match.status = .completed; match.result = .win; match.matchType = .doubles
        var future = match; future.id = UUID(); future.date = now.addingTimeInterval(500)
        var otherSport = match; otherSport.id = UUID(); otherSport.court.sport = CourtSportSelection(sport: .badminton)
        var otherPerson = match; otherPerson.id = UUID(); otherPerson.playerID = UUID()
        var scheduled = match; scheduled.id = UUID(); scheduled.status = .scheduled
        data.matches = [match, future, otherSport, otherPerson, scheduled]
        var training = TrainingSession(playerID: person.id)
        training.date = now.addingTimeInterval(-3600); training.actualStart = training.date; training.actualFinish = training.date.addingTimeInterval(60)
        training.durationMinutes = 1; training.focus = "Serve and return"
        data.trainingSessions = [training]
        var observation = CourtObservation(athleteID: person.id, coachID: UUID(), sport: .tennis)
        observation.date = now.addingTimeInterval(-200); observation.happened = "Private observation"
        data.court.observations = [observation]
        let report = try XCTUnwrap(CourtProgressReport.make(athleteID: person.id, sport: .tennis, data: data, from: now.addingTimeInterval(-86400), through: now))
        XCTAssertTrue(report.rows.contains { $0.title == "Doubles matches" && $0.value.hasPrefix("1 completed: 1 wins") })
        XCTAssertTrue(report.rows.contains { $0.title == "Training" && $0.value.hasPrefix("1 recorded sessions") })
        XCTAssertFalse(report.text.contains("Private goal"))
        XCTAssertFalse(report.text.contains("Private development"))
        XCTAssertFalse(report.text.contains("Private observation"))
        XCTAssertFalse(report.includesPrivateNotes)
        let privateReport = try XCTUnwrap(CourtProgressReport.make(athleteID: person.id, sport: .tennis, data: data, from: now.addingTimeInterval(-86400), through: now, includeGoal: true, includeDevelopmentNotes: true, includeObservations: true))
        XCTAssertTrue(privateReport.text.contains("Private goal"))
        XCTAssertTrue(privateReport.text.contains("Private development"))
        XCTAssertTrue(privateReport.text.contains("Private observation"))
        XCTAssertTrue(privateReport.includesPrivateNotes)
        XCTAssertNil(CourtProgressReport.make(athleteID: person.id, sport: .tennis, data: data, from: now.addingTimeInterval(1), through: now))
    }

    func testCSVProtectsUserTextAndPreservesQuotesAndLineBreaks() {
        let report = CourtProgressReport(athlete: "=1+1", sport: "Custom, game", from: Date(), through: Date(), rows: [.init(title: "Notes", value: "A \"quoted\" line\nand another")], includesPrivateNotes: true)
        XCTAssertTrue(report.csv.contains("\"'=1+1\""))
        XCTAssertTrue(report.csv.contains("\"Custom, game\""))
        XCTAssertTrue(report.csv.contains("\"A \"\"quoted\"\" line\nand another\""))
    }
}
