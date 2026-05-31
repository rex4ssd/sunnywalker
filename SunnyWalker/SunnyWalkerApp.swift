// SunnyWalker — SunnyWalkerApp.swift  |  Day 7  |  AppDelegate + UNUserNotificationCenterDelegate

import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Notification name

extension Notification.Name {
    static let alarmFired = Notification.Name("SunnyWalkerAlarmFired")
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Called when user taps an alarm notification banner (foreground or background).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let alarmID = response.notification.request.content.userInfo["alarmID"] as? String {
            NotificationCenter.default.post(name: .alarmFired, object: alarmID)
        }
        completionHandler()
    }

    // Show notification banner + play sound even when app is already in foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - App entry

@main
struct SunnyWalkerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await PermissionManager.shared.requestAllPermissions()
                }
        }
        .modelContainer(for: Alarm.self)
    }
}
