import Foundation

enum TennisGlanceKind: String, CaseIterable {
    case current, next, week, latest, startTraining

    var widgetKind: String {
        switch self {
        case .current: return "TennisTrackerComplication"
        case .next: return "TennisTrackerNextEvent"
        case .week: return "TennisTrackerThisWeek"
        case .latest: return "TennisTrackerLatestResult"
        case .startTraining: return "TennisTrackerStartTraining"
        }
    }
    var name: String {
        switch self {
        case .current: return "Current Activity"
        case .next: return "Next Tennis Event"
        case .week: return "This Week"
        case .latest: return "Latest Result"
        case .startTraining: return "Start Training"
        }
    }
    var description: String {
        switch self {
        case .current: return "Live score or elapsed training and tournament time."
        case .next: return "The next scheduled tennis activity."
        case .week: return "Completed training time and match results from Monday to Sunday."
        case .latest: return "The most recently completed tennis activity."
        case .startTraining: return "Start tennis training, with scheduled details ready near the start time."
        }
    }
    var symbol: String {
        switch self {
        case .current: return "tennisball.fill"
        case .next: return "calendar"
        case .week: return "chart.bar.fill"
        case .latest: return "checkmark.circle.fill"
        case .startTraining: return "play.circle.fill"
        }
    }
}

extension TennisGlance {
    static func make(kind: TennisGlanceKind, snapshot: TennisWatchSnapshot, now: Date = Date(), calendar: Calendar = .current) -> Self {
        var selected = snapshot
        selected.matches = snapshot.matches.filter { snapshot.selectedPlayerID == nil || $0.playerID == snapshot.selectedPlayerID }
        selected.trainingSessions = snapshot.trainingSessions.filter { snapshot.selectedPlayerID == nil || $0.playerID == snapshot.selectedPlayerID }
        selected.tournaments = snapshot.tournaments.filter { snapshot.selectedPlayerID == nil || $0.playerID == snapshot.selectedPlayerID }
        switch kind {
        case .startTraining:
            if let active = selected.trainingSessions.first(where: \.isActive) {
                return Self(title: "Training", detail: "In progress", accessibilitySummary: "Training in progress. " + TennisSummaryFormatter.training(active, style: .short, now: now, coaches: selected.setup.coaches, players: selected.players), destination: .live, isStale: false, compactDetail: "Live")
            }
            let candidates = TennisScheduling.nearbyTraining(in: selected, now: now)
            let summary = candidates.count == 1
                ? "Start scheduled training. " + TennisSummaryFormatter.training(candidates[0], coaches: selected.setup.coaches, players: selected.players)
                : "Start tennis training. " + (candidates.isEmpty ? "Choose session details." : "Choose a scheduled session.")
            return Self(title: "Start Training", detail: candidates.count == 1 ? candidates[0].trainingType.rawValue : "Ready to play",
                accessibilitySummary: summary, destination: .track, isStale: false, compactDetail: "Start",
                actionURL: URL(string: "tennistracker://watch/start-training"))
        case .current:
            let live = make(snapshot: selected, now: now)
            if live.destination == .live || live.destination == .score { return live }
            if let tournament = selected.tournaments.filter({ $0.actualStart != nil && $0.actualFinish == nil && $0.finalResult == .inProgress })
                .max(by: { ($0.actualStart ?? $0.date) < ($1.actualStart ?? $1.date) }) {
                let duration = TennisDurationFormatter.text(seconds: now.timeIntervalSince(tournament.actualStart ?? now))
                return Self(title: tournament.name, detail: duration,
                    accessibilitySummary: tournament.name + ". Tracked duration " + duration + ".",
                    destination: .live, isStale: false, compactDetail: "\(max(0, Int(now.timeIntervalSince(tournament.actualStart ?? now) / 60))) min")
            }
            return Self(title: "Current Activity", detail: "No activity running", accessibilitySummary: "No tennis activity is running. Open Track.", destination: .track, isStale: false, compactDetail: "Start")
        case .next:
            selected.matches.removeAll { $0.status != .scheduled }
            selected.trainingSessions.removeAll { $0.actualStart != nil || $0.actualFinish != nil }
            selected.tournaments.removeAll { $0.actualStart != nil && $0.actualFinish == nil }
            let next = make(snapshot: selected, now: now)
            if next.destination == .today { return next }
            return Self(title: "Next Tennis", detail: "Nothing scheduled", accessibilitySummary: "No upcoming tennis event is scheduled.", destination: .today, isStale: false, compactDetail: "None")
        case .week:
            let start = TennisReportingWeek.interval(containing: now, calendar: calendar).start
            let training = selected.trainingSessions.filter { !$0.isActive && ($0.actualStart ?? $0.date) >= start && ($0.actualFinish ?? $0.expectedEndDate) <= now }
            let matches = selected.matches.filter { $0.status == .completed && ($0.actualFinish ?? $0.date) >= start && ($0.actualFinish ?? $0.date) <= now }
            let seconds = training.reduce(0.0) { $0 + TennisDurationFormatter.trainingSeconds($1) }
            let wins = matches.filter { $0.result == .win }.count
            let duration = TennisDurationFormatter.text(seconds: seconds)
            let summary = "This week. \(TennisReportingWeek.summary(containing: now, calendar: calendar)). \(training.count) completed training \(training.count == 1 ? "session" : "sessions"), \(duration). \(matches.count) completed \(matches.count == 1 ? "match" : "matches"), \(wins) \(wins == 1 ? "win" : "wins")."
            return Self(title: "This Week", detail: "\(training.count) training, \(matches.count) matches", accessibilitySummary: summary,
                destination: .recent, isStale: false, compactDetail: "\(training.count) sessions")
        case .latest:
            var results: [(Date, String, Self)] = []
            for match in selected.matches where match.status == .completed && (match.actualFinish ?? match.date) <= now {
                results.append((match.actualFinish ?? match.date, match.id.uuidString,
                    Self(title: "Latest Match", detail: TennisSummaryFormatter.match(match, style: .short),
                        accessibilitySummary: TennisSummaryFormatter.match(match, tournaments: selected.tournaments),
                        destination: .recent, isStale: false, compactDetail: match.setScores.fallback(match.result.rawValue))))
            }
            for training in selected.trainingSessions where !training.isActive && (training.actualFinish ?? training.expectedEndDate) <= now {
                results.append((training.actualFinish ?? training.expectedEndDate, training.id.uuidString,
                    Self(title: training.trainingType.rawValue, detail: TennisDurationFormatter.training(training),
                        accessibilitySummary: TennisSummaryFormatter.training(training, style: .detailed, coaches: selected.setup.coaches, players: selected.players),
                        destination: .recent, isStale: false, compactDetail: TennisDurationFormatter.compact(seconds: TennisDurationFormatter.trainingSeconds(training)))))
            }
            for tournament in selected.tournaments where tournament.isCompleted && (tournament.actualFinish ?? tournament.endDate) <= now {
                results.append((tournament.actualFinish ?? tournament.endDate, tournament.id.uuidString,
                    Self(title: "Latest Tournament", detail: tournament.name,
                        accessibilitySummary: TennisSummaryFormatter.tournament(tournament, matches: selected.matches),
                        destination: .recent, isStale: false, compactDetail: tournament.stageReached.rawValue)))
            }
            return results.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 > $1.0 }.first?.2
                ?? Self(title: "Latest Result", detail: "No completed activity", accessibilitySummary: "No completed tennis activity is recorded.", destination: .recent, isStale: false, compactDetail: "None")
        }
    }
}
