import Foundation

struct TennisActivityRoute: Hashable, Identifiable {
    enum Kind: String { case training, match, tournament, weekly, achievements }
    enum Action: String { case details, reflection, result, live }
    let kind: Kind
    var recordID: UUID?
    var action: Action = .details
    var weekStart: Date?
    var id: String { url.absoluteString }

    init(kind: Kind, recordID: UUID? = nil, action: Action = .details, weekStart: Date? = nil) {
        self.kind = kind; self.recordID = recordID; self.action = action; self.weekStart = weekStart
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == "tennistracker",
              let host = url.host?.lowercased(), let kind = Kind(rawValue: host == "live" ? "match" : host) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        self.kind = kind
        if [.training, .match, .tournament].contains(kind) {
            guard let first = parts.first, let id = UUID(uuidString: first), parts.count <= 2 else { return nil }
            recordID = id
            if parts.count == 2 {
                guard let intent = Action(rawValue: parts[1]) else { return nil }
                action = intent
            } else if host == "live" { action = .live }
            guard action == .details || (kind == .training && action == .reflection) ||
                (kind == .match && [.result, .live].contains(action)) else { return nil }
        } else {
            guard parts.isEmpty else { return nil }
            if let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "start" })?.value {
                guard kind == .weekly, let seconds = Double(text), seconds.isFinite, seconds > 0, seconds <= 253_402_300_799 else { return nil }
                weekStart = Date(timeIntervalSince1970: seconds)
            }
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "tennistracker"; components.host = kind.rawValue
        if let recordID { components.path = "/" + recordID.uuidString + (action == .details ? "" : "/" + action.rawValue) }
        if let weekStart { components.queryItems = [URLQueryItem(name: "start", value: String(Int(weekStart.timeIntervalSince1970)))] }
        return components.url!
    }

    static func notificationURL(userInfo: [AnyHashable: Any], identifier: String, deliveredAt: Date = Date()) -> URL? {
        guard let text = userInfo["url"] as? String, let url = URL(string: text), url.scheme == "tennistracker" else { return nil }
        if identifier == "weekly-summary" {
            if let route = Self(url: url), route.kind == .weekly { return route.url }
            let monday = TennisReportingWeek.interval(containing: deliveredAt).start
            let previous = Calendar.current.date(byAdding: .day, value: -7, to: monday) ?? monday
            return Self(kind: .weekly, weekStart: previous).url
        }
        guard var route = Self(url: url) else { return nil }
        // Upgrade reminders delivered by an older build, which omitted their editing intent.
        if identifier.hasPrefix("training-reflection-"), route.kind == .training { route.action = .reflection }
        if identifier.hasPrefix("match-result-"), route.kind == .match { route.action = .result }
        return route.url
    }
}

enum TennisNotificationInbox {
    private static let key = "pendingTennisNotificationURL"
    static func enqueue(_ url: URL, defaults: UserDefaults = .standard) {
        guard TennisActivityRoute(url: url) != nil else { return }
        defaults.set(url.absoluteString, forKey: key)
    }
    static func take(defaults: UserDefaults = .standard) -> URL? {
        guard let text = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        guard let url = URL(string: text), TennisActivityRoute(url: url) != nil else { return nil }
        return url
    }
}

extension Notification.Name {
    static let tennisTrackerOpenURL = Notification.Name("tennisTrackerOpenURL")
}
