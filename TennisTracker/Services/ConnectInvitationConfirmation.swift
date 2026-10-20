import Foundation

struct ConnectInvitationConfirmation {
    let title: String
    let message: String
    let details: String
    let playerName: String
    let canView: Bool
    let canManage: Bool
    init(response: String,row: [String:Any],preview: [String:Any],owner: Bool,localPlayer: String) {
        let sender=preview["name"] as? String ?? "Court Story member"
        playerName=row["player_name"] as? String ?? (owner ? localPlayer : sender)
        let coach=row["coach_name"] as? String ?? sender
        let sport=row["sport"] as? String ?? preview["sport"] as? String ?? "sporting"
        let state=row["state"] as? String ?? "pending"
        let categories=row["categories"] as? [String] ?? []
        canView=response == "accept" && state == "active" && !categories.isEmpty
        canManage=response == "accept" && owner && state != "revoked"
        if response == "decline" {
            title="Invitation declined"
            message="You declined the invitation from \(sender) for \(sport)."
            details="This invitation did not enable any data sharing."
            return
        }
        title="Invitation accepted"
        message=owner ? "You accepted \(coach) as a coach for \(playerName)’s \(sport) record." : "You agreed to receive \(playerName)’s \(sport) data."
        if canView {
            let labels=["match":"matches","training":"training sessions","tournament":"tournaments","note":"sporting notes","reflection":"reflections","goal":"goals"]
            let included=categories.compactMap { labels[$0] }.joined(separator:", ")
            let history=row["history"] as? String ?? "future"
            let historyText=history == "all" ? "All approved historical records are included." : history == "period" ? "Only the player’s approved date range is included." : "Records from the date sharing was approved are included."
            let future=(row["future_sharing"] as? Bool)==true ? "New permitted records will update automatically." : "Future records are not included."
            let feedback=["feedback","contribute"].contains(row["capability"] as? String ?? "") ? (owner ? "Your coach can add coaching feedback." : "You can add coaching feedback to shared records.") : "Access is view only; coaching feedback is not enabled."
            details="Shared: \(included). \(historyText) \(future) \(feedback) Health data, media and records marked private are excluded."
        } else if state == "revoked" || state == "paused" {
            details="Sharing is currently \(state). This acceptance does not restore access."
        } else {
            details=owner ? "Choose what to share next. No records are available to your coach yet. You can include history and enable coaching feedback." : "Waiting for \(playerName) to approve what is shared. No records are available yet. Coaching feedback will be available if the player enables it."
        }
    }
}
