import Foundation
import UserNotifications

enum TennisSound: String, CaseIterable, Identifiable, Codable {
    case bounce, racketStrike, racketSwing, ballCan, applause
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bounce: return "Tennis bounce"
        case .racketStrike: return "Racket strike"
        case .racketSwing: return "Racket swoosh"
        case .ballCan: return "New ball can"
        case .applause: return "Court applause"
        }
    }
    var filename: String {
        switch self {
        case .bounce: return "tennis-bounce.wav"
        case .racketStrike: return "tennis-racket-strike.wav"
        case .racketSwing: return "tennis-racket-swoosh.wav"
        case .ballCan: return "tennis-ball-can.wav"
        case .applause: return "tennis-applause.wav"
        }
    }
}

enum TennisReminderSound: String, CaseIterable, Identifiable, Codable {
    case tennis = "Selected tennis sound", system = "System sound", silent = "Silent"
    var id: String { rawValue }
}

enum TennisFeedbackEvent: Equatable { case save, completion, milestone }

struct TennisSoundSettings: Codable, Equatable {
    var selected: TennisSound = .bounce
    var reminders: TennisReminderSound = .tennis
    var savesEnabled = false
    var completionsEnabled = true
    var milestonesEnabled = true

    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        selected = TennisSound(rawValue: try values.decodeIfPresent(String.self, forKey: .selected) ?? "") ?? .bounce
        reminders = TennisReminderSound(rawValue: try values.decodeIfPresent(String.self, forKey: .reminders) ?? "") ?? .tennis
        savesEnabled = try values.decodeIfPresent(Bool.self, forKey: .savesEnabled) ?? false
        completionsEnabled = try values.decodeIfPresent(Bool.self, forKey: .completionsEnabled) ?? true
        milestonesEnabled = try values.decodeIfPresent(Bool.self, forKey: .milestonesEnabled) ?? true
    }

    func allows(_ event: TennisFeedbackEvent) -> Bool {
        switch event {
        case .save: return savesEnabled
        case .completion: return completionsEnabled
        case .milestone: return milestonesEnabled
        }
    }

    func notificationSound(bundle: Bundle = .main) -> UNNotificationSound? {
        switch reminders {
        case .silent: return nil
        case .system: return .default
        case .tennis:
            #if os(watchOS)
            // Named notification sounds are unavailable on watchOS; foreground audio is separate.
            return .default
            #else
            guard bundle.url(forResource: selected.filename, withExtension: nil) != nil else { return .default }
            return UNNotificationSound(named: UNNotificationSoundName(rawValue: selected.filename))
            #endif
        }
    }
}
