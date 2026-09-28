import Foundation

struct TennisGlance: Equatable {
    var title: String
    var detail: String
    var accessibilitySummary: String
    var destination: TennisWatchPage
    var isStale: Bool
    var compactDetail: String = ""
    var actionURL: URL?
    var url: URL { actionURL ?? destination.url }

    var circularDetail: String { compactDetail.isBlank ? detail : compactDetail }
    var relevanceScore: Float { isStale ? 0 : destination == .score || destination == .live ? 10 : destination == .today ? 5 : 0 }

    static func make(snapshot: TennisWatchSnapshot, now: Date = Date()) -> Self {
        let matches = snapshot.matches.filter { snapshot.selectedPlayerID == nil || $0.playerID == snapshot.selectedPlayerID }
        let training = snapshot.trainingSessions.filter { snapshot.selectedPlayerID == nil || $0.playerID == snapshot.selectedPlayerID }
        if let match = matches.filter({ $0.status == .inProgress }).max(by: { $0.modifiedAt < $1.modifiedAt }) {
            let stale = now.timeIntervalSince(match.modifiedAt) > 6 * 3600
            let names = [match.playerName.fallback("Player"), match.matchType == .doubles ? match.partnerName.fallback("Partner") : ""]
            let compactTeam = names.filter { !$0.isBlank }.map { String($0.split(separator: " ").first?.prefix(3) ?? "") }.joined(separator: "/")
            return Self(title: stale ? "Saved match" : compactTeam,
                        detail: match.liveScore.map { "\($0.playerGames)-\($0.opponentGames)" } ?? "In progress",
                        accessibilitySummary: TennisSummaryFormatter.liveMatchScore(match, saved: stale),
                        destination: .score, isStale: stale)
        }
        if let session = training.filter(\.isActive).max(by: { ($0.actualStart ?? $0.date) < ($1.actualStart ?? $1.date) }) {
            let start = session.actualStart ?? session.date
            let stale = now.timeIntervalSince(start) > 12 * 3600
            return Self(title: stale ? "Check training" : "Training",
                        detail: stale ? session.trainingType.rawValue : "\(max(0, Int(now.timeIntervalSince(start) / 60))) min",
                        accessibilitySummary: (stale ? "Training may still be running. " : "") + TennisSummaryFormatter.training(session, style: .short, now: now, coaches: snapshot.setup.coaches, players: snapshot.players),
                        destination: .live, isStale: stale)
        }
        let today = Calendar.current.startOfDay(for: now)
        func upcoming(_ date: Date, timed: Bool) -> Bool { timed ? date >= now : date >= today }
        func when(_ date: Date, timed: Bool) -> String {
            timed ? date.shortTennisDate + " " + date.shortTennisTime : date.shortTennisDate
        }
        func compactRange(_ start: Date, _ end: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_GB")
            formatter.dateFormat = "d/M"
            let first = formatter.string(from: start)
            return Calendar.current.isDate(start, inSameDayAs: end) ? first : first + "-" + formatter.string(from: max(start, end))
        }
        var events: [(date: Date, id: String, glance: Self)] = []
        for match in matches where match.status == .scheduled && upcoming(match.date, timed: match.hasStartTime) {
            events.append((match.date, match.id.uuidString, Self(title: "Next match", detail: when(match.date, timed: match.hasStartTime),
                accessibilitySummary: TennisSummaryFormatter.match(match, tournaments: snapshot.tournaments, style: .accessibility),
                destination: .today, isStale: false, compactDetail: match.hasStartTime ? match.date.shortTennisTime : match.date.shortTennisDate)))
        }
        for session in training where session.actualStart == nil && session.actualFinish == nil && upcoming(session.date, timed: session.hasStartTime) {
            events.append((session.date, session.id.uuidString, Self(title: session.trainingType.rawValue, detail: when(session.date, timed: session.hasStartTime),
                accessibilitySummary: TennisSummaryFormatter.training(session, now: now, coaches: snapshot.setup.coaches, players: snapshot.players),
                destination: .today, isStale: false, compactDetail: session.hasStartTime ? session.date.shortTennisTime : session.date.shortTennisDate)))
        }
        for tournament in snapshot.tournaments where (snapshot.selectedPlayerID == nil || tournament.playerID == snapshot.selectedPlayerID)
            && tournament.endDate >= today && tournament.finalResult != .completed && tournament.finalResult != .withdrawn {
            events.append((tournament.date, tournament.id.uuidString, Self(title: tournament.name.fallback("Tournament"),
                detail: TennisSummaryFormatter.dateRange(from: tournament.date, through: tournament.endDate),
                accessibilitySummary: TennisSummaryFormatter.tournament(tournament, style: .short), destination: .today, isStale: false,
                compactDetail: compactRange(tournament.date, tournament.endDate))))
        }
        if let event = events.sorted(by: { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }).first { return event.glance }
        return Self(title: "Track Tennis", detail: "Start an activity", accessibilitySummary: "Track a tennis activity.", destination: .track, isStale: false)
    }
}

enum TennisSharedSnapshotFile {
    private static func url() throws -> URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "TennisSharedAppGroup") as? String, !group.isBlank else { return nil }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw CocoaError(.fileNoSuchFile) }
        return container.appendingPathComponent("tennis-snapshot.json")
    }
    @discardableResult
    static func write(_ snapshot: TennisWatchSnapshot) throws -> Bool {
        guard let url = try url() else { return false }
        try JSONEncoder.tennisTracker.encode(snapshot).write(to: url, options: .atomic)
        return true
    }
    static func read() -> TennisWatchSnapshot? {
        guard let url = try? url(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.tennisTracker.decode(TennisWatchSnapshot.self, from: data)
    }
}
