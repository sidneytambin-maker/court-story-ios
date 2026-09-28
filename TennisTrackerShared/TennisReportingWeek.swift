import Foundation

enum TennisReportingWeek {
    static func calendar(in calendar: Calendar) -> Calendar {
        var reporting = Calendar(identifier: .gregorian)
        reporting.timeZone = calendar.timeZone
        reporting.locale = calendar.locale
        reporting.firstWeekday = 2
        reporting.minimumDaysInFirstWeek = 4
        return reporting
    }

    static func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let calendar = self.calendar(in: calendar)
        return calendar.dateInterval(of: .weekOfYear, for: date)!
    }

    static func summary(containing date: Date, calendar: Calendar = .current) -> String {
        let calendar = self.calendar(in: calendar)
        let interval = interval(containing: date, calendar: calendar)
        let sunday = calendar.date(byAdding: .day, value: -1, to: interval.end)!
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.locale = calendar.locale ?? .current
        format.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return "\(format.string(from: interval.start)) to \(format.string(from: sunday))"
    }

    static func timelineDates(from date: Date, calendar: Calendar = .current) -> [Date] {
        let calendar = self.calendar(in: calendar)
        let midnight = calendar.startOfDay(for: date)
        // Include future boundaries even if the system delays a requested widget reload.
        return [date] + (1...8).compactMap { calendar.date(byAdding: .day, value: $0, to: midnight) }
    }
}
