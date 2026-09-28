import SwiftUI
import WatchKit
import UserNotifications

@main
struct TennisTrackerWatchApp: App {
    @WKApplicationDelegateAdaptor(TennisWatchDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

final class TennisWatchDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() { UNUserNotificationCenter.current().delegate = self }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier,
              let url = TennisActivityRoute.notificationURL(userInfo: response.notification.request.content.userInfo,
                  identifier: response.notification.request.identifier, deliveredAt: response.notification.date) else { return }
        await MainActor.run {
            TennisNotificationInbox.enqueue(url)
            NotificationCenter.default.post(name: .tennisTrackerOpenURL, object: url)
        }
    }
    func handleActiveWorkoutRecovery() {
        NotificationCenter.default.post(name: .tennisWorkoutRecovery, object: nil)
    }
}

extension Notification.Name {
    static let tennisWorkoutRecovery = Notification.Name("tennisWorkoutRecovery")
}
