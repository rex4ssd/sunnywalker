// SunnyWalker — SunnyWalkerApp.swift  |  Day 14  |  AlarmKit killed-state routing via UserDefaults

import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Notification name

extension Notification.Name {
    static let alarmFired = Notification.Name("SunnyWalkerAlarmFired")
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Holds the alarm UUID from a notification that arrived before HomeView was ready.
    /// HomeView reads and clears this on `.onAppear` to handle the fully-killed-state case.
    var pendingAlarmID: String?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // AlarmKit killed-state routing: StopAlarmIntent stores the alarmID in UserDefaults
        // before bringing the app to foreground. Pick it up here so HomeView.checkPendingAlarm
        // can route to AlarmRingView once it appears.
        if let alarmKitID = UserDefaults.standard.string(forKey: "pendingAlarmKitAlarmID") {
            pendingAlarmID = alarmKitID
            UserDefaults.standard.removeObject(forKey: "pendingAlarmKitAlarmID")
        }

        return true
    }

    // Called when user taps an alarm notification banner (foreground or background).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleAlarmPayload(response.notification.request.content.userInfo)
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

    // Extracted so tests can call this directly without a real UNNotificationResponse.
    func handleAlarmPayload(_ userInfo: [AnyHashable: Any]) {
        guard let alarmID = userInfo["alarmID"] as? String else { return }
        pendingAlarmID = alarmID
        NotificationCenter.default.post(name: .alarmFired, object: alarmID)
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
