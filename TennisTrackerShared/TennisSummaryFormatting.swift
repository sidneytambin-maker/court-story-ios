import Foundation

enum TennisSummaryStyle { case short, long, accessibility, detailed }

struct TennisMatchSummary: Equatable {
    var headline: String
    var scheduleText: String
    var shortText: String
    var longText: String
    var accessibilityText: String
    var scoreText: String
}

enum TennisSummaryFormatter {
    static func match(_ match: MatchRecord, tournaments: [TournamentRecord] = [], style: TennisSummaryStyle = .long) -> String {
        let summary = matchSummary(match, tournaments: tournaments)
        switch style {
        case .short: return summary.shortText
        case .long: return summary.longText
        case .accessibility: return summary.accessibilityText
        case .detailed:
            if match.usesCourtScoring {
                let rules = match.court.score?.rules ?? match.court.rules ?? .standard(for: match.court.sport.sport)
                return "\(match.court.sport.name). \(summary.longText) \(rules.formatSummary)" + (match.conditionsSummary.isBlank ? "" : " " + match.conditionsSummary)
            }
            return "\(summary.longText) \(match.matchFormat.label), \(match.suddenDeathDeuce ? "sudden-death deuce" : "advantage deuce"). Player classification: \(match.sightLevel.label). \(match.allowedBounces) bounces allowed." + (match.conditionsSummary.isBlank ? "" : " " + match.conditionsSummary)
        }
    }

    static func matchSummary(_ match: MatchRecord, tournaments: [TournamentRecord] = []) -> TennisMatchSummary {
        let round = match.matchPosition == .notSpecified ? "match" : match.matchPosition.label.lowercased()
        let headline = "\(match.status.rawValue) \(match.matchType.rawValue.lowercased()) \(round)"
        var schedule = match.date.tennisSummaryDate
        if match.hasStartTime { schedule += " at \(match.date.shortTennisTime)" }
        let place = unique([match.venue, match.location]).joined(separator: ", ")
        if !place.isBlank { schedule += " at \(place)" }
        let team = match.playerTeam
        let opponents = match.opponentSummary.fallback("opponent not recorded")
        let score = scoreText(for: match)
        let tournament = match.tournamentID.flatMap { id in tournaments.first { $0.id == id }?.name } ?? match.customTournamentName ?? ""
        let verb: String
        switch match.status {
        case .scheduled: verb = "will play"
        case .inProgress: verb = match.matchType == .doubles ? "are playing" : "is playing"
        case .completed:
            switch match.result {
            case .win: verb = "beat"
            case .loss: verb = "lost to"
            case .draw: verb = match.stoppedWithoutWinner ? "stopped play without a winner against" : "drew with"
            case .retired: verb = "retired against"
            }
        }
        var standard = "\(headline). \(team) \(verb) \(opponents)"
        if !score.isBlank { standard += ", \(score)" }
        else if match.status == .completed { standard += ". Score not recorded" }
        if !tournament.isBlank { standard += ", \(tournament)" }
        standard += ", \(schedule)"
        let duration = match.actualStart.flatMap { start in match.actualFinish.map { TennisDurationFormatter.text(seconds: $0.timeIntervalSince(start)) } }
        if let duration { standard += ", duration \(duration)" }
        standard += "."
        let status = match.status == .completed ? match.resultDescription : match.status.rawValue
        // Doubles names remain complete even on compact surfaces.
        var compact = match.matchType == .doubles ? "\(team) \(verb) \(opponents)" : "\(status) against \(opponents)"
        if !score.isBlank { compact += ", \(score)" }
        else if match.status == .completed { compact += ". Score not recorded" }
        if !tournament.isBlank { compact += ", \(tournament)" }
        if let duration { compact += ", \(duration)" }
        return TennisMatchSummary(headline: headline, scheduleText: schedule, shortText: headline + ". " + compact + ".",
            longText: standard, accessibilityText: standard, scoreText: score.fallback("Score not recorded"))
    }

    static func training(_ session: TrainingSession, style: TennisSummaryStyle = .long, now: Date = Date(), coaches: [TennisCoach] = [], players: [PlayerProfile] = []) -> String {
        var parts = [session.trainingType.rawValue]
        let coaches = session.context.coachSummary(in: coaches)
        parts.append(TennisDurationFormatter.training(session, now: now) + (session.isActive ? " elapsed" : ""))
        parts.append("Focus: " + session.focusSummary)
        if let tournament = session.context.customTournamentName, !tournament.isBlank { parts.append("Tournament: " + tournament) }
        if !coaches.isBlank { parts.append("Coaches: \(coaches)") }
        let participants = session.context.participantSummary(in: players)
        if !participants.isBlank {
            parts.append("Players: " + participants)
        }
        parts += unique([session.venue, session.location])
        if style != .short {
            let date = session.actualStart ?? session.date
            parts.append(date.tennisSummaryDate + (session.hasStartTime || session.actualStart != nil ? " at \(date.shortTennisTime)" : ""))
        }
        if style == .detailed, let result = session.workout {
            if session.durationSource == .manual {
                let duration = result.durationSeconds.isFinite && result.durationSeconds >= 0
                    ? " " + TennisDurationFormatter.text(seconds: result.durationSeconds) : ""
                parts.append("Fitness measurements cover the original\(duration) recording")
            }
            if !result.fitnessSummary.isBlank { parts.append(result.fitnessSummary.trimmingCharacters(in: CharacterSet(charactersIn: "."))) }
        }
        if let practice = session.practiceResult {
            var match = MatchRecord(playerID: session.playerID)
            match.playerName = players.first { $0.id == session.playerID }?.displayName ?? "You"
            match.matchType = practice.kind
            match.partnerName = practice.partnerID.flatMap { id in players.first { $0.id == id }?.displayName } ?? practice.partnerName
            match.opponentName = practice.opponentID.flatMap { id in players.first { $0.id == id }?.displayName } ?? practice.opponentName
            match.opponent2Name = practice.opponent2ID.flatMap { id in players.first { $0.id == id }?.displayName } ?? practice.opponent2Name
            match.result = practice.result
            match.setScores = "\(practice.playerGames)-\(practice.opponentGames)"
            parts.append("Practice result: " + matchSummary(match).shortText.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        }
        return parts.joined(separator: ", ") + "."
    }

    static func tournament(_ tournament: TournamentRecord, linkedMatchCount: Int = 0, style: TennisSummaryStyle = .long, matches: [MatchRecord]? = nil, includeName: Bool = true) -> String {
        var parts = includeName ? [tournament.name.fallback("Tournament")] : []
        parts.append(dateRange(from: tournament.date, through: tournament.endDate))
        parts += unique([tournament.venue, tournament.location])
        parts.append("Status: \(tournament.statusText)")
        if tournament.stageReached != .notStarted || tournament.finishingPosition != nil || style == .detailed || style == .accessibility {
            parts.append(tournament.outcomeSummary)
        }
        if style == .detailed || style == .accessibility {
            if tournament.finishingPosition == nil { parts.append("Finishing position: Not recorded") }
            parts.append("Format: \(tournament.format.rawValue)")
        }
        if let start = tournament.actualStart, let finish = tournament.actualFinish {
            parts.append("Tracked duration " + TennisDurationFormatter.text(seconds: finish.timeIntervalSince(start)))
        }
        if style != .short || matches != nil || linkedMatchCount > 0 {
            let linked = (matches ?? []).filter { $0.tournamentID == tournament.id && $0.playerID == tournament.playerID }
            if !linked.isEmpty {
                let scheduled = linked.filter { $0.status == .scheduled }.count
                let inProgress = linked.filter { $0.status == .inProgress }.count
                let completed = linked.filter { $0.status == .completed }
                if scheduled > 0 { parts.append("\(scheduled) scheduled \(scheduled == 1 ? "match" : "matches")") }
                if inProgress > 0 { parts.append("\(inProgress) \(inProgress == 1 ? "match" : "matches") in progress") }
                if !completed.isEmpty {
                    let outcomes: [(MatchResult, String, String)] = [(.win, "win", "wins"), (.loss, "loss", "losses"),
                        (.draw, "draw", "draws"), (.retired, "retirement", "retirements")]
                    var results = outcomes.compactMap { outcome, singular, plural -> String? in
                        let count = completed.filter { !$0.stoppedWithoutWinner && $0.result == outcome }.count
                        return count > 0 ? "\(count) \(count == 1 ? singular : plural)" : nil
                    }
                    let stopped = completed.filter(\.stoppedWithoutWinner).count
                    if stopped > 0 { results.append("\(stopped) stopped without a winner") }
                    parts.append("\(completed.count) completed \(completed.count == 1 ? "match" : "matches"): " + results.joined(separator: " and "))
                }
            } else {
                // An explicit record list is authoritative; a count alone cannot imply played matches.
                let count = matches == nil ? max(0, linkedMatchCount) : 0
                parts.append(count == 0 ? "No matches linked yet" : "\(count) linked \(count == 1 ? "match" : "matches")")
            }
        }
        return parts.joined(separator: ", ") + "."
    }

    static func dateRange(from start: Date, through end: Date, calendar: Calendar = .current) -> String {
        let finish = max(start, end)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        func formatted(_ date: Date, _ pattern: String) -> String {
            formatter.dateFormat = pattern
            return formatter.string(from: date)
        }
        if calendar.isDate(start, inSameDayAs: finish) { return formatted(start, "d MMMM yyyy") }
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: finish)
        let sameMonth = sameYear && calendar.component(.month, from: start) == calendar.component(.month, from: finish)
        return formatted(start, sameMonth ? "d" : sameYear ? "d MMMM" : "d MMMM yyyy") + " to " + formatted(finish, "d MMMM yyyy")
    }

    static func liveMatchScore(_ match: MatchRecord, saved: Bool = false) -> String {
        let participants = "\(match.playerTeam) against \(match.opponentSummary.fallback("opponent not recorded"))"
        if let score = match.court.score { return (saved ? "Saved match. " : "") + match.court.sport.name + ". " + score.summary }
        if saved { return "Saved match: \(participants). \(matchSummary(match).scoreText)." }
        guard let score = match.liveScore else { return "\(participants). Match in progress; score not recorded." }
        return participants + ". " + scoreAnnouncement(state: TennisScoreState(snapshot: score), playerName: match.playerTeam,
            opponentName: match.opponentSummary, suddenDeathDeuce: match.suddenDeathDeuce, pluralTeams: match.matchType == .doubles)
    }

    static func scoreAnnouncement(state: TennisScoreState, playerName: String, opponentName: String, suddenDeathDeuce: Bool, pluralTeams: Bool = false) -> String {
        if state.isMatchComplete { return "Match, \(state.playerSets > state.opponentSets ? playerName : opponentName)." }
        let games: String
        if state.playerGames == state.opponentGames { games = "Games level at \(state.playerGames) all" }
        else {
            let leader = state.playerGames > state.opponentGames ? playerName : opponentName
            games = "\(leader) \(pluralTeams ? "lead" : "leads") \(max(state.playerGames, state.opponentGames)) games to \(min(state.playerGames, state.opponentGames))"
        }
        return "\(state.pointScore(suddenDeathDeuce: suddenDeathDeuce)). \(games)."
    }

    private static func scoreText(for match: MatchRecord) -> String {
        if let score = match.court.score, match.status != .scheduled {
            return match.status == .inProgress ? score.summary : score.resultSummary
        }
        if match.status == .inProgress, let live = match.liveScore {
            let state = TennisScoreState(snapshot: live)
            return [live.completedSetScores.joined(separator: ", "), "\(live.playerGames)-\(live.opponentGames)", state.pointScore(suddenDeathDeuce: match.suddenDeathDeuce)].filter { !$0.isBlank }.joined(separator: ", ")
        }
        if !match.recordedSets.isEmpty {
            return match.recordedSets.enumerated().map { "Set \($0.offset + 1): \($0.element.spokenScore)" }.joined(separator: "; ")
        }
        if !match.setScores.isBlank { return match.setScores }
        if match.yourSetsWon + match.opponentSetsWon > 0 { return "sets \(match.yourSetsWon)-\(match.opponentSetsWon)" }
        return ""
    }

    private static func unique(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values where !value.isBlank && !result.contains(value) { result.append(value) }
        return result
    }
}
