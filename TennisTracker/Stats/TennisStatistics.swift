import Foundation

struct TennisStatistics: Equatable {
    let matchCount: Int
    let winCount: Int
    let lossCount: Int
    let drawCount: Int
    let winRate: Double
    let trainingCount: Int
    let trainingMinutesLast30Days: Int
    let trainingSecondsLast30Days: TimeInterval
    let trainingCountLast30Days: Int
    let tiebreakSetsLast30Days: Int
    let upcomingTournamentCount: Int
    let needsAttention: [String]

    var spokenSummary: String {
        let percent = Int((winRate * 100).rounded())
        return "\(matchCount) completed matches, \(winCount) wins, \(lossCount) losses, \(drawCount) draws, \(percent) percent win rate. \(trainingCount) training sessions saved."
    }

    static func build(matches: [MatchRecord], training: [TrainingSession], tournaments: [TournamentRecord], today: Date = Date()) -> TennisStatistics {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: today)) ?? today
        let completedMatches = TennisCompletedMatch.collect(matches: matches, training: training, now: today)
        let wins = completedMatches.filter { $0.result == .win }.count
        let losses = completedMatches.filter { $0.result == .loss }.count
        let last30Matches = matches.filter { $0.status == .completed && $0.date >= start && $0.date <= today }
        let last30Training = training.filter { ($0.actualStart ?? $0.date) >= start && $0.isRecordedTraining(at: today) }
        let trainingSeconds = last30Training.reduce(0.0) { $0 + TennisDurationFormatter.trainingSeconds($1) }
        let upcoming = tournaments.filter { calendar.startOfDay(for: $0.date) >= calendar.startOfDay(for: today) }
        let linkedCounts = Dictionary(grouping: matches.compactMap(\.tournamentID), by: { $0 }).mapValues(\.count)

        var attention: [String] = []
        let outstanding = tournaments.reduce(0) { total, tournament in
            total + tournament.outstandingMatches(linkedMatchCount: linkedCounts[tournament.id, default: 0])
        }
        if outstanding > 0 {
            attention.append("\(outstanding) tournament matches still need adding.")
        }
        let incomplete = matches.filter(\.needsDetails).count + training.filter(\.needsDetails).count + tournaments.filter(\.needsDetails).count
        if incomplete > 0 {
            attention.append("\(incomplete) activities still need their details completed.")
        }

        return TennisStatistics(
            matchCount: completedMatches.count,
            winCount: wins,
            lossCount: losses,
            drawCount: completedMatches.filter { $0.result == .draw }.count,
            winRate: completedMatches.isEmpty ? 0 : Double(wins) / Double(completedMatches.count),
            trainingCount: training.count,
            trainingMinutesLast30Days: Int(min(trainingSeconds / 60, 5_256_000)),
            trainingSecondsLast30Days: trainingSeconds,
            trainingCountLast30Days: last30Training.count,
            tiebreakSetsLast30Days: last30Matches.reduce(0) { $0 + $1.tiebreakSetCount },
            upcomingTournamentCount: upcoming.count,
            needsAttention: attention
        )
    }
}
