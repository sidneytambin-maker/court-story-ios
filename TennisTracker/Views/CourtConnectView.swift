import SwiftUI



struct CourtConnectView: View {

    @EnvironmentObject private var store: TennisStore

    @ObservedObject private var connect = CourtConnect.shared

    @State private var playerSearch = ""

    @State private var invitation = ""

    @State private var shareLink = ""

    @State private var invitationRole = "player"

    @State private var selectedConnection: ConnectSelection?

    @State private var consent = false

    @State private var deleteAccount = false

    @State private var invitationPreview: [String:Any] = [:]

    @State private var reviewInvitation = false

    @State private var attemptedInvitation = ""

    @State private var initialized = false

    @State private var confirmationID: String?

    @State private var confirmedResponse = ""

    @State private var invitationMessage = ""
    @AccessibilityFocusState private var confirmationFocused: Bool

    private var player: PlayerProfile? { store.workspaceOwner }

    private func previewInvitation() {

        guard !connect.busy else { return }

        let incoming=invitation

        attemptedInvitation=incoming

        invitationMessage="Checking invitation…"

        connect.run {

            do {

                if !connect.isSignedIn { try await connect.connectDevice() }

                let preview=try await connect.preview(incoming)

                guard invitation == incoming else { return }

                invitationPreview=preview

                invitationMessage=""

                let response=CourtConnectProtocol.response(incoming,host:connect.linkHost)

                if response.isEmpty { reviewInvitation=true }

                else { try await respond(incoming,response:response) }

            } catch {

                if invitation == incoming { invitationMessage=error.localizedDescription }

                throw error

            }

        }

    }

    private func chooseResponse(_ response: String) {

        guard let code=CourtConnectProtocol.code(invitation,host:connect.linkHost) else { return }

        invitation=code+"/"+response

        if let url=URL(string:"https://"+connect.linkHost+"/connect/invite#"+invitation) { _=connect.receive(url) }

        previewInvitation()

    }

    private func respond(_ incoming: String, response: String) async throws {

        do {

            let resultID: String

            if response == "decline" { try await connect.decline(incoming); resultID="" }

            else if response == "accept" { resultID=try await connect.accept(incoming,player:player) }

            else { return }

            guard invitation == incoming else { return }

            confirmationID=resultID; confirmedResponse=response

            invitation=""; reviewInvitation=false

        } catch { invitationMessage=error.localizedDescription; throw error }

    }

    private var invitationConfirmation: some View {

        let row=connect.connections.first { $0["id"] as? String == confirmationID } ?? [:]

        let owner=(invitationPreview["role"] as? String)=="coach"

        let result=ConnectInvitationConfirmation(response:confirmedResponse,row:row,preview:invitationPreview,owner:owner,localPlayer:player?.displayName ?? "Player")

        return ScrollView {

            VStack(alignment:.leading,spacing:18) {

                Text(result.title).font(.title).accessibilityAddTraits(.isHeader).accessibilityFocused($confirmationFocused)

                Text(result.message)

                Text(result.details)

                if result.canView, let id=row["player_id"] as? String {

                    NavigationLink("View player’s data") { ConnectPlayerDashboard(player:ConnectPlayerGroup(id:id,name:result.playerName)) }.buttonStyle(.borderedProminent)

                }

                if result.canManage, let selection=ConnectSelection(row) {

                    Button("Choose what to share") { selectedConnection=selection }.buttonStyle(.borderedProminent)

                }

                if confirmedResponse == "accept" {

                    Button("Refresh sharing status") { connect.run { try await connect.refresh() } }

                }

                Button("Done") { confirmationID=nil; confirmedResponse="" }

            }.padding().frame(maxWidth:.infinity,alignment:.leading)

        }

    }

    private var invitationEntry: some View {

        VStack(alignment:.leading,spacing:12) {

            Text("Have an invitation?").font(.headline).accessibilityAddTraits(.isHeader)

            PasteButton(payloadType: String.self) { values in

                guard let value=values.first else { return }

                invitation=value; previewInvitation()

            }.accessibilityLabel("Paste invitation")

            TextField("Invitation link or code",text:$invitation,axis:.vertical)

                .textInputAutocapitalization(.never).autocorrectionDisabled()

            Button("Review invitation") { previewInvitation() }.disabled(invitation.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)

        }

    }

    private var invitationReview: some View {

        Form {

            Section("Connection invitation") {

                Text(invitationPreview["name"] as? String ?? "Court Story member").font(.title2)

                Text(invitationPreview["role"] as? String == "player" ? "Would like you to be their coach." : "Would like to coach you.")

                Text("Sport: " + (invitationPreview["sport"] as? String ?? "Sport"))

                Text("No records are shared by accepting. The player chooses what to share next. Health data and media stay private.")

                Text(invitationMessage.isEmpty ? connect.status : invitationMessage).accessibilityIdentifier("connectStatus")

            }

            Section {

                Button("Accept invitation") {

                    let incoming=invitation

                    connect.run { try await respond(incoming,response:"accept") }

                }.buttonStyle(.borderedProminent)

                Button("Decline invitation",role:.destructive) {

                    let incoming=invitation

                    connect.run { try await respond(incoming,response:"decline") }

                }

                Button("Not now") { if let code=CourtConnectProtocol.code(invitation,host:connect.linkHost) { connect.clearPending(code) }; invitation=""; reviewInvitation=false }

            }

        }

    }

    private var signInForm: some View {

        ScrollView {

            VStack(alignment:.leading,spacing:20) {

                if !invitation.isEmpty { Text("Your invitation is ready").font(.title2); Text("Review who sent it, then accept or decline. Nothing is shared yet.") }

                invitationEntry

                Text("Your privacy").font(.headline).accessibilityAddTraits(.isHeader)

                Text("Connect is optional. Enabling it does not upload your library. Health data and media are never included. Keep personal information out of sporting notes you choose to share.").fixedSize(horizontal:false,vertical:true)

                Text(connect.status).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("connectStatus")

                Text("Connect through a shared link").font(.headline).fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader)

                Text("No email or password needed. Your connection is saved securely on this device. Share an invitation using any messaging app, or paste a link you received.").fixedSize(horizontal:false,vertical:true)

                Button { connect.run { try await connect.connectDevice() } } label: { Text("Enable Connect").fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,minHeight:44) }.buttonStyle(.borderedProminent)



            }.font(.body).padding()

        }.background(Color(uiColor:.systemBackground))

    }

    var body: some View {

        Group {

        if confirmationID != nil { invitationConfirmation } else if reviewInvitation { invitationReview } else if !invitation.isEmpty && (!connect.isSignedIn || !CourtConnectProtocol.response(invitation,host:connect.linkHost).isEmpty) {

            Form {

                Section("Connection invitation") {

                    Text(invitationMessage.isEmpty ? connect.status : invitationMessage).accessibilityIdentifier("connectStatus")

                    if CourtConnectProtocol.response(invitation,host:connect.linkHost).isEmpty {

                        Text("Choose your response. Court Story will check the invitation securely. No email or password is needed, and no sporting records are uploaded.")

                        Button("Accept invitation") { chooseResponse("accept") }.buttonStyle(.borderedProminent)

                        Button("Decline invitation",role:.destructive) { chooseResponse("decline") }

                    } else { Button("Try again") { previewInvitation() } }

                    Button("Not now") { if let code=CourtConnectProtocol.code(invitation,host:connect.linkHost) { connect.clearPending(code) }; invitation="" }

                }

            }

        } else if !connect.isSignedIn { signInForm } else {

        Form {

            Section {

                Text("Connect is optional. Enabling it does not upload your library. Health data and media are never included. Keep personal information out of sporting notes you choose to share.").fixedSize(horizontal:false,vertical:true)

                Text(connect.status).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("connectStatus")

            } header: { Text("Your privacy").foregroundStyle(Color(uiColor:.label)) }

                Section("Invitations") {

                    Picker("Invite as",selection:$invitationRole) { Text("Player inviting coach").tag("player"); Text("Coach requesting player").tag("coach") }

                    Text("Sport: \(store.selectedSport.name)")

                    Button("Create invitation") {

                        connect.run { shareLink = try await connect.invite(role:invitationRole,player:player,sport:store.selectedSport.id,recipient:"") }

                    }

                    if !shareLink.isEmpty {

                        Text("Expires after 48 hours. The player must approve sharing after acceptance.")

                        ShareLink("Share invitation",item:shareLink)

                        Button("Copy invitation") { UIPasteboard.general.string = shareLink; connect.status = "Invitation copied." }

                        Text(shareLink).textSelection(.enabled)

                    }

                    invitationEntry

                }

                Section("Connections and approval") {

                    if connect.connections.isEmpty { Text("No connections yet.") }

                    ForEach(connect.connections.compactMap(ConnectSelection.init)) { row in

                        Button(row.label) { selectedConnection = row }

                    }

                }

                Section("Upload consent on this device") {

                    Text("Only the owner profile and the sporting categories and history you approve for an active connection are eligible. Existing local records remain unchanged.")

                    NavigationLink("Manage private records and notes") { ConnectRecordPrivacyView() }

                    Toggle("I approve uploading permitted sporting records",isOn:$consent)

                    Button("Enable sharing and synchronise") {

                        guard let player else { return }

                        connect.run { try await connect.enableUploads(for:player,library:store.data) }

                    }.disabled(!consent || player == nil)

                    Button("Pause uploads on this device") { connect.run { try connect.stopUploads() } }

                    Button("Refresh and retry sync") { connect.run { try await connect.sync(store.data) } }

                }

                if !connect.syncConflicts.isEmpty {

                    Section("Review changed records") {

                        ForEach(connect.syncConflicts.compactMap { request -> ConnectSelection? in var row=request; row["id"]=request["p_id"]; return ConnectSelection(row) }) { item in

                            Text("Queued device version: " + ConnectRecordView.summary(item.value["p_body"] as? [String:Any] ?? [:]))

                            Text("Current online version: " + ConnectRecordView.summary(connect.records.first { $0["id"] as? String == item.id }?["body"] as? [String:Any] ?? [:]))

                            Button("Keep online version; leave local record unchanged") { connect.run { try connect.resolveConflict(item.id,useDevice:false) } }

                            Button("Use reviewed device version") { connect.run { try connect.resolveConflict(item.id,useDevice:true) } }

                        }

                    }

                }

                if !connect.pendingFeedback.isEmpty {

                    Section("Outgoing feedback") {

                        ForEach(connect.pendingFeedback.compactMap { request -> ConnectSelection? in var row=request; row["id"]=request["p_id"]; return ConnectSelection(row) }) { item in

                            Text(item.value["p_text"] as? String ?? "")

                            Button("Remove queued feedback",role:.destructive) { connect.run { try connect.discardFeedback(item.id) } }

                        }

                        Text("Reconnect and use Refresh and retry sync. If sharing was revoked, remove feedback that can no longer be sent.")

                    }

                }

                Section("Players and shared records") {

                    TextField("Find a player",text:$playerSearch).textInputAutocapitalization(.never).autocorrectionDisabled()

                    ForEach(connect.playerGroups.filter { playerSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(playerSearch) }) { group in

                        NavigationLink { ConnectPlayerDashboard(player:group) } label: {

                            VStack(alignment:.leading) { Text(group.name); Text(group.id == player?.id.uuidString.lowercased() ? "Your shared player record" : "Separate player record").font(.caption) }

                        }

                    }

                    if connect.playerGroups.isEmpty { Text("Approved players appear here. Each player's records stay separate.") }

                }

                Section("Confirmations and notifications") {

                    NavigationLink("Manage Connect notifications") { ConnectNotificationSettingsView() }

                    ForEach(connect.notifications.compactMap(ConnectSelection.init)) { item in

                        Text(item.value["message"] as? String ?? "Connection updated")

                    }

                }

                Section("Manage sharing") {

                    Button("Delete connections and shared cloud data",role:.destructive) { deleteAccount=true }

                }

            }

        }

        }

        .navigationTitle("Court Story Connect")

        .toolbar(.hidden,for:.tabBar)

        .disabled(connect.busy)

        .overlay { if connect.busy { ProgressView("Connecting") } }

        .task(id:connect.pendingCode) {

            let first = !initialized

            initialized=true

            if !connect.pendingCode.isEmpty {

                invitation=connect.pendingCode

                confirmationID=nil; confirmedResponse=""

                if connect.isSignedIn || !CourtConnectProtocol.response(invitation,host:connect.linkHost).isEmpty { previewInvitation() }

            } else if first && connect.isSignedIn && !connect.busy { connect.run { try await connect.refresh() } }

        }

        .onChange(of:connect.busy) { _, busy in

            if !busy && !connect.pendingCode.isEmpty && connect.pendingCode != attemptedInvitation {

                invitation=connect.pendingCode

                confirmationID=nil; confirmedResponse=""

                if connect.isSignedIn || !CourtConnectProtocol.response(invitation,host:connect.linkHost).isEmpty { previewInvitation() }

            }

        }

        .confirmationDialog("Delete your connections and shared cloud data?",isPresented:$deleteAccount,titleVisibility:.visible) {

            Button("Delete connections and cloud data",role:.destructive) { connect.run { try await connect.deleteAccount() } }

        } message: { Text("This removes all your online connections, shared records and feedback. Your local sporting library stays on this device. Copies already saved by coaches cannot necessarily be erased.") }

        .sheet(item:$selectedConnection) { selected in NavigationStack { ConnectPermissionView(connection:selected) } }

    }

}

struct ConnectSelection: Identifiable {

    let id: String; let value: [String:Any]

    init?(_ value: [String:Any]) { guard let id=value["id"] as? String else { return nil }; self.id=id; self.value=value }

    @MainActor var label: String { ((value["player_account"] as? String)?.lowercased() == CourtConnect.shared.accountID ? (value["coach_name"] as? String ?? "Coach") : (value["player_name"] as? String ?? "Player")) + " - " + (value["sport"] as? String ?? "Sport") + " - " + (value["state"] as? String ?? "Pending") }

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

    @EnvironmentObject private var store: TennisStore

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

                    Button("Share all sporting data, including history") { categories=Set(CourtConnectProtocol.categories); history="all"; future=true }

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

                Button("Approve and start sharing") { save("active") }

                Text("This approves uploading the selected sporting records from this device. You can pause sharing or change these choices at any time.")

                Button("Keep private / pause connection") { save("paused") }

                Button("Revoke access",role:.destructive) { save("revoked") }

                Text("Revocation immediately stops server access. Copies previously saved by a coach cannot necessarily be erased remotely.")

            } else {

                Text("The player controls sharing and must approve this connection. This link alone gives no access.")

                Button("Decline or leave connection",role:.destructive) { connect.run { try await connect.rpc("cs_leave_connection",["p_id":connection.id]);try await connect.refresh() } }

            }

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

    private func save(_ state: String) {

        connect.run {

            if state == "active" {

                guard let player=store.workspaceOwner, player.id.uuidString.lowercased()==(connection.value["player_id"] as? String)?.lowercased() else {

                    throw CourtConnectError.message("Switch to the player profile named in this connection before sharing.")

                }

                try await connect.permission(id:connection.id,state:state,categories:Array(categories),history:history,start:start,end:end,future:future,capability:capability)

                try await connect.enableUploads(for:player,library:store.data)

            } else {

                try await connect.permission(id:connection.id,state:state,categories:Array(categories),history:history,start:start,end:end,future:future,capability:capability)

            }

            dismiss()

        }

    }

}

struct ConnectNotificationSettingsView: View {

    @ObservedObject private var connect=CourtConnect.shared

    @State private var push=false

    @State private var requests=true

    @State private var sharing=true

    @State private var feedback=true

    var body: some View {

        Form {

            Section("Connect push notifications") {

                Toggle("Enable Connect push notifications",isOn:$push)

                Toggle("Coach invitations and requests",isOn:$requests)

                Toggle("Sharing confirmations and revocations",isOn:$sharing)

                Toggle("New coach feedback",isOn:$feedback)

                Text("When sharing becomes active, the confirmation names the coach. Sporting records and Health data are not included in notifications. Delivery also depends on your device notification settings and connectivity.")

                Button("Save notification settings") { connect.run { try await connect.saveNotifications(push:push,requests:requests,sharing:sharing,feedback:feedback) } }

                Button("Open iPhone notification settings") { if let url=URL(string:UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) } }

                Text(connect.status)

            }

        }.navigationTitle("Connect notifications").disabled(connect.busy)

        .onAppear { push=connect.notificationSettings["push_enabled"] as? Bool ?? false;requests=connect.notificationSettings["connection_requests"] as? Bool ?? true;sharing=connect.notificationSettings["sharing_confirmations"] as? Bool ?? true;feedback=connect.notificationSettings["coach_feedback"] as? Bool ?? true }

    }

}

struct ConnectRecordView: View {

    let record: ConnectRecord

    @ObservedObject private var connect = CourtConnect.shared

    @State private var message = ""

    @State private var kind = "feedback"

    static func summary(_ body: [String:Any]) -> String { body.keys.sorted().map { fieldLabel($0) + ": " + String(describing:body[$0] ?? "") }.joined(separator:". ") }

    static func fieldLabel(_ key: String) -> String {

        key.replacingOccurrences(of:"([a-z])([A-Z])",with:"$1 $2",options:.regularExpression).replacingOccurrences(of:"_",with:" ").capitalized

    }

    var body: some View {

        Form {

            if let record=connect.records.compactMap(ConnectRecord.init).first(where:{$0.id==self.record.id}) {

            Section("Sporting record") { Text(record.title); ForEach(record.body.keys.sorted(),id:\.self) { key in Text(Self.fieldLabel(key) + ": " + String(describing:record.body[key] ?? "")) } }

            Section("Participants and teams") {

                ForEach(connect.participants.compactMap(ConnectSelection.init).filter { $0.value["record_id"] as? String == record.id }) { person in

                    Text((person.value["display_name"] as? String ?? "Participant") + " - Team " + String((person.value["team"] as? Int ?? 0)+1))

                }

            }

            Section("Coach feedback") {

                ForEach(connect.feedback.compactMap(ConnectSelection.init).filter { $0.value["record_id"] as? String == record.id }) { item in

                    Text(item.value["text"] as? String ?? "")

                    Text("Coach contribution - " + (item.value["state"] as? String ?? "pending"))

                    if (record.value["owner_id"] as? String)?.lowercased() == connect.accountID {

                        Button("Approve suggestion") { connect.run { try await connect.rpc("cs_review_feedback",["p_id":item.id,"p_approve":true]); try await connect.refresh() } }

                        Button("Reject suggestion") { connect.run { try await connect.rpc("cs_review_feedback",["p_id":item.id,"p_approve":false]); try await connect.refresh() } }

                    }

                }

                if let connection=connect.connections.first(where:{ ($0["coach_account"] as? String)?.lowercased() == connect.accountID && $0["player_id"] as? String == record.value["player_id"] as? String && $0["sport"] as? String == record.sport && $0["state"] as? String == "active" && $0["capability"] as? String != "view" }) {

                    Picker("Contribution type",selection:$kind) { Text("Feedback").tag("feedback"); Text("Suggested goal").tag("goal"); if connection["capability"] as? String == "contribute" { Text("Suggested record change").tag("contribution") } }

                    TextField("Feedback or suggestion",text:$message,axis:.vertical)

                    Button("Send to player") { connect.run {

                        try connect.queueFeedback(["p_id":UUID().uuidString,"p_connection":connection["id"] as! String,"p_record":record.id,"p_kind":kind,"p_text":message]); message=""

                    } }.disabled(message.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)

                }

                Text("Suggestions never automatically change official scores. The player reviews and edits their own record.")

            }

            } else { Text("This shared record is no longer available. Refresh connections to check current access.") }

            Text(connect.status)

        }.navigationTitle("Shared record").disabled(connect.busy)

    }

}



struct ConnectRecordPrivacyView: View {

    @EnvironmentObject private var store: TennisStore

    @ObservedObject private var connect=CourtConnect.shared

    private var localRecords: [[String:Any]] { guard let owner=store.workspaceOwner else { return [] }; return (try? CourtConnect.projections(store.data,players:[owner.id.uuidString.lowercased()])) ?? [] }

    var body: some View {

        Form {

            Section { Text("Mark records, notes or reflections private before enabling uploads. Private records are hidden from every coach. If a record was already shared, changing privacy needs an internet connection to remove server access."); Text(connect.status) }

            ForEach(localRecords.compactMap { row -> ConnectSelection? in var value=row; value["id"]=row["p_id"]; return ConnectSelection(value) }) { row in

                let body=row.value["p_body"] as? [String:Any] ?? [:]

                Toggle(isOn:Binding(get:{connect.isPrivate(row.id)},set:{ value in connect.run { try await connect.setPrivate(row.id,private:value,library:store.data) } })) {

                    Text((row.value["p_category"] as? String ?? "Record").capitalized + ": " + (body["title"] as? String ?? body["text"] as? String ?? "Sporting record"))

                    Text("Keep private")

                }

            }

        }.navigationTitle("Private records and notes").disabled(connect.busy)

    }

}

struct ConnectPlayerGroup: Identifiable { let id: String; let name: String }

extension CourtConnect {

    var playerGroups: [ConnectPlayerGroup] {

        var groups: [String:String]=[:]

        for row in connections where row["state"] as? String == "active" {

            if let id=row["player_id"] as? String { groups[id.lowercased()]=row["player_name"] as? String ?? "Player" }

        }

        return groups.map { ConnectPlayerGroup(id:$0.key,name:$0.value) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    }

}

struct ConnectPlayerDashboard: View {

    let player: ConnectPlayerGroup

    @EnvironmentObject private var store: TennisStore

    @State private var localProfile=""

    @State private var confirmLink=false

    @ObservedObject private var connect=CourtConnect.shared

    @State private var sport="All approved sports"

    @State private var category="All categories"

    private var rows: [ConnectRecord] { connect.records.filter { ($0["player_id"] as? String)?.lowercased()==player.id }.compactMap(ConnectRecord.init).sorted { CourtConnect.parseDate($0.value["occurred_at"] as? String ?? "") > CourtConnect.parseDate($1.value["occurred_at"] as? String ?? "") } }

    private var sports: [String] { Array(Set(rows.map(\.sport))).sorted() }

    var body: some View {

        List {

            Section { Text("Records for " + player.name + " only. Sharing remains under this player's control."); Text(connect.status) }

            if player.id != store.workspaceOwner?.id.uuidString.lowercased() {

                Section("Existing local player profile") {

                    Picker("Local profile",selection:$localProfile) { Text("No link").tag(""); ForEach(store.data.players.filter { $0.id != store.workspaceOwner?.id }) { Text($0.displayName).tag($0.id.uuidString.lowercased()) } }

                    Button("Confirm local profile link") { confirmLink=true }

                    Text("Choose explicitly. Names never merge players automatically, and both histories remain separate.")

                }

            }

            Section("Filter records") {

                Picker("Sport",selection:$sport) { Text("All approved sports").tag("All approved sports"); ForEach(sports,id:\.self) { Text($0).tag($0) } }

                Picker("Category",selection:$category) { Text("All categories").tag("All categories"); ForEach(CourtConnectProtocol.categories,id:\.self) { Text($0.capitalized).tag($0) } }

            }

            ForEach(rows.filter { (sport=="All approved sports" || $0.sport==sport) && (category=="All categories" || $0.category==category) }) { record in

                NavigationLink { ConnectRecordView(record:record) } label: { VStack(alignment:.leading) { Text(record.title); Text(record.sport + " - " + record.category); Text(record.value["occurred_at"] as? String ?? "") } }

            }

        }.navigationTitle(player.name)

        .onAppear { localProfile=connect.linkedPlayer(player.id) ?? "" }

        .alert("Confirm this player's local profile link?",isPresented:$confirmLink) {

            Button("Confirm link") { connect.run { try connect.linkPlayer(player.id,local:localProfile.isEmpty ? nil : localProfile) } }

            Button("Cancel",role:.cancel) {}

        } message: { Text("This links the selected local profile to " + player.name + " on this device. It does not merge, overwrite or upload either player's history.") }

    }

}

