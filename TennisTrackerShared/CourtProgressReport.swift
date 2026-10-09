import Foundation

struct CourtProgressReport: Equatable {
    struct Row: Identifiable, Equatable {
        var title: String
        var value: String
        var id: String { title }
    }
    var athlete: String
    var sport: String
    var from: Date
    var through: Date
    var rows: [Row]
    var includesPrivateNotes: Bool

    static func make(athleteID: UUID, sport: CourtSportSelection, data: AppData, from: Date, through: Date,
                     includeGoal: Bool = false, includeDevelopmentNotes: Bool = false, includeObservations: Bool = false) -> CourtProgressReport? {
        guard from <= through, let person = data.players.first(where: { $0.id == athleteID }),
              let preferences = person.court.sports.first(where: { $0.sport == sport }) else { return nil }
        let matches = data.matches.filter { $0.playerID == athleteID && $0.court.sport == sport &&
            $0.status == .completed && $0.date >= from && $0.date <= through && !data.deletedRecordIDs.contains($0.id) }
        let training = data.trainingSessions.filter { $0.playerID == athleteID && $0.court.sport == sport &&
            ($0.actualStart ?? $0.date) >= from && ($0.actualStart ?? $0.date) <= through && $0.isRecordedTraining(at: through) && !data.deletedRecordIDs.contains($0.id) }
        let tournaments = data.tournaments.filter { $0.playerID == athleteID && $0.court.sport == sport &&
            $0.date >= from && $0.endDate <= through && $0.finalResult == .completed && !data.deletedRecordIDs.contains($0.id) }
        var rows: [Row] = []
        for type in [MatchKind.singles, .doubles] {
            let records = matches.filter { $0.matchType == type }
            let stopped = records.filter { $0.court.score.map { $0.frame.complete && $0.frame.winningSide == nil } == true }
            let decided = records.filter { record in !stopped.contains { $0.id == record.id } }
            rows.append(Row(title: "\(type.rawValue) matches", value: "\(records.count) completed: \(decided.filter { $0.result == .win }.count) wins, \(decided.filter { $0.result == .loss }.count) losses, \(decided.filter { $0.result == .draw }.count) draws, \(stopped.count) stopped without a winner"))
        }
        rows.append(Row(title: "Training", value: "\(training.count) recorded sessions, " + TennisDurationFormatter.text(seconds: training.reduce(0) { $0 + TennisDurationFormatter.trainingSeconds($1) })))
        rows.append(Row(title: "Tournaments", value: "\(tournaments.count) completed"))
        let focusNames = Set(training.flatMap(\.specificFocusSelections)).sorted()
        for focus in focusNames {
            rows.append(Row(title: "Focus: \(focus)", value: "\(training.filter { $0.specificFocusSelections.contains(focus) }.count) of \(training.count) recorded sessions"))
        }
        let unknown = training.filter { $0.specificFocusSelections.isEmpty }.count
        if unknown > 0 { rows.append(Row(title: "Focus not recorded", value: "\(unknown) sessions")) }
        if includeGoal { rows.append(Row(title: "Player goal", value: preferences.primaryGoal.fallback("Not recorded"))) }
        if includeDevelopmentNotes { rows.append(Row(title: "Private development notes", value: preferences.developmentNotes.fallback("Not recorded"))) }
        if includeObservations {
            let observations = data.court.observations.filter { $0.athleteID == athleteID && $0.sport == sport && $0.date >= from && $0.date <= through && !data.court.deletedIDs.contains($0.id) }.sorted { $0.date < $1.date }
            for (index, observation) in observations.enumerated() {
                rows.append(Row(title: "Private observation \(index + 1), \(observation.date.fullTennisDate)", value: ["What happened: \(observation.happened)", "Interpretation: \(observation.interpretation.fallback("Not recorded"))", "Player perspective: \(observation.playerPerspective.fallback("Not recorded"))", "Next action: \(observation.nextAction.fallback("Not recorded"))"].joined(separator: "\n")))
            }
        }
        return CourtProgressReport(athlete: person.displayName, sport: sport.name, from: from, through: through, rows: rows, includesPrivateNotes: includeGoal || includeDevelopmentNotes || includeObservations)
    }

    var text: String {
        (["Court Story", "\(athlete) | \(sport) progress", "\(from.fullTennisDate) to \(through.fullTennisDate)"] +
         rows.map { "\($0.title)\n\($0.value)" } +
         ["Recorded activity only. Missing records are not evidence of no activity. Health data, access preferences and original media are not included."])
            .joined(separator: "\n\n")
    }
    var csv: String {
        func cell(_ text: String) -> String {
            // A spreadsheet must treat user-entered names and notes as text, not formulas.
            let protected = text.first.map { "=+-@\t\r".contains($0) } == true ? "'" + text : text
            return "\"" + protected.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let fields = [["Field", "Value"], ["Player", athlete], ["Sport", sport], ["From", from.fullTennisDate], ["Through", through.fullTennisDate]] + rows.map { [$0.title, $0.value] }
        return fields.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n")
    }
}
