#if os(watchOS)
import SwiftUI

struct WatchDateField: View {
    let title: String
    @Binding var date: Date
    private let calendar = Calendar.current

    var body: some View {
        NavigationLink(title) {
            Form {
                OrderedChoicePicker(title: "Day", selection: component(.day), values: Array(calendar.range(of: .day, in: .month, for: date) ?? 1..<32)) { String($0) }
                OrderedChoicePicker(title: "Month", selection: component(.month), values: Array(1...12)) { calendar.monthSymbols[$0 - 1] }
                OrderedChoicePicker(title: "Year", selection: component(.year), values: Array(min(1900, calendar.component(.year, from: date))...max(2100, calendar.component(.year, from: date)))) { String($0) }
            }.navigationTitle(title)
        }.accessibilityValue(date.fullTennisDate)
    }

    private func component(_ component: Calendar.Component) -> Binding<Int> {
        Binding(get: { calendar.component(component, from: date) }, set: { value in
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            parts.setValue(value, for: component)
            let requestedDay = parts.day ?? 1
            parts.day = 1
            guard let first = calendar.date(from: parts), let range = calendar.range(of: .day, in: .month, for: first) else { return }
            parts.day = min(requestedDay, range.count)
            date = calendar.date(from: parts) ?? date
        })
    }
}
#endif
