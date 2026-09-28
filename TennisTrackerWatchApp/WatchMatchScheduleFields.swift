import SwiftUI

struct WatchMatchScheduleFields: View {
    @Binding var match: MatchRecord

    var body: some View {
        WatchDateField(title: "Match date", date: $match.date)
            .accessibilityIdentifier("watchMatchDatePicker")
        Toggle("Start time specified", isOn: $match.hasStartTime)
            .accessibilityIdentifier("matchStartTimeSpecified")
        if match.hasStartTime { FiveMinuteTimePicker(title: "Start time", date: $match.date) }
    }
}
