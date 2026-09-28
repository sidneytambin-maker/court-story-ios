import Foundation

// Compact per-record history lets Watch retain all-time progress beyond its editable history cache.
struct TennisAchievementRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var playerID: UUID
    var date: Date
    var metrics: [String]
    var seconds: Double = 0
    var linkedTrainingID: UUID?
    var legacyPractice = false

    static func collect(matches: [MatchRecord], training: [TrainingSession], tournaments: [TournamentRecord], now: Date = Date()) -> [Self] {
        var records = [Self]()
        for session in training {
            var metrics = [String]()
            if session.isRecordedTraining(at: now) {
                metrics.append("training")
                if !session.specificFocusSelections.isEmpty { metrics.append("focus") }
                if !session.notes.isBlank || !session.sessionOutcome.isBlank { metrics.append("reflection") }
                if session.trackedOnWatch == true || session.workout != nil { metrics.append("watchTraining") }
                if let practice = session.practiceResult { metrics += matchMetrics(kind: practice.kind, result: practice.result) }
            }
            records.append(Self(id: session.id, playerID: session.playerID, date: session.actualStart ?? session.date,
                metrics: metrics, seconds: TennisDurationFormatter.trainingSeconds(session), legacyPractice: session.practiceResult != nil))
        }
        for match in matches {
            records.append(Self(id: match.id, playerID: match.playerID, date: match.date,
                metrics: match.status == .completed && match.date <= now ? matchMetrics(kind: match.matchType, result: match.result) : [],
                linkedTrainingID: match.trainingSessionID))
        }
        for tournament in tournaments {
            var metrics = tournament.name.isBlank ? [] : ["tournament"]
            if !metrics.isEmpty && tournament.finalResult == .completed { metrics.append("completedTournament") }
            records.append(Self(id: tournament.id, playerID: tournament.playerID, date: tournament.date, metrics: metrics))
        }
        var seen = Set<UUID>()
        return records.filter { seen.insert($0.id).inserted }
    }

    private static func matchMetrics(kind: MatchKind, result: MatchResult) -> [String] {
        var metrics = ["match", kind == .singles ? "singles" : "doubles"]
        if result == .win { metrics.append(kind == .singles ? "singlesWin" : "doublesWin") }
        if result == .loss { metrics.append(kind == .singles ? "singlesLoss" : "doublesLoss") }
        if result == .draw { metrics.append(kind == .singles ? "singlesDraw" : "doublesDraw") }
        if result == .retired { metrics.append(kind == .singles ? "singlesRetired" : "doublesRetired") }
        return metrics
    }

    static func merge(history: [Self], current: [Self], deleted: Set<UUID>) -> [Self] {
        var records = [UUID: Self]()
        for record in history + current where !deleted.contains(record.id) { records[record.id] = record }
        let linked = Set(records.values.compactMap(\.linkedTrainingID))
        return records.values.map { record in
            var copy = record
            if record.legacyPractice && linked.contains(record.id) {
                copy.metrics.removeAll { $0 == "match" || $0.hasPrefix("singles") || $0.hasPrefix("doubles") }
            }
            return copy
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

struct TennisAchievement: Identifiable, Equatable {
    let id: String
    let title: String
    let requirement: String
    let celebration: String
    let symbol: String
    let metric: String
    let target: Int
    var progress: Int = 0
    var earned: Bool { progress >= target }
    var fraction: Double { min(1, Double(progress) / Double(target)) }
    var summary: String {
        earned ? "Earned. " + celebration : "To collect. \(progress) of \(target). " + requirement
    }

    static let collection: [Self] = [
        .init(id: "training.1", title: "First Steps on Court", requirement: "Complete your first training session.", celebration: "Your first session is in the book. A brilliant beginning!", symbol: "figure.tennis", metric: "training", target: 1),
        .init(id: "training.10", title: "Ten Sessions Strong", requirement: "Complete 10 training sessions.", celebration: "Ten sessions of showing up for your tennis. Well done!", symbol: "figure.tennis", metric: "training", target: 10),
        .init(id: "training.25", title: "Building Your Game", requirement: "Complete 25 training sessions.", celebration: "Twenty-five sessions. Your commitment deserves celebrating.", symbol: "figure.tennis", metric: "training", target: 25),
        .init(id: "training.50", title: "Training Half Century", requirement: "Complete 50 training sessions.", celebration: "Fifty sessions. That is a lot of time invested in your game!", symbol: "laurel.leading", metric: "training", target: 50),
        .init(id: "training.100", title: "Century on Court", requirement: "Complete 100 training sessions.", celebration: "One hundred sessions. What a remarkable tennis journey!", symbol: "star.circle.fill", metric: "training", target: 100),
        .init(id: "match.1", title: "Game On", requirement: "Record your first completed match.", celebration: "Your first match is logged. Your match story starts here!", symbol: "tennisball.fill", metric: "match", target: 1),
        .init(id: "match.10", title: "Ten Match Moments", requirement: "Record 10 completed matches.", celebration: "Ten matches, ten chances to learn. Keep enjoying your tennis!", symbol: "tennisball.fill", metric: "match", target: 10),
        .init(id: "match.50", title: "Fifty and Playing", requirement: "Record 50 completed matches.", celebration: "Fifty matches recorded. Celebrate every one of those experiences!", symbol: "star.circle.fill", metric: "match", target: 50),
        .init(id: "match.100", title: "Match Century", requirement: "Record 100 completed matches.", celebration: "A hundred matches. An achievement worth applauding!", symbol: "trophy.fill", metric: "match", target: 100),
        .init(id: "singles.10", title: "Your Own Court", requirement: "Record 10 completed singles matches.", celebration: "Ten singles matches. You are building your own tennis story!", symbol: "person.fill", metric: "singles", target: 10),
        .init(id: "doubles.10", title: "Better Together", requirement: "Record 10 completed doubles matches.", celebration: "Ten doubles matches. Here is to teamwork and shared court time!", symbol: "person.2.fill", metric: "doubles", target: 10),
        .init(id: "singlesWin.1", title: "Singles Breakthrough", requirement: "Record your first singles win.", celebration: "Your first recorded singles win. Enjoy this moment!", symbol: "checkmark.seal.fill", metric: "singlesWin", target: 1),
        .init(id: "doublesWin.1", title: "Winning Partnership", requirement: "Record your first doubles win.", celebration: "Your first recorded doubles win. A shared success to celebrate!", symbol: "person.2.fill", metric: "doublesWin", target: 1),
        .init(id: "tournament.1", title: "On the Tournament Map", requirement: "Add your first named tournament entry.", celebration: "Your first tournament entry is saved. Something to look forward to!", symbol: "trophy.fill", metric: "tournament", target: 1),
        .init(id: "tournament.5", title: "Tournament Explorer", requirement: "Add five named tournament entries.", celebration: "Five tournament entries. Your tennis world is growing!", symbol: "trophy.fill", metric: "tournament", target: 5),
        .init(id: "completedTournament.1", title: "Tournament Journey", requirement: "Mark your first tournament completed.", celebration: "Your first completed tournament. Take a moment to appreciate the journey!", symbol: "flag.checkered", metric: "completedTournament", target: 1),
        .init(id: "watchTraining.1", title: "From Your Wrist", requirement: "Finish a training session tracked on Apple Watch.", celebration: "Your first Watch-tracked session is saved. Nicely done!", symbol: "applewatch", metric: "watchTraining", target: 1),
        .init(id: "watchTraining.10", title: "Wrist Ready", requirement: "Finish 10 training sessions tracked on Apple Watch.", celebration: "Ten sessions tracked from your wrist. Your court companion is earning its place!", symbol: "applewatch", metric: "watchTraining", target: 10),
        .init(id: "focus.1", title: "Practice with Purpose", requirement: "Record a specific focus in a completed training session.", celebration: "You have given your practice a focus. A useful step forward!", symbol: "scope", metric: "focus", target: 1),
        .init(id: "focus.10", title: "Purposeful Practice", requirement: "Complete 10 sessions with a specific training focus.", celebration: "Ten focused sessions. Keep making your practice count!", symbol: "scope", metric: "focus", target: 10),
        .init(id: "reflection.1", title: "Pause and Reflect", requirement: "Save notes or progress for a completed training session.", celebration: "Your first training reflection is saved. Learning continues off court too!", symbol: "square.and.pencil", metric: "reflection", target: 1),
        .init(id: "reflection.10", title: "Learning the Game", requirement: "Save notes or progress for 10 completed training sessions.", celebration: "Ten sessions reflected on. You are building a useful record of your game!", symbol: "book.fill", metric: "reflection", target: 10)
    ]

    static func build(records: [TennisAchievementRecord], playerID: UUID?) -> [Self] {
        let selected = records.filter { $0.playerID == playerID }
        return collection.map { badge in
            var result = badge
            result.progress = Set(selected.filter { $0.metrics.contains(badge.metric) }.map(\.id)).count
            return result
        }
    }

    static func earnedIDs(records: [TennisAchievementRecord], playerID: UUID?) -> Set<String> {
        Set(build(records: records, playerID: playerID).filter(\.earned).map(\.id))
    }

    static func feedback(before: Set<String>, records: [TennisAchievementRecord], playerID: UUID?, settings: TennisSoundSettings, otherwise: TennisFeedbackEvent) -> TennisFeedbackEvent {
        settings.milestonesEnabled && !earnedIDs(records: records, playerID: playerID).subtracting(before).isEmpty ? .milestone : otherwise
    }
}

extension TennisWatchSnapshot {
    var achievementRecords: [TennisAchievementRecord] {
        TennisAchievementRecord.merge(history: achievementHistory,
            current: TennisAchievementRecord.collect(matches: matches, training: trainingSessions, tournaments: tournaments), deleted: deletedRecordIDs)
    }
    var achievements: [TennisAchievement] { TennisAchievement.build(records: achievementRecords, playerID: selectedPlayerID) }
}

extension AppData {
    var achievementRecords: [TennisAchievementRecord] {
        TennisAchievementRecord.merge(history: [], current: TennisAchievementRecord.collect(matches: matches, training: trainingSessions, tournaments: tournaments), deleted: deletedRecordIDs)
    }
    var achievements: [TennisAchievement] { TennisAchievement.build(records: achievementRecords, playerID: selectedPlayerID) }
}
