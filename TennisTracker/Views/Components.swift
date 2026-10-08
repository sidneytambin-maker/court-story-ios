import SwiftUI

struct AppThemePalette {
    let background: Color
    let groupedBackground: Color
    let rowBackground: Color
    let accent: Color
    let strongSurface: Color
}

extension AppTheme {
    var palette: AppThemePalette {
        switch self {
        case .tennis:
            return AppThemePalette(
                background: TennisSportStyle.ball,
                groupedBackground: TennisSportStyle.ball,
                rowBackground: TennisSportStyle.ball,
                accent: TennisSportStyle.court,
                strongSurface: TennisSportStyle.ink
            )
        case .classic:
            return AppThemePalette(
                background: Color(red: 0.95, green: 0.97, blue: 1.0),
                groupedBackground: Color(red: 0.90, green: 0.94, blue: 0.99),
                rowBackground: .white,
                accent: .blue,
                strongSurface: .blue
            )
        case .highContrast:
            return AppThemePalette(
                background: .black,
                groupedBackground: Color(red: 0.05, green: 0.05, blue: 0.05),
                rowBackground: Color(red: 0.10, green: 0.10, blue: 0.10),
                accent: .yellow,
                strongSurface: .black
            )
        case .system:
            return AppThemePalette(
                background: Color(.systemBackground),
                groupedBackground: Color(.systemGroupedBackground),
                rowBackground: Color(.secondarySystemGroupedBackground),
                accent: .accentColor,
                strongSurface: Color(.secondarySystemBackground)
            )
        }
    }
}

struct ThemedListBackground: ViewModifier {
    @EnvironmentObject private var store: TennisStore

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(store.data.settings.theme.palette.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(store.data.settings.theme.palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .listRowSeparatorTint(store.data.settings.theme == .tennis ? TennisSportStyle.court.opacity(0.18) : .secondary)
    }
}

extension View {
    func tennisThemedList() -> some View {
        modifier(ThemedListBackground())
    }
}

struct SummaryRow: View {
    let title: String
    let value: String
    var hint: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(value)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint(hint)
    }
}

struct TennisSection<Content: View>: View {
    @EnvironmentObject private var store: TennisStore
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Section { content.listRowBackground(store.data.settings.theme.palette.rowBackground) } header: {
            Text(title)
                .foregroundStyle(store.data.settings.theme == .tennis ? TennisSportStyle.ink : .primary)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

struct TennisDashboardHeader: View {
    let name: String
    var body: some View {
        Label {
            Text("Welcome, \(name)")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "tennisball.fill")
                .foregroundStyle(TennisSportStyle.court)
        }
            .foregroundStyle(TennisSportStyle.ink)
            .padding(.vertical, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Welcome, \(name)")
    }
}

struct DateShortcutPicker: View {
    let title: String
    @Binding var date: Date

    var body: some View {
        DatePicker(title, selection: $date, displayedComponents: .date)
            .datePickerStyle(.compact)
            .accessibilityHint("Double tap to edit the date. Use the quick date buttons for common changes.")
        HStack {
            Button("Yesterday") { date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date() }
            Button("Today") { date = Date() }
            Button("Tomorrow") { date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date() }
        }
        .buttonStyle(.bordered)
        .accessibilityElement(children: .contain)
    }
}

struct ScreenIntro: View {
    let title: String
    let summary: String

    var body: some View {
        Section {
            SummaryRow(title: title, value: summary)
        }
    }
}

struct AccessibleDateTimeEditor: View {
    let dateTitle: String
    let timeTitle: String
    @Binding var date: Date
    @Binding var hasStartTime: Bool
    var allowsUnspecifiedTime = true

    var body: some View {
        DatePicker(dateTitle, selection: $date, displayedComponents: .date)
            .datePickerStyle(.compact)
            .accessibilityValue(date.fullTennisDate)
            .accessibilityHint("Opens the native date picker.")

        HStack {
            Button("Today") { date = Calendar.current.dateByKeepingTime(from: date, on: Date()) }
            Button("Tomorrow") {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                date = Calendar.current.dateByKeepingTime(from: date, on: tomorrow)
            }
        }
        .buttonStyle(.bordered)

        if allowsUnspecifiedTime {
            Toggle("Start time specified", isOn: $hasStartTime)
        }

        if hasStartTime {
            FiveMinuteTimePicker(title: timeTitle, date: $date)
        }
    }
}

struct AccessibleDateRangeEditor: View {
    @Binding var startDate: Date
    @Binding var endDate: Date

    var body: some View {
        DatePicker("Start date", selection: $startDate, displayedComponents: .date)
            .datePickerStyle(.compact)
            .accessibilityLabel("Tournament start date")
            .accessibilityValue(startDate.fullTennisDate)
            .accessibilityHint("Opens the native date picker.")
            .onChange(of: startDate) { _, newStart in
                if endDate < newStart {
                    endDate = newStart
                }
            }

        DatePicker("End date", selection: $endDate, in: startDate..., displayedComponents: .date)
            .datePickerStyle(.compact)
            .accessibilityLabel("Tournament end date")
            .accessibilityValue(endDate.fullTennisDate)
            .accessibilityHint("Opens the native date picker. The end date cannot be before the start date.")
    }
}

struct DurationPicker: View {
    let title: String
    @Binding var minutes: Int
    var minimumMinutes = 5

    var body: some View {
        Section(title) {
            DurationFields(minutes: $minutes, minimumMinutes: minimumMinutes)
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String

    var body: some View {
        Label(title, systemImage: "tray")
            .font(.headline)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(title)
            .accessibilityHint(message)
    }
}

extension Binding where Value == Int {
    func clamped(min: Int = 0, max: Int = 999) -> Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue) },
            set: { wrappedValue = Swift.max(min, Swift.min(max, Int($0))) }
        )
    }
}
