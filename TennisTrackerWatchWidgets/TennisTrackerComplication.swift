import SwiftUI
import WidgetKit

private struct TennisEntry: TimelineEntry {
    let date: Date
    let glance: TennisGlance
    let kind: TennisGlanceKind
    var relevance: TimelineEntryRelevance? { TimelineEntryRelevance(score: glance.relevanceScore, duration: 60) }
}

private struct TennisTimeline: TimelineProvider {
    let kind: TennisGlanceKind
    func placeholder(in context: Context) -> TennisEntry {
        TennisEntry(date: .now, glance: TennisGlance.make(kind: kind, snapshot: .empty), kind: kind)
    }
    func getSnapshot(in context: Context, completion: @escaping (TennisEntry) -> Void) {
        completion(entry(at: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TennisEntry>) -> Void) {
        let now = Date()
        let snapshot = TennisSharedSnapshotFile.read() ?? .empty
        let dates = kind == .week ? TennisReportingWeek.timelineDates(from: now)
            : (0..<60).map { now.addingTimeInterval(Double($0) * 60) }
        let entries = dates.map { date in
            return TennisEntry(date: date, glance: TennisGlance.make(kind: kind, snapshot: snapshot, now: date), kind: kind)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }
    private func entry(at date: Date) -> TennisEntry {
        TennisEntry(date: date, glance: TennisGlance.make(kind: kind, snapshot: TennisSharedSnapshotFile.read() ?? .empty, now: date), kind: kind)
    }
}

private struct TennisComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TennisEntry

    var body: some View {
        Group {
            if family == .accessoryInline {
                Text("\(entry.glance.title): \(entry.glance.detail)")
            } else if family == .accessoryCorner {
                Image(systemName: entry.kind.symbol)
                    .widgetAccentable()
                    .accessibilityLabel(entry.glance.accessibilitySummary)
                    .widgetLabel { Text(entry.glance.circularDetail).accessibilityHidden(true) }
            } else if family == .accessoryCircular {
                VStack {
                    Image(systemName: entry.kind.symbol)
                    Text(entry.glance.circularDetail).font(.caption2).lineLimit(2).minimumScaleFactor(0.7)
                }
            } else {
                VStack(alignment: .leading) {
                    Label(entry.glance.title, systemImage: entry.kind.symbol).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    Text(entry.glance.detail).lineLimit(2).minimumScaleFactor(0.7)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.glance.accessibilitySummary)
        .accessibilityRepresentation { Text(entry.glance.accessibilitySummary) }
        .privacySensitive()
        .widgetURL(entry.glance.url)
    }
}

struct TennisTrackerComplication: Widget {
    let selection: TennisGlanceKind

    init() { self.init(selection: .current) }
    init(selection: TennisGlanceKind) { self.selection = selection }

    var kind: String { selection.widgetKind }
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TennisTimeline(kind: selection)) { TennisComplicationView(entry: $0) }
            .configurationDisplayName(selection.name)
            .description(selection.description)
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

@main
struct TennisTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        TennisTrackerComplication(selection: .current)
        TennisTrackerComplication(selection: .next)
        TennisTrackerComplication(selection: .week)
        TennisTrackerComplication(selection: .latest)
        TennisTrackerComplication(selection: .startTraining)
    }
}
