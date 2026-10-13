import Foundation
import Security
import CryptoKit

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
            guard url.scheme == "https", url.host == host, url.path == "/connect/invite", url.user == nil,
                  url.password == nil, url.port == nil, url.query == nil else { return nil }
            candidate = url.fragment ?? ""
        } else { candidate = text }
        return candidate.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil ? candidate : nil
    }
    static func noteID(_ id: UUID) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(("court-story-note:" + id.uuidString.lowercased()).utf8)).prefix(16))
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
    @Published private(set) var feedback: [[String: Any]] = []
    @Published var status = "Local-only. Nothing is uploaded until you approve sharing."
    @Published var pendingCode = ""
    @Published private(set) var busy = false
    private var state: [String: Any] = [:]
    private var syncing = false
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
        let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        try data.write(to: stateURL, options: [.atomic, .completeFileProtection])
    }
    private func saveSession(_ newSession: CourtConnectSession) throws {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:keychainService]
        let data = try JSONEncoder().encode(newSession)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String:data] as CFDictionary)
        if result == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary,nil) == errSecSuccess else { throw CourtConnectError.message("Could not securely save sign-in.") }
        } else if result != errSecSuccess { throw CourtConnectError.message("Could not securely save sign-in.") }
        let changed = accountID != newSession.user.id.lowercased()
        session = newSession
        if changed { records = []; feedback = []; connections = []; loadState() }
    }
    func signOut() {
        SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:keychainService] as CFDictionary)
        session = nil; records = []; feedback = []; connections = []; state = [:]
        status = "Signed out. Your local sporting records are unchanged."
    }
    func receive(_ url: URL) -> Bool {
        guard !linkHost.isEmpty, let code = CourtConnectProtocol.code(url.absoluteString, host: linkHost) else { return false }
        pendingCode = code; UserDefaults.standard.set(code, forKey:"CourtConnectPendingInvitation"); return true
    }
    private func request(_ path: String, method: String = "POST", body: [String:Any]? = nil, authenticated: Bool = true, retry: Bool = true) async throws -> Any {
        guard let base = config["supabase_url"], let origin = URL(string: base), origin.scheme == "https",
              let key = config["publishable_key"], !key.isEmpty, let url = URL(string: base + path) else {
            throw CourtConnectError.message("Court Story Connect service configuration is unavailable. Local tracking remains available.")
        }
        if authenticated && session == nil { throw CourtConnectError.message("Sign in to Court Story Connect first.") }
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
            throw CourtConnectError.message(http.statusCode == 429 ? "Please wait before trying again." : "The request was not accepted. Check sign-in, invitation expiry and sharing permission.")
        }
        if data.isEmpty { return NSNull() }
        return try JSONSerialization.jsonObject(with:data,options:.fragmentsAllowed)
    }
    @discardableResult func rpc(_ name: String, _ parameters: [String:Any]) async throws -> Any { try await request("/rest/v1/rpc/"+name,body:parameters) }
    func sendCode(email: String) async throws {
        _ = try await request("/auth/v1/otp",body:["email":email,"create_user":true],authenticated:false)
        status = "Check your email for the sign-in code. Signing in does not upload your records."
    }
    func verify(email: String, code: String) async throws {
        let response = try await request("/auth/v1/verify",body:["email":email,"token":code,"type":"email"],authenticated:false)
        try saveSession(JSONDecoder().decode(CourtConnectSession.self,from:JSONSerialization.data(withJSONObject:response)))
        try await refresh(); status = "Signed in. Choose a player and approve sharing to upload sporting records."
    }
    private func allRows(_ table: String) async throws -> [[String:Any]] {
        var rows: [[String:Any]] = []; var offset = 0
        while true {
            let next = try await request("/rest/v1/"+table+"?select=*&order=id&limit=200&offset=\(offset)",method:"GET") as? [[String:Any]] ?? []
            rows += next; if next.count < 200 { return rows }; offset += next.count
        }
    }
    func refresh() async throws {
        guard isSignedIn else { return }
        // Rebuild the authorised view instead of retaining rows which may have been revoked.
        records = []; feedback = []
        connections = try await allRows("cs_connections")
        records = try await allRows("cs_records").filter { !(($0["deleted"] as? Bool) ?? false) }
        feedback = try await allRows("cs_feedback")
        status = "Sharing access refreshed."
    }
    func register(_ player: PlayerProfile) async throws {
        try await rpc("cs_register_profile",["p_id":player.id.uuidString,"p_name":player.displayName])
    }
    func invite(role: String, player: PlayerProfile?, sport: String, recipient: String) async throws -> String {
        if role == "player", let player { try await register(player) }
        let result = try await rpc("cs_create_invitation",["p_role":role,"p_player":role == "player" ? (player?.id.uuidString as Any? ?? NSNull()) : NSNull(),"p_sport":sport,"p_recipient":recipient]) as? [String:Any]
        guard let code = result?["code"] as? String else { throw CourtConnectError.message("Invitation was not created.") }
        return linkHost.isEmpty ? code : "https://"+linkHost+"/connect/invite#"+code
    }
    func accept(_ input: String, player: PlayerProfile?) async throws {
        guard let code = CourtConnectProtocol.code(input,host:linkHost) else { throw CourtConnectError.message("Use the complete invitation link or 64-character code.") }
        if let player { try await register(player) }
        try await rpc("cs_accept_invitation",["p_code":code,"p_player":player?.id.uuidString as Any? ?? NSNull()])
        pendingCode = ""; UserDefaults.standard.removeObject(forKey:"CourtConnectPendingInvitation")
        try await refresh(); status = "Invitation accepted. Sharing starts only after player approval."
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
        var allowed = state["uploadPlayers"] as? [String] ?? []
        if !allowed.contains(player.id.uuidString.lowercased()) { allowed.append(player.id.uuidString.lowercased()) }
        state["uploadPlayers"] = allowed; try persist()
        try await sync(library)
    }
    func stopUploads() throws {
        state["uploadPlayers"] = [String](); state["queue"] = [[String:Any]](); try persist()
        status = "Uploads paused on this device. Use Revoke to remove existing server access."
    }
    func changed(_ library: AppData) {
        guard isSignedIn, !(state["uploadPlayers"] as? [String] ?? []).isEmpty else { return }
        Task { do { try await sync(library) } catch { status = "Sync needs attention. " + error.localizedDescription } }
    }
    private func permits(_ record: [String:Any]) -> Bool {
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
                if category == "training" { body["focus"] = row["focus"] as? String ?? "" }
                let record: [String:Any] = ["p_id":id.lowercased(),"p_player":player.lowercased(),"p_sport":key,"p_category":category,"p_occurred":date,"p_body":body,"p_private":false,"p_deleted":false]
                output.append(record)
                if let notes = row["notes"] as? String, !notes.isEmpty, let uuid = UUID(uuidString:id) {
                    var note = record; note["p_id"] = CourtConnectProtocol.noteID(uuid).uuidString.lowercased(); note["p_category"] = "note"; note["p_body"] = ["text":notes]
                    output.append(note)
                }
            }
        }
        return output
    }
    func sync(_ library: AppData) async throws {
        guard !syncing, isSignedIn else { return }; syncing = true; defer { syncing = false }
        let actor = accountID
        // Fetch current permissions BEFORE flushing an offline queue. Revocation or pause invalidates queued uploads.
        try await refresh()
        guard actor == accountID else { return }
        let players = state["uploadPlayers"] as? [String] ?? []
        var queue = state["queue"] as? [[String:Any]] ?? []
        var hashes = (state["hashes"] as? [String:String]) ?? [:]
        var revisions = (state["revisions"] as? [String:Int]) ?? [:]
        let projections = try Self.projections(library,players:players)
        for candidate in projections where permits(candidate) {
            let id = candidate["p_id"] as! String
            let hash = SHA256.hash(data:try JSONSerialization.data(withJSONObject:candidate,options:.sortedKeys)).map { String(format:"%02x",$0) }.joined()
            guard hashes[id] != hash, !queue.contains(where:{ $0["p_id"] as? String == id }) else { continue }
            var queued = candidate; queued["p_operation"] = UUID().uuidString; queued["p_expected"] = revisions[id] ?? 0; queued["local_hash"] = hash
            queue.append(queued)
        }
        queue = queue.filter { permits($0) }
        state["queue"] = queue; try persist()
        while !queue.isEmpty {
            guard actor == accountID else { return }
            var item = queue[0]; let hash = item.removeValue(forKey:"local_hash") as? String; let id = item["p_id"] as! String
            let response = (try await rpc("cs_put_record",item) as? [String:Any]) ?? [:]
            guard actor == accountID else { return }
            hashes[id] = hash; revisions[id] = response["revision"] as? Int
            queue.removeFirst(); state["queue"] = queue; state["hashes"] = hashes; state["revisions"] = revisions; try persist()
        }
        try await refresh(); status = "Permitted sporting records synchronised. Health and media stay on the device."
    }
}
