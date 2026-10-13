import SwiftUI

struct CourtConnectView: View {
    @EnvironmentObject private var store: TennisStore
    @ObservedObject private var connect = CourtConnect.shared
    @State private var email = ""
    @State private var signInCode = ""
    @State private var invitation = ""
    @State private var shareLink = ""
    @State private var recipient = ""
    @State private var invitationRole = "player"
    @State private var selectedConnection: ConnectSelection?
    @State private var consent = false
    private var player: PlayerProfile? { store.workspaceOwner }
    var body: some View {
        Form {
            Section("Your privacy") {
                Text("Connect is optional. Signing in does not upload your library. Health data and media are never included. Keep personal information out of sporting notes you choose to share.")
                Text(connect.status).accessibilityIdentifier("connectStatus")
            }
            if !connect.isSignedIn {
                Section("Sign in with an email code") {
                    TextField("Email address",text:$email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Send sign-in code") { connect.run { try await connect.sendCode(email:email) } }
                    TextField("Email sign-in code",text:$signInCode).textContentType(.oneTimeCode).keyboardType(.numberPad)
                    Button("Sign in") { connect.run { try await connect.verify(email:email,code:signInCode) } }
                }
            } else {
                Section("Invitations") {
                    Picker("Invite as",selection:$invitationRole) { Text("Player inviting coach").tag("player"); Text("Coach requesting player").tag("coach") }
                    Text("Sport: \(store.selectedSport.name)")
                    TextField("Recipient email (optional)",text:$recipient).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Create invitation") {
                        connect.run { shareLink = try await connect.invite(role:invitationRole,player:player,sport:store.selectedSport.id,recipient:recipient) }
                    }
                    if !shareLink.isEmpty {
                        Text("Expires after 48 hours. The player must approve sharing after acceptance.")
                        ShareLink("Share invitation",item:shareLink)
                        Button("Copy invitation") { UIPasteboard.general.string = shareLink; connect.status = "Invitation copied." }
                        Text(shareLink).textSelection(.enabled)
                    }
                    TextField("Invitation link or code",text:$invitation,axis:.vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Accept invitation") { connect.run { try await connect.accept(invitation,player:player) } }
                }
                Section("Connections and approval") {
                    if connect.connections.isEmpty { Text("No connections yet.") }
                    ForEach(connect.connections.compactMap(ConnectSelection.init)) { row in
                        Button(row.label) { selectedConnection = row }
                    }
                }
                Section("Upload consent on this device") {
                    Text("Only the owner profile and the sporting categories and history you approve for an active connection are eligible. Existing local records remain unchanged.")
                    Toggle("I approve uploading permitted sporting records",isOn:$consent)
                    Button("Enable sharing and synchronise") {
                        guard let player else { return }
                        connect.run { try await connect.enableUploads(for:player,library:store.data) }
                    }.disabled(!consent || player == nil)
                    Button("Pause uploads on this device") { connect.run { try connect.stopUploads() } }
                    Button("Refresh and retry sync") { connect.run { try await connect.sync(store.data) } }
                }
                Section("Shared sporting records") {
                    ForEach(connect.records.compactMap(ConnectRecord.init)) { record in
                        NavigationLink { ConnectRecordView(record:record) } label: {
                            VStack(alignment:.leading) { Text(record.title); Text(record.sport + " · " + record.category).font(.caption) }
                        }
                    }
                }
                Section("Account") { Button("Sign out") { connect.signOut() } }
            }
        }
        .navigationTitle("Court Story Connect")
        .disabled(connect.busy)
        .overlay { if connect.busy { ProgressView("Connecting") } }
        .onAppear { invitation = connect.pendingCode; if connect.isSignedIn { connect.run { try await connect.refresh() } } }
        .sheet(item:$selectedConnection) { selected in NavigationStack { ConnectPermissionView(connection:selected) } }
    }
}
struct ConnectSelection: Identifiable {
    let id: String; let value: [String:Any]
    init?(_ value: [String:Any]) { guard let id=value["id"] as? String else { return nil }; self.id=id; self.value=value }
    var label: String { (value["sport"] as? String ?? "Sport") + " · " + (value["state"] as? String ?? "Pending") + " · " + String(id.prefix(8)) }
}
struct ConnectRecord: Identifiable {
    let id: String; let value: [String:Any]
    init?(_ value: [String:Any]) { guard let id=value["id"] as? String else { return nil }; self.id=id; self.value=value }
    var body: [String:Any] { (value["body"] as? [String:Any]) ?? [:] }
    var title: String { (body["title"] as? String) ?? (body["text"] as? String) ?? "Sporting record" }
    var sport: String { value["sport"] as? String ?? "" }
    var category: String { value["category"] as? String ?? "" }
}
struct ConnectPermissionView: View {
    let connection: ConnectSelection
    @ObservedObject private var connect = CourtConnect.shared
    @Environment(\.dismiss) private var dismiss
    @State private var categories = Set(["match","training","tournament"])
    @State private var history = "future"
    @State private var future = true
    @State private var capability = "view"
    @State private var start = Date()
    @State private var end = Date()
    var owner: Bool { (connection.value["player_account"] as? String)?.lowercased() == connect.accountID }
    var body: some View {
        Form {
            Section { Text(connection.label); Text(connect.status) }
            if owner {
                Section("Sporting categories") {
                    Button("Share all eligible sporting categories") { categories=Set(CourtConnectProtocol.categories) }
                    ForEach(CourtConnectProtocol.categories,id:\.self) { category in
                        Toggle(category.capitalized,isOn:Binding(get:{ categories.contains(category) },set:{ if $0 { categories.insert(category) } else { categories.remove(category) } }))
                    }
                    Text("Health, media and private notes are always excluded.")
                }
                Section("History and future") {
                    Picker("History",selection:$history) { Text("Future only").tag("future"); Text("All history and future").tag("all"); Text("Selected period").tag("period") }
                    if history == "period" { DatePicker("From",selection:$start); DatePicker("Through",selection:$end) }
                    Toggle("Automatically share future records",isOn:$future)
                    Picker("Coach access",selection:$capability) { Text("View only").tag("view"); Text("Coach feedback").tag("feedback"); Text("Suggest contributions for approval").tag("contribute") }
                }
                Button("Approve and save sharing") { save("active") }
                Button("Keep private / pause connection") { save("paused") }
                Button("Revoke access",role:.destructive) { save("revoked") }
                Text("Revocation immediately stops server access. Copies previously saved by a coach cannot necessarily be erased remotely.")
            } else { Text("The player controls sharing and must approve this connection. This link alone gives no access.") }
        }.navigationTitle("Sharing permission").toolbar { Button("Done") { dismiss() } }.disabled(connect.busy)
        .onAppear {
            if connection.value["approved_at"] is String {
                categories=Set(connection.value["categories"] as? [String] ?? []); history=connection.value["history"] as? String ?? "future"
                capability=(connection.value["capability"] as? String) ?? "view"
                future=(connection.value["future_sharing"] as? Bool) ?? true
                if let date=connection.value["history_start"] as? String { start=CourtConnect.parseDate(date) }
                if let date=connection.value["history_end"] as? String { end=CourtConnect.parseDate(date) }
            }
        }
    }
    private func save(_ state: String) { connect.run { try await connect.permission(id:connection.id,state:state,categories:Array(categories),history:history,start:start,end:end,future:future,capability:capability) } }
}
struct ConnectRecordView: View {
    let record: ConnectRecord
    @ObservedObject private var connect = CourtConnect.shared
    @State private var message = ""
    @State private var kind = "feedback"
    var body: some View {
        Form {
            Section("Sporting record") { Text(record.title); ForEach(record.body.keys.sorted(),id:\.self) { key in Text(key + ": " + String(describing:record.body[key] ?? "")) } }
            Section("Coach feedback") {
                ForEach(connect.feedback.compactMap(ConnectSelection.init).filter { $0.value["record_id"] as? String == record.id }) { item in
                    Text(item.value["text"] as? String ?? "")
                    Text("Coach contribution · " + (item.value["state"] as? String ?? "pending"))
                    if (record.value["owner_id"] as? String)?.lowercased() == connect.accountID {
                        Button("Approve suggestion") { connect.run { try await connect.rpc("cs_review_feedback",["p_id":item.id,"p_approve":true]); try await connect.refresh() } }
                        Button("Reject suggestion") { connect.run { try await connect.rpc("cs_review_feedback",["p_id":item.id,"p_approve":false]); try await connect.refresh() } }
                    }
                }
                if let connection=connect.connections.first(where:{ ($0["coach_account"] as? String)?.lowercased() == connect.accountID && $0["player_id"] as? String == record.value["player_id"] as? String && $0["sport"] as? String == record.sport && $0["state"] as? String == "active" && $0["capability"] as? String != "view" }) {
                    Picker("Contribution type",selection:$kind) { Text("Feedback").tag("feedback"); Text("Suggested goal").tag("goal"); if connection["capability"] as? String == "contribute" { Text("Suggested record change").tag("contribution") } }
                    TextField("Feedback or suggestion",text:$message,axis:.vertical)
                    Button("Send to player") { connect.run {
                        try await connect.rpc("cs_add_feedback",["p_id":UUID().uuidString,"p_connection":connection["id"] as! String,"p_record":record.id,"p_kind":kind,"p_text":message]); message=""; try await connect.refresh()
                    } }.disabled(message.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                }
                Text("Suggestions never automatically change official scores. The player reviews and edits their own record.")
            }
            Text(connect.status)
        }.navigationTitle("Shared record").disabled(connect.busy)
    }
}
