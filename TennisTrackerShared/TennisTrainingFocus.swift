import Foundation

enum TennisTrainingFocus: String, CaseIterable, Identifiable {
    case serves = "Serves"
    case returns = "Returns"
    case serveAndReturn = "Serve and return"
    case forehand = "Forehand"
    case backhand = "Backhand"
    case volleys = "Volleys and net play"
    case overheads = "Overheads and smashes"
    case footwork = "Footwork and court movement"
    case rallying = "Rally consistency"
    case placement = "Shot placement and accuracy"
    case tactics = "Point construction and tactics"
    case doubles = "Doubles positioning and teamwork"
    case defence = "Defence and recovery"
    case touch = "Drop shots and lobs"
    case tracking = "Ball tracking and timing"
    case pressure = "Playing under pressure"

    var id: String { rawValue }

    static func selections(focus: String, additional: [String]) -> [String] {
        var seen = Set<String>()
        return ([focus] + additional).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    static func isSpecific(_ value: String) -> Bool {
        if allCases.contains(where: { $0.rawValue.localizedCaseInsensitiveCompare(value) == .orderedSame }) { return true }
        let generic = TrainingType.allCases.map(\.rawValue) + ["General practice", "Technical session", "Tactical session"]
        return !value.isBlank && !generic.contains { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }
    }
}

extension TrainingSession {
    var dashboardFocusSummary: String {
        if focusSelections.isEmpty { return "No focus selected" }
        return TennisActivityContext.names(specificFocusSelections).fallback("Specific focus not recorded")
    }
    var focusSelections: [String] { TennisTrainingFocus.selections(focus: focus, additional: additionalFocus) }
    var specificFocusSelections: [String] { focusSelections.filter(TennisTrainingFocus.isSpecific) }
    var focusSummary: String { TennisActivityContext.names(specificFocusSelections).fallback("No focus selected") }

    func isRecordedTraining(at now: Date) -> Bool {
        guard !isActive else { return false }
        if let finish = actualFinish { return finish <= now }
        return expectedEndDate <= now
    }
}
