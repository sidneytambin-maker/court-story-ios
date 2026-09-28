import AppIntents
import Foundation

enum TennisIntentRoute {
    static func set(_ route: String) {
        UserDefaults.standard.set(route, forKey: "pendingIntentRoute")
    }
}

struct StartLiveScoringIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Match Scoring"
    static var description = IntentDescription("Open your saved matches to choose a score to resume.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        TennisIntentRoute.set("matches")
        return .result(dialog: "Opening Court Story for live scoring.")
    }
}

struct AddMatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Match"
    static var description = IntentDescription("Open Court Story to add a match.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        TennisIntentRoute.set("matches")
        return .result(dialog: "Opening Court Story to add a match.")
    }
}

struct AddTrainingSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Track Training Session"
    static var description = IntentDescription("Open Court Story to add a training session.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        TennisIntentRoute.set("training")
        return .result(dialog: "Opening Court Story to add training.")
    }
}

struct AddTournamentIntent: AppIntent {
    static var title: LocalizedStringResource = "Track Tournament"
    static var description = IntentDescription("Open Court Story to add a tournament.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        TennisIntentRoute.set("tournaments")
        return .result(dialog: "Opening Court Story to add a tournament.")
    }
}

struct ShowNextTournamentIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Next Tournament"
    static var description = IntentDescription("Open Court Story to the tournament area.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        TennisIntentRoute.set("tournaments")
        return .result(dialog: "Opening Court Story tournaments.")
    }
}

struct ShowRecentRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Recent Result"
    static var description = IntentDescription("Open Court Story to recent tennis activity.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        TennisIntentRoute.set("dashboard")
        return .result(dialog: "Opening Court Story recent activity.")
    }
}

struct TennisTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartLiveScoringIntent(), phrases: ["Resume match scoring in \(.applicationName)"], shortTitle: "Resume Match Scoring", systemImageName: "figure.tennis")
        AppShortcut(intent: AddMatchIntent(), phrases: ["Record a match in \(.applicationName)"], shortTitle: "Record Match", systemImageName: "plus.circle")
        AppShortcut(intent: AddTrainingSessionIntent(), phrases: ["Add training in \(.applicationName)"], shortTitle: "Add Training", systemImageName: "figure.run")
        AppShortcut(intent: AddTournamentIntent(), phrases: ["Track a tournament in \(.applicationName)"], shortTitle: "Track Tournament", systemImageName: "trophy")
        AppShortcut(intent: ShowNextTournamentIntent(), phrases: ["Show my next tournament in \(.applicationName)"], shortTitle: "Next Tournament", systemImageName: "calendar")
        AppShortcut(intent: ShowRecentRecordIntent(), phrases: ["Show my recent record in \(.applicationName)"], shortTitle: "Recent Record", systemImageName: "chart.bar")
    }
}
