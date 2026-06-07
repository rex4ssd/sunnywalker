// SunnyWalker — SunnyWalkerApp.swift  |  Day 16  |  AlarmKit auth on launch

import BackgroundTasks
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
        // Restore screen brightness if app was force-quit during bed-side mode
        BedSideManager.shared.restoreOnLaunch()

        // Register BGProcessingTask handler for background alarm auto-stop.
        // Must be called before the app finishes launching (iOS requirement).
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AlarmAutoStopService.bgTaskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false); return
            }
            Task { @MainActor in
                AlarmAutoStopService.shared.handleBGTask(processingTask)
            }
        }
        print("🛡️ BGTaskScheduler: registered \(AlarmAutoStopService.bgTaskIdentifier)")

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Register the alarm category WITH .customDismissAction so pressing ✕ on the banner
        // calls our didReceive handler (default behaviour would silently clear the banner and
        // never tell us). That's what lets a non-strict 貪睡模式 alarm turn off on ✕.
        let alarmCategory = UNNotificationCategory(
            identifier: "SUNNYWAKE_ALARM",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([alarmCategory])

        // AlarmKit killed-state routing: StopAlarmIntent stores the alarmID in UserDefaults
        // before bringing the app to foreground. Pick it up here so HomeView.checkPendingAlarm
        // can route to AlarmRingView once it appears.
        if let alarmKitID = UserDefaults.standard.string(forKey: "pendingAlarmKitAlarmID") {
            pendingAlarmID = alarmKitID
            UserDefaults.standard.removeObject(forKey: "pendingAlarmKitAlarmID")
            print("🚀 AppDelegate.didFinishLaunching: picked up killed-state pendingAlarmID=\(alarmKitID.prefix(8))")
        }

        return true
    }

    // Called when the user interacts with an alarm notification (tap on body, ✕ dismiss, action).
    //
    // ⚠️ UNUserNotificationCenter calls this on an ARBITRARY (usually background) queue. All of our
    // routing state — pendingAlarmID and the .alarmFired post that drives HomeView's fullScreenCover
    // — MUST be touched on the main thread. Doing it off-main triggers "Publishing changes from
    // background threads is not allowed" AND races the marker reads in HomeView.checkPendingAlarm,
    // which is how a ✕-dismissed alarm could still pop the ring screen back open. So we hop to the
    // main actor before doing anything stateful.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let action   = response.actionIdentifier
        let reqID    = response.notification.request.identifier
        let strict   = (userInfo["requireAppToStop"] as? Bool) ?? false
        let alarmID  = userInfo["alarmID"] as? String

        // Log the RAW action identifier so we can finally see, on-device, whether the ✕ button
        // delivers Dismiss, Default(tap-body), or a custom action for this banner.
        let actionName: String
        switch action {
        case UNNotificationDismissActionIdentifier: actionName = "DISMISS(✕)"
        case UNNotificationDefaultActionIdentifier: actionName = "DEFAULT(tap-body)"
        default:                                    actionName = "ACTION(\(action))"
        }
        print("🔔 didReceive: action=\(actionName) strict=\(strict) alarmID=\(alarmID.map { String($0.prefix(8)) } ?? "nil") reqID=\(reqID)")

        Task { @MainActor in
            defer { completionHandler() }
            switch action {
            case UNNotificationDismissActionIdentifier:
                // User pressed ✕. Non-strict → the alarm is done: clear every routing marker and
                // stamp a short-lived suppression so a racing .alarmFired / checkPendingAlarm does
                // NOT re-open the ring screen for this same fire. Strict → ignore (nags by design).
                guard let alarmID, let uuid = UUID(uuidString: alarmID) else { return }
                if strict {
                    print("🔔 didReceive: ✕ on STRICT alarm \(uuid.uuidString.prefix(8)) — ignored, nags continue")
                } else {
                    self.markAlarmDismissed(alarmID)
                    AlarmScheduler.shared.cancelNags(uuid)
                    print("🔔 didReceive: ✕ handled (non-strict) — alarm \(uuid.uuidString.prefix(8)) OFF, routing suppressed")
                }
            default:
                // Tap on the banner body (or default action) → open the wake-up screen.
                print("🔔 didReceive: tap → handleAlarmPayload")
                self.handleAlarmPayload(userInfo)
            }
        }
    }

    // Show notification banner + play sound even when app is already in foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let snd = notification.request.content.sound
        print("🔔 AppDelegate.willPresent: alarm fired in FOREGROUND → banner+sound; content.sound=\(String(describing: snd)) id=\(notification.request.identifier)")
        completionHandler([.banner, .sound])
    }

    // Extracted so tests can call this directly without a real UNNotificationResponse.
    // Now only ever called on the main thread (from the Task { @MainActor } above), so the
    // .alarmFired post — and therefore HomeView's state mutation — stays on main.
    func handleAlarmPayload(_ userInfo: [AnyHashable: Any]) {
        guard let alarmID = userInfo["alarmID"] as? String else {
            print("🔔 AppDelegate.handleAlarmPayload: no alarmID in payload — ignored")
            return
        }
        print("🔔 AppDelegate.handleAlarmPayload: alarmID=\(alarmID.prefix(8)) → set pending + post .alarmFired (main)")
        pendingAlarmID = alarmID
        NotificationCenter.default.post(name: .alarmFired, object: alarmID)
    }

    /// Record that the user turned this alarm off via the banner ✕. Clears every routing marker
    /// and stamps a short-lived suppression that HomeView checks before opening the ring screen —
    /// so a stray .alarmFired / checkPendingAlarm right after the dismiss can't re-trigger it.
    func markAlarmDismissed(_ alarmID: String) {
        pendingAlarmID = nil
        let d = UserDefaults.standard
        d.removeObject(forKey: "pendingAlarmKitAlarmID")
        d.set(alarmID, forKey: "dismissedAlarmID")
        d.set(Date().timeIntervalSince1970, forKey: "dismissedAlarmAt")
        print("🔔 markAlarmDismissed: \(alarmID.prefix(8)) — markers cleared, suppression stamped")
    }
}

// MARK: - App entry

@main
struct SunnyWalkerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var localization = LocalizationManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Drives live language switching: Text(LocalizedStringKey) re-localizes
                // from Localizable.xcstrings whenever the chosen language changes.
                .environment(\.locale, localization.locale)
                .task {
                    // Request mic + speech permissions (v1 path)
                    await PermissionManager.shared.requestAllPermissions()
                    // Request AlarmKit authorization — HomeView.onAppear will then
                    // sync all existing enabled alarms to AlarmKit (it has @Query alarms)
                    _ = await AlarmKitService.shared.requestAuthorization()
                }
        }
        .modelContainer(for: [Alarm.self, WakeRecord.self, VoiceClip.self])
    }
}
