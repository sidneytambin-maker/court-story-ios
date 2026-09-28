import SwiftUI

struct DashboardInsightsSection: View {
    let progress: TennisPlayerProgress
    let mode: TrackingMode
    let chooseFocus: () -> Void
    let editGoals: () -> Void
    let reviewMatch: () -> Void
    let planTraining: () -> Void

    var body: some View {
        TennisOptionalSection("Training & goals", mode: mode, identifier: "dashboardInsights") {
            if !progress.trainingTypes.isEmpty {
                heading("Training, last 30 days")
                ForEach(progress.trainingTypes) { item in
                    SummaryRow(title: item.focus, value: item.summary)
                }
            }
            if !progress.focus.isEmpty {
                heading("Focus, last 30 days")
                ForEach(progress.focus) { item in
                    TennisFocusDashboardRow(item: item, maximum: progress.focus.map(\.sessions).max() ?? 1)
                }
            }
            if !progress.trainingNeedingFocus.isEmpty {
                Button("Choose Training Focus", systemImage: "scope", action: chooseFocus)
                    .accessibilityIdentifier("dashboardChooseFocus")
                    .accessibilityHint("Choose the focus for your most recent training session without a focus.")
            }
            if !progress.suggestions.isEmpty {
                heading("What to work on")
                ForEach(progress.suggestions) { suggestion in
                    SummaryRow(title: suggestion.source, value: suggestion.detail)
                        .accessibilityAction(named: suggestion.source.hasPrefix("Your match review") ? "Review a Match" : "Edit Goals and Priorities") {
                            if suggestion.source.hasPrefix("Your match review") { reviewMatch() } else { editGoals() }
                        }
                }
            }
            Button("Edit Goals and Priorities", systemImage: "target", action: editGoals)
                .accessibilityIdentifier("dashboardEditGoals")
            Button("Review a Match", systemImage: "square.and.pencil", action: reviewMatch)
                .accessibilityIdentifier("dashboardReviewMatch")
            Button("Plan Next Training Session", systemImage: "calendar.badge.plus", action: planTraining)
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }
}
