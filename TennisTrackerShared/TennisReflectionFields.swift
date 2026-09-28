import SwiftUI

struct TennisReflectionDraft: Equatable {
    let sessionID: UUID
    var focus: String
    var additionalFocus: [String]
    var outcome: String
    var notes: String
    init(session: TrainingSession) {
        sessionID = session.id; focus = session.focus; additionalFocus = session.additionalFocus
        outcome = session.sessionOutcome; notes = session.notes
    }
    func applying(to current: TrainingSession) -> TrainingSession? {
        guard current.id == sessionID else { return nil }
        var result = current
        result.focus = focus; result.additionalFocus = additionalFocus
        result.sessionOutcome = outcome; result.notes = notes
        return result
    }
}

struct TennisReflectionFields: View {
    @Binding var draft: TennisReflectionDraft
    let summary: String
    var body: some View {
        Text(summary).font(.callout)
            .accessibilityIdentifier("reflectionSessionSummary")
        TennisTrainingFocusPicker(focus: $draft.focus, additionalFocus: $draft.additionalFocus)
        TextField("Progress and next steps", text: $draft.outcome, axis: .vertical)
            .accessibilityIdentifier("reflectionProgressField")
            .accessibilityHint("What improved in this session, and what would you like to practise next? Saved progress stays with this session.")
        TextField("Reflection notes", text: $draft.notes, axis: .vertical)
            .accessibilityIdentifier("reflectionNotesField")
            .accessibilityHint("Your session notes. Existing notes are kept here so you can add to them.")
    }
}
