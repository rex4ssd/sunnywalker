// SunnyWalker — PermissionManager.swift  |  Day 19  |  AlarmKit auth added to first-launch flow

import UserNotifications
import AVFoundation
import Speech
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    private init() {}

    @Published var notificationsGranted = false

    // MARK: - All permissions (call once on first launch)

    func requestAllPermissions() async {
        await requestNotificationPermission()
        await requestMicrophonePermission()
        await requestSpeechPermission()
        // AlarmKit — request after other permissions so the system dialog order is predictable
        _ = await AlarmKitService.shared.requestAuthorization()
        await logNotificationSettings()
    }

    /// DIAGNOSTIC: dump the EFFECTIVE notification settings. When the lock-screen alarm shows a
    /// banner but plays NO sound, the cause is almost always one of these — not our code:
    ///   • soundSetting == .disabled  → the user turned OFF "Sounds" for the app in iOS Settings.
    ///   • authorizationStatus != .authorized → notifications (or sound) were never granted.
    ///   • Ring/Silent switch on Silent, or a Focus/DND filtering the app → a normal
    ///     UNNotificationSound is muted (only AlarmKit / Critical Alerts ring through Silent).
    /// These can't be read directly, but soundSetting/authStatus narrow it down fast.
    func logNotificationSettings() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        func d(_ v: UNNotificationSetting) -> String {
            switch v { case .enabled: return "enabled"; case .disabled: return "disabled"; default: return "notSupported" }
        }
        print("""
        🔔 NotifSettings: authStatus=\(s.authorizationStatus.rawValue) \
        sound=\(d(s.soundSetting)) alert=\(d(s.alertSetting)) \
        lockScreen=\(d(s.lockScreenSetting)) notifCenter=\(d(s.notificationCenterSetting)) \
        alertStyle=\(s.alertStyle.rawValue) criticalAlert=\(d(s.criticalAlertSetting)) \
        timeSensitive=\(d(s.timeSensitiveSetting))
        ⤷ If sound=disabled → turn on iOS Settings ▸ SunnyWalker ▸ Sounds. If sound=enabled but \
        still silent on lock, the Ring/Silent switch or a Focus is muting it (a plain notification \
        can't ring through Silent — only AlarmKit / Critical Alerts can).
        """)
    }

    // MARK: - Individual requests

    func requestNotificationPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            notificationsGranted = granted
        } catch {
            notificationsGranted = false
        }
    }

    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsGranted = settings.authorizationStatus == .authorized
    }

    func requestMicrophonePermission() async {
        _ = await AVAudioApplication.requestRecordPermission()
    }

    func requestSpeechPermission() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in cont.resume() }
        }
    }
}
