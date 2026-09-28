import XCTest
@testable import TennisTracker

final class TennisMatchListGroupsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testStatusPartitionsPastAndFutureRecordsWithoutChangingThem() {
        let records = MatchStatus.allCases.flatMap { status in
            [-86_400.0, 86_400.0].map { offset in make(status: status, offset: offset) }
        }
        let groups = TennisMatchListGroups(matches: records)
        for group in TennisMatchListGroup.allCases {
            XCTAssertEqual(groups[group].count, 2)
            XCTAssertTrue(groups[group].allSatisfy { $0.status == group.status })
            for match in groups[group] { XCTAssertEqual(match, records.first { $0.id == match.id }) }
        }
        let output = TennisMatchListGroup.allCases.flatMap { groups[$0] }
        XCTAssertEqual(Set(output.map(\.id)), Set(records.map(\.id)))
        XCTAssertEqual(output.count, records.count)
    }

    func testEveryStatusUsesDayThenKnownMinuteThenUnknownTimeAndStableID() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2))!
        for group in TennisMatchListGroup.allCases {
            func record(_ id: Int, dayOffset: Int = 0, hour: Int, minute: Int = 0, second: Int = 0, known: Bool = true) -> MatchRecord {
                var match = make(status: group.status, offset: 0)
                match.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!
                match.date = day.addingTimeInterval(TimeInterval(dayOffset * 86_400 + hour * 3600 + minute * 60 + second))
                match.hasStartTime = known
                return match
            }
            let earlier = record(1, hour: 12, minute: 5, second: 50)
            let sameMinute = record(3, hour: 12, minute: 5)
            let later = record(2, hour: 14)
            let unknownEarlyClock = record(8, hour: 0, known: false)
            let unknownLateClock = record(7, hour: 23, known: false)
            let previousDay = record(9, dayOffset: -1, hour: 23)
            let nextDay = record(6, dayOffset: 1, hour: 0, known: false)
            let input = [later, unknownEarlyClock, sameMinute, previousDay, unknownLateClock, nextDay, earlier]
            let expected = [previousDay, earlier, sameMinute, later, unknownLateClock, unknownEarlyClock, nextDay]
            XCTAssertEqual(TennisMatchListGroups(matches: input, calendar: calendar)[group], expected)
            XCTAssertEqual(TennisMatchListGroups(matches: Array(input.reversed()), calendar: calendar)[group], expected)
        }
    }

    @MainActor
    func testReloadLinkedMatchesAndWatchSnapshotKeepChronologicalOrderAndIDs() throws {
        var data = AppData()
        var player = PlayerProfile(); player.name = "Ordering Example"
        data.players = [player]; data.selectedPlayerID = player.id; data.onboardingCompleted = true
        let tournament = TournamentRecord(playerID: player.id)
        data.tournaments = [tournament]
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now)
        for status in MatchStatus.allCases {
            // Insert 14:00 first, then 12:05, for every status.
            for (hour, minute) in [(14, 0), (12, 5)] {
                var match = make(status: status, offset: 0)
                match.playerID = player.id; match.tournamentID = tournament.id
                match.hasStartTime = true
                match.date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
                data.matches.append(match)
            }
        }
        let expected = TennisMatchChronology.ordered(data.matches)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("match-order-fixture.json")
        try JSONEncoder.tennisTracker.encode(data).write(to: url)
        let store = TennisStore(storeURL: url)
        XCTAssertNil(store.storageError)
        XCTAssertEqual(store.selectedMatches.map(\.id), expected.map(\.id))
        XCTAssertEqual(store.linkedMatches(for: tournament).map(\.id), expected.map(\.id))
        let reloaded = TennisStore(storeURL: url)
        XCTAssertEqual(reloaded.selectedMatches.map(\.id), expected.map(\.id))
        let snapshot = TennisWatchSnapshot(data: reloaded.data, now: now)
        let restored = try JSONDecoder.tennisTracker.decode(TennisWatchSnapshot.self, from: JSONEncoder.tennisTracker.encode(snapshot))
        XCTAssertEqual(TennisMatchChronology.ordered(restored.matches).map(\.id), expected.map(\.id))
        for group in TennisMatchListGroup.allCases {
            XCTAssertEqual(TennisMatchListGroups(matches: restored.matches)[group].map(\.id), expected.filter { $0.status == group.status }.map(\.id))
        }
        XCTAssertTrue(restored.matches.allSatisfy { $0.notes == "Preserve example note" && $0.aces == 7 && $0.tournamentID == tournament.id })
    }

    func testResultAndNeedsDetailsNeverOverrideStatus() {
        for result in MatchResult.allCases {
            var scheduled = make(status: .scheduled, offset: -86_400)
            scheduled.result = result
            scheduled.needsDetails = true
            var finished = make(status: .completed, offset: 86_400)
            finished.result = result
            finished.needsDetails = true
            let groups = TennisMatchListGroups(matches: [scheduled, finished])
            XCTAssertEqual(groups[.upcoming], [scheduled])
            XCTAssertEqual(groups[.history], [finished])
            XCTAssertTrue(groups[.inProgress].isEmpty)
        }
    }

    func testNextUpcomingExcludesPastSchedulesAndOtherStatusesWithoutRemovingListRecords() {
        let calendar = upcomingCalendar
        var old = make(status: .scheduled, offset: -4 * 86_400)
        old.hasStartTime = false
        var elapsed = make(status: .scheduled, offset: -1)
        elapsed.hasStartTime = true
        var future = make(status: .scheduled, offset: 86_400)
        future.hasStartTime = true
        let completed = make(status: .completed, offset: 60)
        let active = make(status: .inProgress, offset: 120)
        let excluded = [old, elapsed, completed, active]
        let groups = TennisMatchListGroups(matches: excluded + [future], calendar: calendar)
        XCTAssertEqual(groups.nextUpcomingMatch(now: now), future)
        XCTAssertEqual(groups[.upcoming].map(\.id), [old.id, elapsed.id, future.id])
        XCTAssertNil(TennisMatchListGroups(matches: excluded, calendar: calendar).nextUpcomingMatch(now: now))
        var startingNow = future
        startingNow.id = UUID()
        startingNow.date = now
        XCTAssertEqual(TennisMatchListGroups(matches: [future, startingNow], calendar: calendar)
            .nextUpcomingMatch(now: now), startingNow)
    }

    func testNextUpcomingUses1205Before1400RegardlessOfInsertionOrder() {
        let calendar = upcomingCalendar
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        var earlier = make(status: .scheduled, offset: 0)
        earlier.hasStartTime = true
        earlier.date = calendar.date(bySettingHour: 12, minute: 5, second: 0, of: tomorrow)!
        var later = make(status: .scheduled, offset: 0)
        later.hasStartTime = true
        later.date = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: tomorrow)!
        for records in [[later, earlier], [earlier, later]] {
            XCTAssertEqual(TennisMatchListGroups(matches: records, calendar: calendar)
                .nextUpcomingMatch(now: now), earlier)
        }
    }

    func testNextUpcomingKeepsTodayWithUnspecifiedTimeRegardlessOfHiddenHour() {
        let calendar = upcomingCalendar
        let midday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
        var tomorrow = make(status: .scheduled, offset: 86_400)
        tomorrow.hasStartTime = true
        for hour in [0, 23] {
            var today = make(status: .scheduled, offset: 0)
            today.hasStartTime = false
            today.date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: midday)!
            XCTAssertEqual(TennisMatchListGroups(matches: [tomorrow, today], calendar: calendar)
                .nextUpcomingMatch(now: midday), today)
        }
        XCTAssertNil(TennisMatchListGroups(matches: [], calendar: calendar).nextUpcomingMatch(now: midday))
    }

    private var upcomingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 2 * 3600)!
        return calendar
    }

    func testEmptyInputProducesNoGroupsWithRecords() {
        let groups = TennisMatchListGroups(matches: [])
        XCTAssertTrue(TennisMatchListGroup.allCases.allSatisfy { groups[$0].isEmpty })
    }

    func testRecentHistoryKeepsNewestFiveAndAllPendingReviewsThenDisplaysAscending() {
        var history = (0..<8).map { make(status: .completed, offset: Double($0) * 86_400) }
        history[0].needsDetails = true
        history[6].needsDetails = true
        var scheduled = make(status: .scheduled, offset: -86_400)
        scheduled.needsDetails = true
        let groups = TennisMatchListGroups(matches: [scheduled] + Array(history.reversed()))
        let expected = history.enumerated().filter { $0.offset != 1 }.map(\.element)
        XCTAssertEqual(groups.recentHistory(limit: 5), expected)
        XCTAssertEqual(groups.recentHistory(limit: 0), [history[0], history[6]])
        XCTAssertEqual(Set(groups.recentHistory(limit: 5).map(\.id)).count, expected.count)
        XCTAssertFalse(groups.recentHistory(limit: 5).contains { $0.id == scheduled.id })
    }

    private func make(status: MatchStatus, offset: TimeInterval) -> MatchRecord {
        var match = MatchRecord(playerID: UUID())
        match.date = now.addingTimeInterval(offset)
        match.status = status
        match.notes = "Preserve example note"
        match.trainingSessionID = UUID()
        match.tournamentID = UUID()
        match.aces = 7
        return match
    }
}
