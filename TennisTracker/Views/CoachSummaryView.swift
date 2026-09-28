import SwiftUI

struct CoachSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    let progress: TennisPlayerProgress
    let stats: TennisStatistics
    @State private var includeResults = true
    @State private var includeTraining = true
    @State private var includeFocus = false
    @State private var includeGoals = false

    private var hasContent: Bool { includeResults || includeTraining || includeFocus || includeGoals }

    private var summary: String {
        var lines = ["Court Story", "Tennis summary"]
        if includeResults {
            lines += ["", "Match results, all time", "Singles: " + progress.singles.summary,
                "Doubles: " + progress.doubles.summary]
        }
        if includeTraining {
            lines += ["", "Training, last 30 days",
                "\(stats.trainingCountLast30Days) sessions, \(TennisDurationFormatter.text(seconds: stats.trainingSecondsLast30Days))."]
        }
        if includeFocus {
            lines += ["", "Focus, last 30 days"]
            lines += progress.focus.isEmpty ? ["No training focus recorded."] : progress.focus.map {
                "\($0.focus): \($0.sessions) \($0.sessions == 1 ? "session" : "sessions")."
            }
        }
        if includeGoals {
            lines += ["", "Goals & match review"]
            lines += progress.suggestions.isEmpty ? ["No goals or match review recorded."] : progress.suggestions.map {
                "\($0.source): \($0.detail)"
            }
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            TennisForm {
                Section("Include") {
                    Toggle("Match results", isOn: $includeResults)
                    Toggle("Training totals", isOn: $includeTraining)
                    Toggle("Training focus", isOn: $includeFocus)
                    Toggle("Goals & match review", isOn: $includeGoals)
                        .accessibilityIdentifier("coachIncludeGoals")
                }
                Section("Preview") {
                    Text(summary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("coachSummaryText")
                }
                Section {
                    ShareLink(item: summary) {
                        Label("Share Summary", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!hasContent)
                    .accessibilityIdentifier("coachShareSummary")
                    .accessibilityHint("Opens the system share sheet. Only the previewed text is included.")
                }
            }
            .navigationTitle("Coach Summary")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
