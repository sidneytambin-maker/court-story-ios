import SwiftUI
import UserNotifications
import UIKit

final class TennisTrackerAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier,
              let url = TennisActivityRoute.notificationURL(userInfo: response.notification.request.content.userInfo,
                  identifier: response.notification.request.identifier, deliveredAt: response.notification.date) else { return }
        await MainActor.run {
            TennisNotificationInbox.enqueue(url)
            NotificationCenter.default.post(name: .tennisTrackerOpenURL, object: url)
        }
    }
}

@main
struct TennisTrackerApp: App {
    @UIApplicationDelegateAdaptor(TennisTrackerAppDelegate.self) private var appDelegate
    @StateObject private var store = TennisStore()

    var body: some Scene {
        WindowGroup {
            TennisTrackerRootView()
                .environmentObject(store)
                .onAppear {
                    IPhoneWatchSyncService.shared.configure(store: store)
                }
        }
    }
}
