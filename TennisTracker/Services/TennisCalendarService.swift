import EventKit
import Foundation

struct CalendarEventDraft: Equatable {
    var title: String
    var notes: String
    var startDate: Date
    var endDate: Date
    var location: String
    var deepLink: URL
    var isAllDay = false

    func confirmation(saved: Bool) -> String {
        guard saved else { return "Not added to your calendar. Calendar access was not granted or the event could not be saved." }
        let activity: String
        switch deepLink.host {
        case "training": activity = "training session"
        case "tournament": activity = "tournament"
        default: activity = "match"
        }
        let when = startDate.fullTennisDate + (isAllDay ? "" : " at \(startDate.shortTennisTime)")
        let whereText = location.isBlank ? "" : " at \(location)"
        return "Your \(activity) for \(when)\(whereText) has been successfully added to your calendar."
    }
}

enum TennisCalendarMapper {
    static func event(for match: MatchRecord) -> CalendarEventDraft {
        let start = match.hasStartTime ? match.date : Calendar.current.startOfDay(for: match.date)
        let end = match.hasStartTime
            ? start.addingTimeInterval(TimeInterval((match.hasExpectedDuration ? match.expectedDurationMinutes : 60) * 60))
            : Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return CalendarEventDraft(
            title: "Tennis: \(match.playerTeam) versus \(match.opponentSummary.fallback("opponent not recorded"))",
            notes: "Court Story match. \(TennisSummaryFormatter.match(match, style: .long)) \(match.notes)",
            startDate: start,
            endDate: end,
            location: [match.venue, match.location].filter { !$0.isBlank }.joined(separator: ", "),
            deepLink: URL(string: "tennistracker://match/\(match.id.uuidString)")!,
            isAllDay: !match.hasStartTime
        )
    }

    static func event(for session: TrainingSession, coaches: [TennisCoach] = [], players: [PlayerProfile] = []) -> CalendarEventDraft {
        let start = session.hasStartTime ? session.date : Calendar.current.startOfDay(for: session.date)
        let end = session.hasStartTime ? session.expectedEndDate
            : Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return CalendarEventDraft(
            title: "Tennis training: \(session.trainingType.rawValue)",
            notes: "\(TennisSummaryFormatter.training(session, style: .detailed, coaches: coaches, players: players)) \(session.notes)",
            startDate: start,
            endDate: end,
            location: [session.venue, session.location].filter { !$0.isBlank }.joined(separator: ", "),
            deepLink: URL(string: "tennistracker://training/\(session.id.uuidString)")!,
            isAllDay: !session.hasStartTime
        )
    }

    static func event(for tournament: TournamentRecord) -> CalendarEventDraft {
        CalendarEventDraft(
            title: "Tennis tournament: \(tournament.name.fallback("Unnamed tournament"))",
            notes: "\(TennisSummaryFormatter.tournament(tournament, style: .short)) \(tournament.goal) \(tournament.notes)",
            startDate: tournament.date,
            endDate: tournament.isAllDay
                ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: max(tournament.endDate, tournament.date))) ?? tournament.endDate
                : max(tournament.endDate, tournament.date.addingTimeInterval(60 * 60)),
            location: [tournament.venue, tournament.location].filter { !$0.isBlank }.joined(separator: ", "),
            deepLink: URL(string: "tennistracker://tournament/\(tournament.id.uuidString)")!,
            isAllDay: tournament.isAllDay || !tournament.hasStartTime
        )
    }
}

@MainActor
final class TennisCalendarService {
    static let shared = TennisCalendarService()

    private let store = EKEventStore()

    private init() {}

    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                return try await store.requestFullAccessToEvents()
            }
            return try await withCheckedThrowingContinuation { continuation in
                store.requestAccess(to: .event) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        } catch {
            return false
        }
    }

    func save(_ draft: CalendarEventDraft) async -> Bool {
        guard await requestAccess(), let calendar = store.defaultCalendarForNewEvents else { return false }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = draft.title
        event.notes = "\(draft.notes)\n\(draft.deepLink.absoluteString)"
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.location = draft.location
        event.isAllDay = draft.isAllDay

        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            return false
        }
    }
}

extension TennisStore {
    @discardableResult
    func addToCalendar(_ draft: CalendarEventDraft,
                       save: (CalendarEventDraft) async -> Bool = { await TennisCalendarService.shared.save($0) }) async -> String {
        let message = draft.confirmation(saved: await save(draft))
        announce(message)
        return message
    }
}
