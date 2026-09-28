import Foundation

enum TennisSettingsDestination: Hashable { case players, setup }

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab = "dashboard"
    @Published var targetID: UUID?
    @Published var activityRoute: TennisActivityRoute?
    @Published var settingsPath: [TennisSettingsDestination] = []

    func open(_ url: URL) {
        guard url.scheme == "tennistracker" else { return }
        activityRoute = TennisActivityRoute(url: url)
        let host = url.host?.lowercased()
        let idText = url.pathComponents.dropFirst().first
        targetID = idText.flatMap(UUID.init(uuidString:))

        switch host {
        case "match", "live":
            selectedTab = "matches"
        case "training":
            selectedTab = "training"
        case "tournament":
            selectedTab = "tournaments"
        case "player":
            selectedTab = "settings"
            settingsPath = [.players]
        case "settings":
            selectedTab = "settings"
            settingsPath = []
        default:
            selectedTab = "dashboard"
        }
    }

    func openPendingIntentRoute() {
        if let url = TennisNotificationInbox.take() { open(url); return }
        guard let route = UserDefaults.standard.string(forKey: "pendingIntentRoute") else { return }
        UserDefaults.standard.removeObject(forKey: "pendingIntentRoute")
        if route == "player" {
            selectedTab = "settings"
            settingsPath = [.players]
        } else { selectedTab = route }
    }
}
