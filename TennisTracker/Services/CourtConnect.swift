import Foundation
import Combine
import BackgroundTasks
import Security
import CryptoKit
import UIKit
import UserNotifications

enum CourtConnectError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum CourtConnectProtocol {
    static let categories = ["match", "training", "tournament", "note", "reflection", "goal"]
    static func code(_ input: String, host: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if let url = URL(string: text), url.scheme != nil {
            let allowedHosts = host == "court-story-connect.web.app" ? [host, "court-story-connect.firebaseapp.com"] : [host]
            guard url.scheme == "https", allowedHosts.contains(url.host ?? ""), url.path == "/connect/invite", url.user == nil,
                  url.password == nil, url.port == nil, url.query == nil else { return nil }
            candidate = url.fragment ?? ""
        } else { candidate = text }
        return candidate.range(of: "^[a-f0-9]{64}(/(accept|decline))?$", options: .regularExpression) != nil ? String(candidate.prefix(64)) : nil
    }
    static func response(_ input: String, host: String) -> String {
        guard code(input,host:host) != nil else { return "" }
        let text=input.trimmingCharacters(in:.whitespacesAndNewlines)
        let value = text.contains(":") ? (URL(string:text)?.fragment ?? "") : text
        return value.count > 64 ? String(value.dropFirst(65)) : ""
    }
    static func noteID(_ id: UUID) -> UUID { derivedID(id,category:"note") }
    static func derivedID(_ id: UUID, category: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(("court-story-" + category + ":" + id.uuidString.lowercased()).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 15) | 80; bytes[8] = (bytes[8] & 63) | 128
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
}

struct CourtConnectSession: Codable {
    var access_token: String
    var refresh_token: String
    var expires_at: Double?
    var user: User
    struct User: Codable { var id: String; var email: String? }
}

@MainActor final class CourtConnect: ObservableObject {
    static let shared = CourtConnect()
    @Published private(set) var session: CourtConnectSession?
    @Published private(set) var connections: [[String: Any]] = []
    @Published private(set) var records: [[String: Any]] = []
    @Published private(set) var participants: [[String:Any]] = []
    @Published private(set) var feedback: [[String: Any]] = []
    @Published private(set) var notifications: [[String: Any]] = []
    @Published private(set) var notificationSettings: [String: Any] = [:]
    @Published var status = "Local-only. Nothing is uploaded until you approve sharing."
    @Published var pendingCode = ""
    @Published private(set) var busy = false
    private var state: [String: Any] = [:]
    private var syncing = false
    private var pendingLibrary: AppData?
    private var recordCursor = 0
    private var connectionFingerprint = Data()
    private let keychainService = "app.courtstory.connect.session"
    private var config: [String: String] {
        guard let url = Bundle.main.url(forResource: "CourtConnectConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode([String:String].self, from: data) else { return [:] }
        return value
    }
    var linkHost: String { config["link_host"] ?? "" }
    var accountID: String? { session?.user.id.lowercased() }
    var isSignedIn: Bool { session != nil }
    private var stateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("court-connect-" + (accountID ?? "signed-out") + ".json")
    }
    private init() {
        #if DEBUG && targetEnvironment(simulator)
        if CourtConnectInvitationTestSupport.enabled { return }
        #endif
        var result: CFTypeRef?
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:keychainService,
                                  kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            session = try? JSONDecoder().decode(CourtConnectSession.self, from: data)
        }
        pendingCode = UserDefaults.standard.string(forKey: "CourtConnectPendingInvitation") ?? ""
        loadState()
    }
    private func loadState() {
        state = [:]
        if let data = try? Data(contentsOf: stateURL), let saved = try? JSONSerialization.jsonObject(with: data) as? [String:Any] { state = saved }
    }
    private func persist() throws {
        #if DEBUG && targetEnvironment(simulator)
        if CourtConnectInvitationTestSupport.enabled { return }
        #endif
        let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        try data.write(to: stateURL, options: [.atomic, .completeFileProtection])
    }
    private func saveSession(_ newSession: CourtConnectSession) throws {
        #if DEBUG && targetEnvironment(simulator)
        if CourtConnectInvitationTestSupport.enabled { session=newSession; return }
        #endif
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:keychainService]
        let data = try JSONEncoder().encode(newSession)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String:data] as CFDictionary)
        if result == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary,nil) == errSecSuccess else { throw CourtConnectError.message("Could not securely save this device connection.") }
        } else if result != errSecSuccess { throw CourtConnectError.message("Could not securely save this device connection.") }
        let changed = accountID != newSession.user.id.lowercased()
        session = newSession
        if changed { records = []; feedback = []; connections = []; loadState() }
    }
    func signOut() async throws {
        var serverConfirmed=true
        if isSignedIn {
            do {
                if let installation=UserDefaults.standard.string(forKey:"CourtConnectInstallation") { try await rpc("cs_unregister_device",["p_installation":installation]) }
                _ = try await request("/auth/v1/logout?scope=local",method:"POST")
            } catch { serverConfirmed=false }
        }
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.content.userInfo["connect_notification"] != nil }.map { $0.request.identifier })
        UIApplication.shared.unregisterForRemoteNotifications()
        SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:keychainService] as CFDictionary)
        session = nil; records = []; participants = []; feedback = []; connections = []; notifications = []; notificationSettings = [:]; state = [:]
        status = "Signed out on this device. Your local sporting records are unchanged." + (serverConfirmed ? "" : " Server sign-out was not confirmed.")
    }
    func deleteAccount() async throws {
        _ = try await request("/functions/v1/delete-account",method:"DELETE")
        try? FileManager.default.removeItem(at:stateURL)
        UIApplication.shared.unregisterForRemoteNotifications()
        SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:keychainService] as CFDictionary)
        session=nil; state=[:]; records=[]; participants=[]; connections=[]; feedback=[]; notifications=[]; notificationSettings=[:]
        status="Connections and shared cloud data deleted. Your local sporting library is unchanged."
    }
    func receive(_ url: URL) -> Bool {
        guard !linkHost.isEmpty, let code = CourtConnectProtocol.code(url.absoluteString, host: linkHost) else { return false }
        let response=CourtConnectProtocol.response(url.absoluteString,host:linkHost)
        pendingCode = code + (response.isEmpty ? "" : "/" + response)
        UserDefaults.standard.set(pendingCode, forKey:"CourtConnectPendingInvitation"); return true
    }
    private func request(_ path: String, method: String = "POST", body: [String:Any]? = nil, authenticated: Bool = true, retry: Bool = true) async throws -> Any {
        #if DEBUG && targetEnvironment(simulator)
        if CourtConnectInvitationTestSupport.enabled { return try CourtConnectInvitationTestSupport.request(path,body:body) }
        #endif
        guard let base = config["supabase_url"], let origin = URL(string: base), origin.scheme == "https",
              let key = config["publishable_key"], !key.isEmpty, let url = URL(string: base + path) else {
            throw CourtConnectError.message("Court Story Connect service configuration is unavailable. Local tracking remains available.")
        }
        if authenticated && session == nil { throw CourtConnectError.message("Enable Connect on this device first.") }
        var req = URLRequest(url: url); req.httpMethod = method; req.timeoutInterval = 30
        req.setValue(key, forHTTPHeaderField:"apikey"); req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if authenticated, let token = session?.access_token { req.setValue("Bearer " + token, forHTTPHeaderField:"Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject:body) }
        let (data,response) = try await URLSession.shared.data(for:req)
        guard let http = response as? HTTPURLResponse else { throw CourtConnectError.message("No response. Try again when online.") }
        if http.statusCode == 401 && authenticated && retry, let refresh = session?.refresh_token {
            let value = try await request("/auth/v1/token?grant_type=refresh_token",body:["refresh_token":refresh],authenticated:false,retry:false)
            let renewed = try JSONDecoder().decode(CourtConnectSession.self,from:JSONSerialization.data(withJSONObject:value))
            try saveSession(renewed)
            return try await request(path,method:method,body:body,authenticated:true,retry:false)
        }
        guard (200..<300).contains(http.statusCode) else {
            let obj = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
            if obj?["code"] as? String == "40001" { throw CourtConnectError.message("A record changed on another device. Refresh and review the conflict; your queued edit is retained.") }
            throw CourtConnectError.message(http.statusCode == 429 ? "Please wait before trying again." : "The request was not accepted. Check your connection, invitation expiry and sharing permission.")
        }
        if data.isEmpty { return NSNull() }
        return try JSONSerialization.jsonObject(with:data,options:.fragmentsAllowed)
    }
    @discardableResult func rpc(_ name: String, _ parameters: [String:Any]) async throws -> Any { try await request("/rest/v1/rpc/"+name,body:parameters) }
    func connectDevice() async throws {
        guard session == nil else { return }
        let response = try await request("/auth/v1/signup",body:[:],authenticated:false,retry:false)
        try saveSession(JSONDecoder().decode(CourtConnectSession.self,from:JSONSerialization.data(withJSONObject:response)))
        try await refresh()
        status = "Ready to connect. Share an invitation or open one you received. Nothing is uploaded until you approve sharing."
    }
    private func allRows(_ table: String, order: String = "id") async throws -> [[String:Any]] {
        var rows: [[String:Any]] = []; var offset = 0
        while true {
            let next = try await request("/rest/v1/"+table+"?select=*&order=\(order)&limit=200&offset=\(offset)",method:"GET") as? [[String:Any]] ?? []
            rows += next; if next.count < 200 { return rows }; offset += next.count
        }
    }
    func refresh() async throws {
        let actor=accountID
        var cache=Dictionary(uniqueKeysWithValues:records.compactMap { row -> (String,[String:Any])? in guard let id=row["id"] as? String else { return nil }; return (id,row) })
        records=[]; feedback=[]
        let latest=try await allRows("cs_connections")
        let fingerprint=try JSONSerialization.data(withJSONObject:latest,options:.sortedKeys)
        var cursor=recordCursor
        var deletedRemotely=Set(state["remoteDeletedIDs"] as? [String] ?? [])
        if fingerprint != connectionFingerprint || cache.isEmpty { cursor=0; cache=[:] }
        while true {
            let page=(try await request("/rest/v1/cs_records?select=*&change_id=gt.\(cursor)&order=change_id&limit=200",method:"GET") as? [[String:Any]]) ?? []
            for row in page { guard let id=row["id"] as? String else { continue }; cursor=max(cursor,row["change_id"] as? Int ?? 0); if row["deleted"] as? Bool == true { cache.removeValue(forKey:id); if (row["owner_id"] as? String)?.lowercased()==actor { deletedRemotely.insert(id.lowercased()) } } else { cache[id]=row } }
            if page.count<200 { break }
        }
        var permitted=Set<String>(); var after="00000000-0000-0000-0000-000000000000"
        while true {
            let page=(try await rpc("cs_visible_manifest",["p_after":after,"p_limit":200]) as? [[String:Any]]) ?? []
            for row in page { if let id=row["id"] as? String { permitted.insert(id); after=id } }
            if page.count<200 { break }
        }
        let people=try await allRows("cs_participants",order:"record_id,id")
        let messages=try await allRows("cs_feedback")
        let confirmations=try await allRows("cs_notifications")
        let preferences=(try await request("/rest/v1/cs_notification_preferences?select=*&limit=1",method:"GET") as? [[String:Any]])?.first ?? [:]
        guard actor==accountID else { return }
        state["remoteDeletedIDs"]=Array(deletedRemotely); try persist()
        connections=latest; records=cache.filter { permitted.contains($0.key) }.values.sorted { ($0["occurred_at"] as? String ?? "") > ($1["occurred_at"] as? String ?? "") }
        recordCursor=cursor; connectionFingerprint=fingerprint; participants=people; feedback=messages; notifications=confirmations; notificationSettings=preferences
        status="Sharing access refreshed."
    }
    func register(_ player: PlayerProfile) async throws {
        try await rpc("cs_register_profile",["p_id":player.id.uuidString,"p_name":player.displayName])
    }
    func invite(role: String, player: PlayerProfile?, sport: String, recipient: String) async throws -> String {
        if let player { try await register(player) }
        let result = try await rpc("cs_create_invitation",["p_role":role,"p_player":role == "player" ? (player?.id.uuidString as Any? ?? NSNull()) : NSNull(),"p_sport":sport,"p_recipient":recipient]) as? [String:Any]
        guard let code = result?["code"] as? String else { throw CourtConnectError.message("Invitation was not created.") }
        return linkHost.isEmpty ? code : "https://"+linkHost+"/connect/invite#"+code
    }
    func clearPending(_ code: String) {
        guard CourtConnectProtocol.code(pendingCode,host:linkHost)==code else { return }
        pendingCode=""; UserDefaults.standard.removeObject(forKey:"CourtConnectPendingInvitation")
    }
    @discardableResult func accept(_ input: String, player: PlayerProfile?) async throws -> String {
        guard let code = CourtConnectProtocol.code(input,host:linkHost) else { throw CourtConnectError.message("Use the complete invitation link or 64-character code.") }
        if let player { try await register(player) }
        let receipt = try await rpc("cs_respond_invitation",["p_code":code,"p_response":"accept","p_player":player?.id.uuidString as Any? ?? NSNull()]) as? [String:Any] ?? [:]
        guard let connectionID=receipt["connection_id"] as? String, !connectionID.isEmpty else { throw CourtConnectError.message("The invitation response could not be confirmed. Please try again.") }
        clearPending(code)
        try await refresh(); status = "Invitation accepted. The player can now approve sharing."
        return connectionID
    }
    func preview(_ input: String) async throws -> [String:Any] {
        guard let code=CourtConnectProtocol.code(input,host:linkHost) else { throw CourtConnectError.message("Use the full invitation link or 64-character code.") }
        return try await rpc("cs_review_invitation",["p_code":code]) as? [String:Any] ?? [:]
    }
    func decline(_ input: String) async throws {
        guard let code=CourtConnectProtocol.code(input,host:linkHost) else { throw CourtConnectError.message("Invalid invitation link or code.") }
        try await rpc("cs_respond_invitation",["p_code":code,"p_response":"decline"]); clearPending(code)
        status="Invitation declined. Nothing is shared."
    }
    func saveNotifications(push: Bool,requests: Bool,sharing: Bool,feedback: Bool) async throws {
        var permitted=push
        if push { permitted = try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge]) }
        try await rpc("cs_set_notifications",["p_push":permitted,"p_requests":requests,"p_sharing":sharing,"p_feedback":feedback])
        if permitted { UIApplication.shared.registerForRemoteNotifications() }
        else {
            if let installation=UserDefaults.standard.string(forKey:"CourtConnectInstallation") { try await rpc("cs_unregister_device",["p_installation":installation]) }
            UIApplication.shared.unregisterForRemoteNotifications()
        }
        try await refresh()
        status=push && !permitted ? "Push is disabled in iPhone Settings. Confirmations remain available inside Connect." : "Connect notification settings saved."
    }
    func shouldPresentNotification(_ id: String) async -> Bool {
        guard isSignedIn else { return false }
        do { try await refresh() } catch { return false }
        guard notificationSettings["push_enabled"] as? Bool == true, let row=notifications.first(where:{$0["id"] as? String == id}) else { return false }
        let kind=row["kind"] as? String ?? ""
        let key=kind == "coach_feedback" ? "coach_feedback" : kind == "connection_request" ? "connection_requests" : "sharing_confirmations"
        guard notificationSettings[key] as? Bool != false else { return false }
        if kind=="sharing_started" { return connections.contains { $0["id"] as? String == row["connection_id"] as? String && $0["state"] as? String == "active" && !(($0["categories"] as? [String] ?? []).isEmpty) } }
        return true
    }
    func registeredForPush(_ token: Data) {
        guard isSignedIn else { return }
        let defaults=UserDefaults.standard
        let installation=defaults.string(forKey:"CourtConnectInstallation") ?? UUID().uuidString
        defaults.set(installation,forKey:"CourtConnectInstallation")
        let value=token.map { String(format:"%02x",$0) }.joined()
        Task { do { try await rpc("cs_register_device",["p_installation":installation,"p_platform":"apns","p_token":value]) }
            catch { status="Push registration needs attention. " + error.localizedDescription } }
    }
    func permission(id: String,state: String,categories: [String],history: String,start: Date,end: Date,future: Bool,capability: String) async throws {
        let iso = ISO8601DateFormatter()
        try await rpc("cs_set_permission",["p_id":id,"p_state":state,"p_categories":categories,"p_history":history,
            "p_start":history == "period" ? iso.string(from:start) as Any : NSNull(),"p_end":history == "period" ? iso.string(from:end) as Any : NSNull(),"p_future":future,"p_capability":capability])
        try await refresh()
        status = state == "revoked" ? "Access revoked on the server. Previously saved copies cannot necessarily be erased remotely." : "Sharing permission saved."
    }
    func run(_ action: @escaping () async throws -> Void) {
        guard !busy else { return }; busy = true
        Task { do { try await action() } catch { status = error.localizedDescription }; busy = false }
    }
    func enableUploads(for player: PlayerProfile, library: AppData) async throws {
        try await register(player)
        let libraryID=library.libraryID.uuidString.lowercased()
        if state["libraryID"] as? String != libraryID {
            for key in ["queue","hashes","revisions","uploaded","uploadPlayers"] { state.removeValue(forKey:key) }
        }
        state["libraryID"]=libraryID
        var allowed = state["uploadPlayers"] as? [String] ?? []
        if !allowed.contains(player.id.uuidString.lowercased()) { allowed.append(player.id.uuidString.lowercased()) }
        state["uploadPlayers"] = allowed; try persist()
        try await sync(library)
    }
    func linkedPlayer(_ remote: String) -> String? { (state["linkedPlayers"] as? [String:String])?[remote.lowercased()] }
    func linkPlayer(_ remote: String, local: String?) throws {
        var links=state["linkedPlayers"] as? [String:String] ?? [:]
        if let local, links.contains(where:{$0.key != remote.lowercased() && $0.value==local.lowercased()}) { throw CourtConnectError.message("This local profile is already linked to another online player. Review that link first.") }
        links[remote.lowercased()]=local?.lowercased(); state["linkedPlayers"]=links; try persist()
        status="Local profile link saved. Online and local histories remain separate; no records were merged."
    }
    func isPrivate(_ id: String) -> Bool { (state["privateRecords"] as? [String:Bool] ?? [:])[id.lowercased()] ?? false }
    func setPrivate(_ id: String, private value: Bool, library: AppData) async throws {
        var values=state["privateRecords"] as? [String:Bool] ?? [:]; values[id.lowercased()]=value; state["privateRecords"]=values; state["queue"]=(state["queue"] as? [[String:Any]] ?? []).filter { ($0["p_id"] as? String)?.lowercased() != id.lowercased() }; try persist()
        if let remote=records.first(where:{ ($0["id"] as? String)?.lowercased()==id.lowercased() }) {
            let revision=try await rpc("cs_set_record_private",["p_id":id,"p_private":value,"p_expected":remote["revision"] ?? 0])
            var revisions=state["revisions"] as? [String:Int] ?? [:]; revisions[id.lowercased()]=revision as? Int; state["revisions"]=revisions; try persist()
        }
        try await sync(library)
        status=value ? "Record kept private. Server access is removed; previously saved copies cannot necessarily be erased." : "Record eligible for the sharing permissions you approve."
    }
    func stopUploads() throws {
        state["uploadPlayers"] = [String](); state["queue"] = [[String:Any]](); try persist()
        status = "Uploads paused on this device. Use Revoke to remove existing server access."
    }
    static func scheduleBackground() {
        guard shared.isSignedIn else { return }
        let request=BGAppRefreshTaskRequest(identifier:"com.inclusophy.tennistracker.connect-refresh"); request.earliestBeginDate=Date(timeIntervalSinceNow:900)
        try? BGTaskScheduler.shared.submit(request)
    }
    func changed(_ library: AppData) {
        guard isSignedIn, !(state["uploadPlayers"] as? [String] ?? []).isEmpty else { return }
        Task { do { try await sync(library) } catch { status = "Sync needs attention. " + error.localizedDescription } }
    }
    private func permits(_ record: [String:Any]) -> Bool {
        if (state["remoteDeletedIDs"] as? [String] ?? []).contains((record["p_id"] as? String ?? "").lowercased()) { return false }
        guard let player = record["p_player"] as? String, let sport = record["p_sport"] as? String,
              let category = record["p_category"] as? String, let date = record["p_occurred"] as? String else { return false }
        return connections.contains { c in
            guard (c["player_account"] as? String)?.lowercased() == accountID,
                  (c["player_id"] as? String)?.lowercased() == player.lowercased(), c["sport"] as? String == sport,
                  c["state"] as? String == "active", (c["categories"] as? [String] ?? []).contains(category) else { return false }
            let when = Self.parseDate(date); let approved = Self.parseDate(c["approved_at"] as? String ?? "")
            if !((c["future_sharing"] as? Bool) ?? false) && when > approved { return false }
            switch c["history"] as? String {
            case "all": return true
            case "period": return when >= Self.parseDate(c["history_start"] as? String ?? "") && when <= Self.parseDate(c["history_end"] as? String ?? "")
            default: return when >= approved
            }
        }
    }
    static func parseDate(_ string: String) -> Date {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        if let date = parser.date(from:string) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from:string) ?? .distantPast
    }
    static func projections(_ data: AppData, players: [String]) throws -> [[String:Any]] {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let library = (try JSONSerialization.jsonObject(with:encoder.encode(data)) as? [String:Any]) ?? [:]
        var output: [[String:Any]] = []
        var scoreSummaries: [String:String]=[:]
        for match in data.matches { if let score=match.court.score { scoreSummaries[match.id.uuidString.lowercased()]=score.summary + ". " + score.resultSummary } }
        for (table,category) in [("matches","match"),("trainingSessions","training"),("tournaments","tournament")] {
            for row in library[table] as? [[String:Any]] ?? [] {
                guard let id = row["id"] as? String, let player = row["playerID"] as? String,
                      players.contains(player.lowercased()), let date = row["date"] as? String else { continue }
                let court = (row["court"] as? [String:Any]) ?? [:]; let selection = (court["sport"] as? [String:Any]) ?? [:]
                let sport = (selection["sport"] as? String) ?? "Tennis"
                let key = sport == "Custom" ? "custom:"+(selection["customName"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines).lowercased() : sport
                // Deliberately do not encode workout, health, wellness, media, location, disability or the full record.
                var body: [String:Any] = ["title":(row["name"] as? String) ?? (row["trainingType"] as? String) ?? "Match"]
                if category == "match" { body["score"] = row["setScores"] as? String ?? ""; body["result"] = row["result"] as? String ?? "" }
                if category == "training" { body["focus"] = row["focus"] as? String ?? ""; body["duration_minutes"] = row["durationMinutes"] as? Int ?? 0 }
                for key in ["status", "matchType", "matchFormat", "yourSetsWon", "opponentSetsWon", "aces", "doubleFaults", "winners", "unforcedErrors", "hadTiebreak", "tiebreakScore", "tournamentID", "trainingSessionID", "finalResult", "matchesPlayed", "format", "stageReached", "finishingPosition", "endDate"] {
                    if let value=row[key], value is String || value is NSNumber { body[key]=value }
                }
                if category == "match", let summary=scoreSummaries[id.lowercased()] { body["customScoreSummary"]=summary }
                for field in ["surface","sessionType"] { if let value=court[field] as? String, !value.isEmpty { body[field]=value } }
                let plan=court["plan"] as? [String:Any] ?? [:]
                for (source,destination) in [("objective","planObjective"),("drills","planDrills"),("equipment","planEquipment"),("successMeasure","planSuccessMeasure")] {
                    if let value=plan[source] as? String, !value.isEmpty { body[destination]=value }
                }
                var record: [String:Any] = ["p_id":id.lowercased(),"p_player":player.lowercased(),"p_sport":key,"p_category":category,"p_occurred":date,"p_body":body,"p_private":false,"p_deleted":false]
                if category=="match", let uuid=UUID(uuidString:id) {
                    var people: [[String:Any]]=[]
                    for (key,team) in [("playerName",0),("partnerName",0),("opponentName",1),("opponent2Name",1)] {
                        if let name=row[key] as? String, !name.isEmpty { people.append(["id":CourtConnectProtocol.derivedID(uuid,category:key).uuidString.lowercased(),"display_name":name,"team":team]) }
                    }
                    if let score=court["score"] as? [String:Any], let sides=score["sides"] as? [[String:Any]], !sides.isEmpty {
                        people=[]
                        for (team,side) in sides.enumerated() {
                            let names=(side["members"] as? [String] ?? []).filter { !$0.isEmpty }
                            for (member,name) in (names.isEmpty ? [side["name"] as? String ?? "Team"] : names).enumerated() {
                                let sideID=(side["id"] as? String ?? String(team)).lowercased()
                                people.append(["id":CourtConnectProtocol.derivedID(uuid,category:"score-side-"+sideID+"-member-"+String(member)).uuidString.lowercased(),"display_name":name,"team":team])
                            }
                        }
                    }
                    record["p_people"]=people
                }
                output.append(record)
                if let uuid=UUID(uuidString:id) {
                    let reflectionKeys=category == "match" ? ["matchStory","matchStrengths","matchNeedsWork","pressureMoment"] : ["sessionOutcome"]
                    let reflection=(reflectionKeys.compactMap { row[$0] as? String } + [plan["review"] as? String ?? ""]).filter { !$0.isEmpty }.joined(separator:"\n")
                    let goalKeys=category == "tournament" ? ["goal"] : ["nextPracticeFocus"]
                    let goal=goalKeys.compactMap { row[$0] as? String }.filter { !$0.isEmpty }.joined(separator:"\n")
                    for (derivedCategory,text) in [("reflection",reflection),("goal",goal)] where !text.isEmpty {
                        var derived=record; derived["p_people"]=[[String:Any]](); derived["p_id"]=CourtConnectProtocol.derivedID(uuid,category:derivedCategory).uuidString.lowercased(); derived["p_category"]=derivedCategory; derived["p_body"]=["text":text]; output.append(derived)
                    }
                }
                if let notes = row["notes"] as? String, !notes.isEmpty, let uuid = UUID(uuidString:id) {
                    var note = record; note["p_people"]=[[String:Any]](); note["p_id"] = CourtConnectProtocol.noteID(uuid).uuidString.lowercased(); note["p_category"] = "note"; note["p_body"] = ["text":notes]
                    output.append(note)
                }
            }
        }
        func appendText(id: UUID, player: UUID, sport: CourtSportSelection, category: String, date: Date, title: String, text: String) {
            guard players.contains(player.uuidString.lowercased()), !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
            output.append(["p_id":id.uuidString.lowercased(),"p_player":player.uuidString.lowercased(),"p_sport":sport.id,"p_category":category,"p_occurred":ISO8601DateFormatter().string(from:date),"p_body":["title":title,"text":text],"p_private":false,"p_deleted":false,"p_people":[[String:Any]]()])
        }
        for profile in data.players where players.contains(profile.id.uuidString.lowercased()) {
            for preferences in profile.court.sports {
                let sport=preferences.sport
                appendText(id:CourtConnectProtocol.derivedID(profile.id,category:"profile-goal:"+sport.id),player:profile.id,sport:sport,category:"goal",date:profile.court.modifiedAt,title:"Development goal",text:preferences.primaryGoal)
                appendText(id:CourtConnectProtocol.derivedID(profile.id,category:"profile-note:"+sport.id),player:profile.id,sport:sport,category:"note",date:profile.court.modifiedAt,title:"Development notes",text:preferences.developmentNotes)
            }
        }
        for observation in data.court.observations where !data.court.deletedIDs.contains(observation.id) {
            let text=[("Focus",observation.focus),("Observation",observation.happened),("Interpretation",observation.interpretation),("Player perspective",observation.playerPerspective)].filter { !$0.1.isEmpty }.map { $0.0+": "+$0.1 }.joined(separator:"\n")
            appendText(id:observation.id,player:observation.athleteID,sport:observation.sport,category:"reflection",date:observation.date,title:"Coaching observation",text:text)
            appendText(id:CourtConnectProtocol.derivedID(observation.id,category:"goal"),player:observation.athleteID,sport:observation.sport,category:"goal",date:observation.date,title:"Next action",text:observation.nextAction)
        }
        for drill in data.court.drills where !data.court.deletedIDs.contains(drill.id) {
            var parts=[drill.summary,"Focus: "+drill.focus,"Setup: "+drill.setup,"Conditions: "+drill.conditions]
            if let measurement=drill.measurement { parts.append("Measurement: \(measurement) "+drill.unit) }
            appendText(id:drill.id,player:drill.athleteID,sport:drill.sport,category:"training",date:drill.date,title:drill.name,text:parts.joined(separator:"\n"))
        }
        return output
    }
    var syncConflicts: [[String:Any]] {
        (state["queue"] as? [[String:Any]] ?? []).filter { queued in
            records.contains { remote in remote["id"] as? String == queued["p_id"] as? String && (remote["revision"] as? Int ?? 0) > (queued["p_expected"] as? Int ?? 0) }
        }
    }
    func resolveConflict(_ id: String, useDevice: Bool) throws {
        guard let remote=records.first(where: { $0["id"] as? String == id }), remote["owner_id"] as? String == accountID else { throw CourtConnectError.message("Refresh this record before reviewing the conflict.") }
        var queue=state["queue"] as? [[String:Any]] ?? []
        guard let index=queue.firstIndex(where: { $0["p_id"] as? String == id }) else { return }
        var revisions=state["revisions"] as? [String:Int] ?? [:]; revisions[id]=remote["revision"] as? Int
            if remote["private"] as? Bool == true {
                var privacy=state["privateRecords"] as? [String:Bool] ?? [:]; privacy[id]=true; state["privateRecords"]=privacy; queue[index]["p_private"]=true
                var sporting=queue[index]; sporting.removeValue(forKey:"p_expected"); sporting.removeValue(forKey:"p_operation"); sporting.removeValue(forKey:"local_hash")
                queue[index]["local_hash"]=SHA256.hash(data:try JSONSerialization.data(withJSONObject:sporting,options:.sortedKeys)).map { String(format:"%02x",$0) }.joined()
            }
        if useDevice {
            guard remote["deleted"] as? Bool != true else { throw CourtConnectError.message("A deleted online record cannot be restored by a queued edit.") }
            queue[index]["p_expected"]=remote["revision"]; queue[index]["p_operation"]=UUID().uuidString

        } else {
            var hashes=state["hashes"] as? [String:String] ?? [:]; hashes[id]=queue[index]["local_hash"] as? String; state["hashes"]=hashes; if queue[index]["p_deleted"] as? Bool == true { var uploaded=state["uploaded"] as? [String:[String:Any]] ?? [:]; uploaded.removeValue(forKey:id); state["uploaded"]=uploaded }; queue.remove(at:index)
        }
        state["revisions"]=revisions; state["queue"]=queue; try persist()
        status=useDevice ? "Reviewed device version queued. Retry sync to send it with a fresh version check." : "Online version kept. Your local record remains unchanged."
    }
    var pendingFeedback: [[String:Any]] { state["feedbackQueue"] as? [[String:Any]] ?? [] }
    func queueFeedback(_ request: [String:Any]) throws {
        guard isSignedIn, let text=request["p_text"] as? String, (1...4000).contains(text.count), !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw CourtConnectError.message("Enter feedback of up to 4,000 characters.") }
        var queue=pendingFeedback; queue.append(request); state["feedbackQueue"]=queue; try persist()
        status="Feedback saved to the outgoing queue. It will be sent when connected and sharing is still permitted."
        Self.scheduleBackground()
    }
    func discardFeedback(_ id: String) throws {
        state["feedbackQueue"]=pendingFeedback.filter { $0["p_id"] as? String != id }; try persist(); status="Queued feedback removed."
    }
    private func flushFeedback() async throws {
        let actor=accountID
        while let request=pendingFeedback.first {
            try await rpc("cs_add_feedback",request)
            guard actor==accountID else { return }
            state["feedbackQueue"]=Array(pendingFeedback.dropFirst()); try persist()
        }
    }
    func sync(_ requestedLibrary: AppData) async throws {
        guard isSignedIn else { return }
        if syncing { pendingLibrary=requestedLibrary; return }
        syncing=true
        var completed=false
        defer { syncing=false; let next=pendingLibrary; pendingLibrary=nil; if completed, let next { changed(next) } }
        // Read the saved library afresh. An older screen snapshot must never delete newer records.
        let savedURL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("TennisTracker/tennis-tracker-data.json")
        let library=try TennisBackup.decodeStoredLibrary(Data(contentsOf:savedURL))
        Self.scheduleBackground()
        let actor = accountID
        let players = state["uploadPlayers"] as? [String] ?? []
        if !players.isEmpty && state["libraryID"] as? String != library.libraryID.uuidString.lowercased() { throw CourtConnectError.message("Your local library changed. Review the selected profile and approve uploads again; online records have not been deleted.") }
        var queue = state["queue"] as? [[String:Any]] ?? []
        var hashes = (state["hashes"] as? [String:String]) ?? [:]
        var revisions = (state["revisions"] as? [String:Int]) ?? [:]
        var uploaded=state["uploaded"] as? [String:[String:Any]] ?? [:]
        let projections = try Self.projections(library,players:players).map { record -> [String:Any] in var result=record; result["p_private"]=isPrivate(record["p_id"] as? String ?? ""); return result }
        for candidate in projections where permits(candidate) {
            let id = candidate["p_id"] as! String
            let hash = SHA256.hash(data:try JSONSerialization.data(withJSONObject:candidate,options:.sortedKeys)).map { String(format:"%02x",$0) }.joined()
            if let prior=queue.first(where:{ $0["p_id"] as? String == id }) { if prior["local_hash"] as? String != hash { pendingLibrary=library }; continue }
            guard hashes[id] != hash else { continue }
            var queued = candidate; queued["p_operation"] = UUID().uuidString; queued["p_expected"] = revisions[id] ?? 0; queued["local_hash"] = hash
            queue.append(queued)
        }
        let present=Set(projections.compactMap { $0["p_id"] as? String })
        for (id,metadata) in uploaded where !(state["remoteDeletedIDs"] as? [String] ?? []).contains(id) && !present.contains(id) && players.contains(metadata["p_player"] as? String ?? "") && !queue.contains(where:{ $0["p_id"] as? String == id }) {
            var tombstone=metadata; tombstone["p_body"]=[String:String](); tombstone["p_people"]=[[String:Any]](); tombstone["p_deleted"]=true; tombstone["p_private"]=true; tombstone["p_operation"]=UUID().uuidString; tombstone["p_expected"]=revisions[id] ?? 0; tombstone["local_hash"]="deleted"; queue.append(tombstone)
        }
        state["queue"]=queue; try persist()
        // Build the durable queue before network access, then recheck server permission before sending.
        try await refresh(); guard actor==accountID else { return }; try await flushFeedback()
        queue=queue.filter { !(state["remoteDeletedIDs"] as? [String] ?? []).contains(($0["p_id"] as? String ?? "").lowercased()) && (($0["p_deleted"] as? Bool == true) || permits($0)) }
        state["queue"]=queue; try persist()
        while !queue.isEmpty {
            guard actor == accountID else { return }
            var item = queue[0]; let hash = item.removeValue(forKey:"local_hash") as? String; let id = item["p_id"] as! String
            let response = (try await rpc("cs_put_record",item) as? [String:Any]) ?? [:]
            guard actor == accountID else { return }
            hashes[id] = hash; revisions[id] = response["revision"] as? Int
            if item["p_deleted"] as? Bool == true { uploaded.removeValue(forKey:id) }
            else { var metadata=item; metadata.removeValue(forKey:"p_body"); metadata.removeValue(forKey:"p_people"); metadata.removeValue(forKey:"p_expected"); metadata.removeValue(forKey:"p_operation"); uploaded[id]=metadata }
            state["uploaded"]=uploaded
            queue.removeFirst(); state["queue"] = queue; state["hashes"] = hashes; state["revisions"] = revisions; try persist()
        }
        try await refresh()
        for record in projections where permits(record) {
            let hash=SHA256.hash(data:try JSONSerialization.data(withJSONObject:record,options:.sortedKeys)).map { String(format:"%02x",$0) }.joined()
            if hashes[record["p_id"] as? String ?? ""] != hash { pendingLibrary=library; break }
        }
        completed=true
        status = "Permitted sporting records synchronised. Health and media stay on the device."
    }
}
