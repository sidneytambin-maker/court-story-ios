import SwiftUI
import Charts

struct TennisResultDashboardRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let totals: TennisResultTotals
    let symbol: String
    var trainingMatchCount = 0
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(totals.count.formatted()).font(.headline).monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
                    Text("\(totals.count) matches").font(.headline).monospacedDigit()
                }
            }
            Chart {
                ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                    BarMark(xStart: .value("Start", slices.prefix(index).reduce(0) { $0 + $1.count }),
                            xEnd: .value("End", slices.prefix(index + 1).reduce(0) { $0 + $1.count }),
                            y: .value("Results", "Results"), height: .ratio(0.8))
                        .foregroundStyle(slice.color)
                }
            }
            .chartXScale(domain: 0...max(1, totals.count))
            .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
            .frame(height: compact ? 10 : 18)
            .background(.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            if compact {
                Text("\(totals.wins) wins, \(totals.losses) losses, \(totals.draws) draws")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 3), alignment: .leading, spacing: 8) {
                    metric("Wins", value: totals.wins, symbol: "checkmark", color: slices[0].color)
                    metric("Losses", value: totals.losses, symbol: "xmark", color: slices[1].color)
                    metric("Draws", value: totals.draws, symbol: "equal", color: slices[2].color)
                }
            }
            if totals.retired > 0 { Text("\(totals.retired) retired").font(.callout) }
            if trainingMatchCount > 0 { Text(trainingContext).font(.callout) }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(title)
        .accessibilityValue(totals.summary + (trainingMatchCount > 0 ? " " + trainingContext : ""))
        .accessibilityIdentifier("resultSummary." + title)
    }

    private var trainingContext: String { "Includes \(trainingMatchCount) \(trainingMatchCount == 1 ? "match" : "matches") played during training." }

    private var slices: [(count: Int, color: Color)] {
        [(totals.wins, colorScheme == .dark ? .mint : TennisSportStyle.court),
         (totals.losses, colorScheme == .dark ? .pink : Color(red: 0.60, green: 0.09, blue: 0.23)),
         (totals.draws, colorScheme == .dark ? .cyan : Color(red: 0.08, green: 0.25, blue: 0.62)),
         (totals.retired, .secondary)]
    }

    private func metric(_ name: String, value: Int, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(color)
            Text(value.formatted()).font(.headline).monospacedDigit()
            Text(name).font(.caption).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TennisFocusDashboardRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: TennisFocusProgress
    let maximum: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.focus).font(.headline)
            Text("\(item.sessions) \(item.sessions == 1 ? "session" : "sessions")").font(.callout).fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(item.sessions), total: Double(max(1, maximum)))
                .tint(colorScheme == .dark ? TennisSportStyle.ball : TennisSportStyle.court)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(item.focus)
        .accessibilityValue("\(item.sessions) \(item.sessions == 1 ? "session" : "sessions")")
        .accessibilityHint("Counts sessions including this focus. A session can include several focuses. Total duration is in the training summary.")
    }
}
