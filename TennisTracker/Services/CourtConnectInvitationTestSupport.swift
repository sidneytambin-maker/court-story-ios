#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Simulator-only service fixture. Unknown requests fail closed; no live account is used.
@MainActor enum CourtConnectInvitationTestSupport {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-ui-testing-connect-invitation") }
    static let actor="00000000-0000-4000-8000-000000000011"
    static let connection="00000000-0000-4000-8000-000000000012"
    static var responded=""
    static var attempts=0
    static func request(_ path: String, body: [String:Any]?) throws -> Any {
        if path == "/auth/v1/signup" { return ["access_token":"synthetic", "refresh_token":"synthetic", "user":["id":actor]] as [String:Any] }
        if path == "/rest/v1/rpc/cs_review_invitation" {
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-connect-expired") { throw CourtConnectError.message("This invitation has expired. Ask the sender for a new invitation.") }
            return ["name":"Synthetic sender", "role":"player", "sport":"Tennis"]
        }
        if path == "/rest/v1/rpc/cs_respond_invitation" {
            guard let response=body?["p_response"] as? String, ["accept","decline"].contains(response), body?["p_code"] as? String == String(repeating:"a",count:64) else { throw CourtConnectError.message("Invalid test response") }
            attempts += 1
            responded=response
            return ["response":response,"connection_id":connection]
        }
        if path == "/rest/v1/rpc/cs_register_profile" { return NSNull() }
        if path == "/rest/v1/rpc/cs_visible_manifest" || (path.hasPrefix("/rest/v1/cs_") && !path.contains("/rpc/")) { return [[String:Any]]() }
        throw CourtConnectError.message("Unexpected request in invitation test: " + path)
    }
}
#endif
