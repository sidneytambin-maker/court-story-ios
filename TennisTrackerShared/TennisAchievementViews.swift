import SwiftUI

struct TennisAchievementBadge: View {
    let achievement: TennisAchievement
    @Environment(\.colorScheme) private var colorScheme
    private var accent: Color { colorScheme == .dark ? TennisSportStyle.ball : TennisSportStyle.court }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(achievement.earned ? TennisSportStyle.ball : Color.primary.opacity(0.06))
            Image(systemName: achievement.symbol).font(.system(size: 27, weight: .semibold))
                .foregroundStyle(achievement.earned ? TennisSportStyle.ink : accent)
        }
        .frame(width: 58, height: 64)
        .overlay(alignment: .bottomTrailing) {
            if achievement.earned {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(TennisSportStyle.ink, TennisSportStyle.ball)
                    .font(.system(size: 18)).offset(x: 3, y: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

struct TennisAchievementRow: View {
    let achievement: TennisAchievement
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            TennisAchievementBadge(achievement: achievement)
            VStack(alignment: .leading, spacing: 5) {
                Text(achievement.title).font(.headline)
                Text(achievement.earned ? achievement.celebration : achievement.requirement).font(.callout)
                if achievement.earned { Label("Earned", systemImage: "checkmark").font(.caption.bold()) }
                else {
                    Text("\(achievement.progress) of \(achievement.target)").font(.caption.bold()).monospacedDigit()
                    ProgressView(value: achievement.fraction)
                        .tint(colorScheme == .dark ? TennisSportStyle.ball : TennisSportStyle.court)
                        .accessibilityHidden(true)
                }
            }.fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(achievement.title)
        .accessibilityValue(achievement.summary)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("achievement." + achievement.id)
    }
}

struct TennisAchievementsView: View {
    let achievements: [TennisAchievement]
    @State private var showEarned = false
    private var earned: [TennisAchievement] { achievements.filter(\.earned) }
    var body: some View {
        TennisList {
            Text("\(earned.count) of \(achievements.count) achievements earned")
                .font(.headline).accessibilityIdentifier("achievementCollectionSummary")
                .accessibilityHint("Based on this player's saved activity history. Deleted test records no longer count. Each badge describes exactly what earns it.")
            Picker("Show achievements", selection: $showEarned) {
                Text("To collect").tag(false)
                Text("Earned").tag(true)
            }.accessibilityIdentifier("achievementFilterPicker")
            ForEach(achievements.filter { $0.earned == showEarned }) { TennisAchievementRow(achievement: $0) }
            if showEarned && earned.isEmpty { Text("Your collection starts with your first saved activity.") }
            if !showEarned && earned.count == achievements.count { Text("Every badge earned. What a tennis journey!") }
        }.navigationTitle("Achievements")
    }
}

struct TennisAchievementsSummary: View {
    let achievements: [TennisAchievement]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(achievements.filter(\.earned).count) of \(achievements.count) earned").font(.headline)
            if let next = achievements.filter({ !$0.earned }).max(by: { $0.fraction < $1.fraction }) {
                TennisAchievementRow(achievement: next)
            } else { Text("Every badge earned. Congratulations!") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Achievements")
        .accessibilityValue("\(achievements.filter(\.earned).count) of \(achievements.count) earned. " + nextSummary)
        .accessibilityHint("Opens your earned badges and the achievements still to collect.")
        .accessibilityIdentifier("achievementsLink")
    }
    private var nextSummary: String {
        guard let next = achievements.filter({ !$0.earned }).max(by: { $0.fraction < $1.fraction }) else { return "Every badge earned. Congratulations!" }
        return "Next target: " + next.title + ". " + next.summary
    }
}

struct TennisWeeklyReview: View {
    let records: [TennisAchievementRecord]
    let playerID: UUID?
    let weekStart: Date
    private var interval: DateInterval { TennisReportingWeek.interval(containing: weekStart) }
    private var selected: [TennisAchievementRecord] { records.filter { $0.playerID == playerID && $0.date >= interval.start && $0.date < interval.end } }
    private func count(_ metric: String) -> Int { Set(selected.filter { $0.metrics.contains(metric) }.map(\.id)).count }
    var body: some View {
        TennisList {
            Text(TennisReportingWeek.summary(containing: weekStart)).font(.headline)
                .accessibilityIdentifier("notificationWeekRange")
            Text("\(count("training")) training sessions. " + TennisDurationFormatter.text(seconds: selected.filter { $0.metrics.contains("training") }.reduce(0) { $0 + $1.seconds }))
            Text("\(count("singles")) singles matches, \(count("singlesWin")) wins, \(count("singlesLoss")) losses, \(count("singlesDraw")) draws, \(count("singlesRetired")) retired.")
            Text("\(count("doubles")) doubles matches, \(count("doublesWin")) wins, \(count("doublesLoss")) losses, \(count("doublesDraw")) draws, \(count("doublesRetired")) retired.")
            Text("\(count("tournament")) tournament entries in this week.")
            Text("\(count("focus")) training sessions with a specific focus. \(count("reflection")) with notes or progress recorded.")
        }.navigationTitle("Weekly Review")
    }
}
