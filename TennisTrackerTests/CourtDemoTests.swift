import XCTest
@testable import TennisTracker

final class CourtDemoTests: XCTestCase {
    func testAllFictionalRolesAndModesRoundTripWithoutMixingSportsOrHealth() throws {
        for role in CourtRole.allCases {
            for mode in TrackingMode.allCases {
                let data = CourtDemoLibrary.make(role: role, mode: mode)
                XCTAssertNil(CourtLibraryValidation.message(in: data))
                XCTAssertNoThrow(try TennisBackup.validate(data))
                XCTAssertTrue(data.trainingSessions.allSatisfy { $0.workout == nil })
                XCTAssertTrue(data.players.allSatisfy { $0.name.hasPrefix("Demo ") && $0.court.sports.count == 3 })
                let custom = try XCTUnwrap(data.matches.first?.court.score)
                XCTAssertEqual(custom.sport.name, "Goalball")
                XCTAssertEqual(custom.rules.system, .rally)
                XCTAssertEqual(custom.frame.winningSide, 0)
                XCTAssertFalse(custom.summary.contains("15"))
                let bytes = try JSONEncoder.tennisTracker.encode(data)
                let restored = try TennisBackup.decode(bytes)
                XCTAssertEqual(try JSONEncoder.tennisTracker.encode(restored), bytes)
                let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")
                attachment.name = "Fictional-Court-Story-\(role.rawValue)-\(mode.rawValue)-Private-Test-Backup.json"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testCoachAndAthleteAccessPreferencesRemainIndependent() throws {
        let data = CourtDemoLibrary.make()
        let owner = try XCTUnwrap(data.players.first)
        let athlete = try XCTUnwrap(data.players.last)
        XCTAssertEqual(owner.court.selected.access.allowedBounces(for: .tennis), 1)
        XCTAssertEqual(athlete.court.selected.access.allowedBounces(for: .tennis), 3)
        let snapshot = TennisWatchSnapshot(data: data)
        XCTAssertTrue(snapshot.mayUseHealth(for: owner.id))
        XCTAssertFalse(snapshot.mayUseHealth(for: athlete.id))
        XCTAssertEqual(snapshot.scoped(playerID: athlete.id, sport: .tennis).trainingSessions.count, 2)
        XCTAssertEqual(snapshot.scoped(playerID: athlete.id, sport: CourtSportSelection(sport: .badminton)).trainingSessions.count, 1)
    }
}
