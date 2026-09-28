import SwiftUI

struct DurationFields: View {
    @Binding var minutes: Int
    var minimumMinutes = 5

    private let minuteChoices = Array(0...59)

    var body: some View {
        OrderedChoicePicker(title: "Duration hours", selection: hoursBinding, values: Array(0...max(8, minutes / 60))) {
            $0 == 1 ? "1 hour" : "\($0) hours"
        }
        .accessibilityIdentifier("durationHours")
        OrderedChoicePicker(title: "Duration minutes", selection: minutesBinding, values: minuteChoices) {
            "\($0) minutes"
        }
        .accessibilityIdentifier("durationMinutes")
    }

    private var hoursBinding: Binding<Int> {
        Binding(
            get: { minutes / 60 },
            set: { minutes = max(minimumMinutes, ($0 * 60) + (minutes % 60)) }
        )
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { minutes % 60 },
            set: { minutes = max(minimumMinutes, ((minutes / 60) * 60) + $0) }
        )
    }
}
