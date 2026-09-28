import XCTest
@testable import TennisTracker

@MainActor
final class TennisCalendarAnnouncementTests: XCTestCase {
    func testConfirmationNamesActivityDateAndVenueWithoutInventingMissingTime() {
        let playerID = UUID()
        var session = TrainingSession(playerID: playerID)
        session.venue = "Fictional Test Court"
        session.hasStartTime = false
        let draft = TennisCalendarMapper.event(for: session)
        let message = draft.confirmation(saved: true)
        XCTAssertTrue(message.contains("Your training session"))
        XCTAssertTrue(message.contains(session.date.fullTennisDate))
        XCTAssertTrue(message.contains("at Fictional Test Court"))
        XCTAssertFalse(message.contains(session.date.shortTennisTime))
        XCTAssertTrue(TennisCalendarMapper.event(for: MatchRecord(playerID: playerID)).confirmation(saved: true).contains("Your match"))
        XCTAssertTrue(TennisCalendarMapper.event(for: TournamentRecord(playerID: playerID)).confirmation(saved: true).contains("Your tournament"))
    }

    func testCalendarResultIsDeliveredForEveryActionIncludingIdenticalSuccessAndFailure() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let store = TennisStore(storeURL: url)
        var announcements: [String] = []
        store.announcementDelivery = { announcements.append($0) }
        let draft = TennisCalendarMapper.event(for: TrainingSession(playerID: UUID()))
        var saveCount = 0
        for _ in 0..<2 {
            await store.addToCalendar(draft) { received in
                XCTAssertEqual(received, draft)
                saveCount += 1
                return true
            }
        }
        await store.addToCalendar(draft) { _ in false }
        XCTAssertEqual(saveCount, 2)
        XCTAssertEqual(announcements.count, 3)
        XCTAssertEqual(announcements[0], announcements[1])
        XCTAssertTrue(announcements[2].hasPrefix("Not added"))
        XCTAssertFalse(announcements[2].contains("successfully"))
        XCTAssertEqual(store.lastAnnouncement, announcements[2])
    }

    func testUntimedActivitiesUseOneWholeCalendarDayAndTimedActivitiesKeepTheirDuration() {
        var session = TrainingSession(playerID: UUID())
        session.hasStartTime = false
        let untimed = TennisCalendarMapper.event(for: session)
        let midnight = Calendar.current.startOfDay(for: session.date)
        XCTAssertTrue(untimed.isAllDay)
        XCTAssertEqual(untimed.startDate, midnight)
        XCTAssertEqual(untimed.endDate, Calendar.current.date(byAdding: .day, value: 1, to: midnight))
        let match = TennisCalendarMapper.event(for: MatchRecord(playerID: session.playerID))
        XCTAssertTrue(match.isAllDay)
        XCTAssertEqual(match.endDate, Calendar.current.date(byAdding: .day, value: 1, to: match.startDate))
        session.hasStartTime = true
        session.durationMinutes = 65
        let timed = TennisCalendarMapper.event(for: session)
        XCTAssertFalse(timed.isAllDay)
        XCTAssertEqual(timed.startDate, session.date)
        XCTAssertEqual(timed.endDate.timeIntervalSince(timed.startDate), 3900)
        XCTAssertTrue(timed.confirmation(saved: true).contains(session.date.shortTennisTime))
    }
}
