import XCTest
@testable import TennisTracker

final class TennisPrivacyPolicyTests: XCTestCase {
    func testOfflinePolicyHasDistinctCompleteTopics() {
        let topics = TennisPrivacyPolicy.topics
        XCTAssertEqual(Set(topics.map(\.id)), ["library", "watch", "health", "calendar", "backup", "delete", "beta", "contact"])
        XCTAssertEqual(Set(topics.map(\.id)).count, topics.count)
        XCTAssertTrue(topics.allSatisfy { !$0.title.isEmpty && !$0.text.isEmpty })
        XCTAssertEqual(TennisPrivacyPolicy.website.scheme, "https")
        XCTAssertEqual(TennisPrivacyPolicy.website.host, "sidneytambin-maker.github.io")
    }

    func testPolicyExplainsOptionalHealthAndReadableExports() throws {
        let health = try XCTUnwrap(TennisPrivacyPolicy.topics.first { $0.id == "health" })
        let backup = try XCTUnwrap(TennisPrivacyPolicy.topics.first { $0.id == "backup" })
        let deletion = try XCTUnwrap(TennisPrivacyPolicy.topics.first { $0.id == "delete" })
        XCTAssertTrue(health.text.contains("Basic tennis logging works without Health access"))
        XCTAssertTrue(backup.text.contains("not password-encrypted"))
        XCTAssertTrue(deletion.text.contains("does not delete a previously saved Apple Health workout"))
    }
}
