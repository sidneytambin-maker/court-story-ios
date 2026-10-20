import XCTest
@testable import TennisTracker
final class ConnectInvitationConfirmationTests: XCTestCase {
    func testNamesSportsScopeAndFeedbackComeFromActualConnection() {
        let row: [String:Any] = ["player_name":"Morgan Lee","coach_name":"Alex","sport":"Badminton","state":"active","categories":["match","training"],"history":"all","future_sharing":true,"capability":"feedback"]
        let result=ConnectInvitationConfirmation(response:"accept",row:row,preview:[:],owner:false,localPlayer:"Other player")
        XCTAssertEqual(result.message,"You agreed to receive Morgan Lee’s Badminton data.")
        XCTAssertTrue(result.canView);XCTAssertFalse(result.canManage)
        XCTAssertTrue(result.details.contains("matches, training sessions"))
        XCTAssertTrue(result.details.contains("All approved historical records"))
        XCTAssertTrue(result.details.contains("You can add coaching feedback"))
        XCTAssertTrue(result.details.contains("Health data, media and records marked private are excluded"))
    }
    func testPendingAndRevokedNeverPromiseDataAccess() {
        for state in ["pending","paused","revoked"] {
            let result=ConnectInvitationConfirmation(response:"accept",row:["state":state,"player_name":"Jordan","sport":"Squash","capability":"feedback","categories":["match"]],preview:[:],owner:false,localPlayer:"")
            XCTAssertFalse(result.canView)
            XCTAssertFalse(result.details.contains("You can add coaching feedback to shared records"))
        }
    }
    func testViewOnlyAndDeclineDoNotOfferFeedbackOrDataIncorrectly() {
        let row:[String:Any] = ["state":"active","categories":["match"],"capability":"view"]
        let view=ConnectInvitationConfirmation(response:"accept",row:row,preview:[:],owner:false,localPlayer:"")
        XCTAssertTrue(view.details.contains("view only"))
        let decline=ConnectInvitationConfirmation(response:"decline",row:row,preview:["name":"Taylor","sport":"Padel"],owner:false,localPlayer:"")
        XCTAssertEqual(decline.message,"You declined the invitation from Taylor for Padel.")
        XCTAssertFalse(decline.canView);XCTAssertFalse(decline.canManage)
    }
}
