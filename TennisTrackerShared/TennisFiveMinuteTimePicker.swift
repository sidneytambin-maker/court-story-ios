import SwiftUI

struct FiveMinuteTimePicker: View {
    let title: String
    @Binding var date: Date

    private let hours = Array(0...23)
    private var minutes: [Int] {
        Array(Set(Array(stride(from: 0, through: 55, by: 5)) + [Calendar.current.component(.minute, from: date)])).sorted()
    }

    var body: some View {
        OrderedChoicePicker(title: "\(title) hour", selection: hourBinding, values: hours) { String(format: "%02d hours", $0) }
            .accessibilityIdentifier("\(title) hour")
        OrderedChoicePicker(title: "\(title) minutes", selection: minuteBinding, values: minutes) { String(format: "%02d minutes", $0) }
            .accessibilityIdentifier("\(title) minutes")
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.hour, from: date) },
            set: { update(hour: $0, minute: Calendar.current.component(.minute, from: date)) }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.minute, from: date) },
            set: { update(hour: Calendar.current.component(.hour, from: date), minute: $0) }
        )
    }

    private func update(hour: Int, minute: Int) {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0
        date = Calendar.current.date(from: components) ?? date
    }
}
