import SwiftUI
import UserNotifications
import UIKit
import BackgroundTasks

final class TennisTrackerAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in CourtConnect.shared.registeredForPush(deviceToken) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in CourtConnect.shared.status="Push registration failed. Confirmations remain available in Connect." }
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier:"com.inclusophy.tennistracker.connect-refresh",using:nil) { task in
            let work=Task { @MainActor in
                guard UIApplication.shared.isProtectedDataAvailable else { task.setTaskCompleted(success:false); return }
                let store=TennisStore()
                do { if store.storageError==nil && CourtConnect.shared.isSignedIn { try await CourtConnect.shared.sync(store.data) }; task.setTaskCompleted(success:true) }
                catch { task.setTaskCompleted(success:false) }
                CourtConnect.scheduleBackground()
            }
            task.expirationHandler={ work.cancel() }
        }
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard let id=notification.request.content.userInfo["connect_notification"] as? String else { return [] }
        return await CourtConnect.shared.shouldPresentNotification(id) ? [.banner,.list,.sound] : []
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.userInfo["connect_notification"] is String {
            await MainActor.run { UserDefaults.standard.set(true,forKey:"CourtConnectOpenPending"); NotificationCenter.default.post(name:Notification.Name("CourtConnectOpen"),object:nil) }
            return
        }
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
