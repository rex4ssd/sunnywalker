// SunnyWalker — SunnyWalkerApp.swift  |  Day 16  |  AlarmKit auth on launch

import AppVersionKit
import BackgroundTasks
import KidsDiagnostics   // MetricKit 崩潰／凍結報告落盤（App Store 版的閃退證據）
import KidsParentalUI
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
        // Grandfathering (free-era installs → lifetime Pro, free) is resolved asynchronously from
        // Apple's signed AppTransaction inside StoreService.start() (called from SunnyWalkerApp's
        // .task). It's account-bound, so it no longer depends on launch-ordering or on-device state —
        // nothing to do here at didFinishLaunching.

        // Record the build number the very first time the app is ever launched (idempotent — only
        // writes on the first run). Powers the "首次啟動 First launch" row in Settings' version card.
        AppVersion.registerFirstLaunch()

        // 生產環境崩潰／凍結證據：MetricKit 在「下一次啟動」送交前次的診斷，這裡落成
        // Documents/diagnostics/*.json（不上網、無 PII）。Rex 回報 App Store 版「選音檔／錄音頁
        // 有時整個 crash」但拉不到 log——之後用 devicectl 拉 Documents/diagnostics 就有 stack。
        KidsDiagnostics.start()

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

        // 🔬 冷啟動鑑識：重建上一輪背景/被殺的時間軸（自動停鈴失效診斷）。
        Task { @MainActor in
            AlarmAutoStopService.shared.logLifecycleForensics(context: "cold-launch")
        }

        return true
    }

    // 🔬 forensics markers — 用來區分「只是進背景」vs「app 被關閉/殺掉」。
    func applicationDidEnterBackground(_ application: UIApplication) {
        UserDefaults.standard.set(Date(), forKey: AlarmAutoStopService.lastDidEnterBgKey)
    }

    // ⚠️ 注意：force-quit（從多工列上滑）通常『不會』觸發 willTerminate（app 已 suspended 直接被殺）。
    // 但系統主動回收或某些關閉路徑會觸發 — 有值就是強訊號：上次是被終止，不是單純背景。
    func applicationWillTerminate(_ application: UIApplication) {
        UserDefaults.standard.set(Date(), forKey: AlarmAutoStopService.lastWillTerminateKey)
        print("🔬 AppDelegate.applicationWillTerminate — app 正在被終止 \(Date())")
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
                // 2026-06-12 UX：提醒模式（.notification）的橫幅，聲音播完就自動停了，
                // 沒有「關鬧鐘」需求 → 點橫幅只把 app 帶回主畫面（系統開 app 就是主畫面），
                // 不設 pendingAlarmID、不發 .alarmFired、不開 AlarmRingView。
                // AlarmKit / 舊 fallback 路徑維持原行為（開喚醒畫面）。
                if (userInfo["backgroundMode"] as? String) == AlarmBackgroundMode.notification.rawValue {
                    // 孩子已回應 → 取消殘留的 strict-mode nag 連發（以前由 AlarmRingView 開啟時取消，
                    // 現在不開 ring view，得在這裡收掉，否則 nag 會繼續轟炸 N 分鐘）。
                    if let alarmID, let uuid = UUID(uuidString: alarmID) {
                        AlarmScheduler.shared.cancelNags(uuid)
                    }
                    print("🔔 didReceive: tap on NOTIFICATION-mode banner → home screen only (no ring view), nags cancelled")
                } else {
                    // Tap on the banner body (or default action) → open the wake-up screen.
                    print("🔔 didReceive: tap → handleAlarmPayload")
                    self.handleAlarmPayload(userInfo)
                }
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

    // Shared-library unlock session, needed by KidsFamilyShelf's inner gate. Kept in sync with the
    // app's own AppSettings unlock window (gate success / 立即解鎖 / 立即上鎖) so the parent isn't
    // re-challenged on the shelf inside an already-unlocked window. In-memory by design.
    @State private var parentalSession = ParentalUnlockSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(parentalSession)
                // Drives live language switching: Text(LocalizedStringKey) re-localizes
                // from Localizable.xcstrings whenever the chosen language changes.
                .environment(\.locale, localization.locale)
                .task {
                    // 家長頁尾段（共用件）的「延長解鎖 N 分」stepper 讀寫 session.defaultMinutes；
                    // 開機用 app 自己存的分鐘數餵進去（共用件 stepper 範圍 1–30，夾一下）。
                    parentalSession.defaultMinutes = min(30, max(1, AppSettings.shared.parentalUnlockDurationMinutes))
                    // AppSettings 的解鎖窗是持久化的、共用 session 是 in-memory：重開 app 若窗還沒過，
                    // 把剩餘時間餵回 session，家長頁尾段的「立即上鎖／倒數」才跟首頁的免驗證狀態一致。
                    let remaining = AppSettings.shared.remainingParentalUnlockSeconds()
                    if remaining > 0 {
                        parentalSession.unlock(minutes: max(1, Int((Double(remaining) / 60).rounded(.up))))
                    }
                    // Open the StoreKit Transaction.updates listener + refresh entitlement BEFORE any
                    // purchase UI. Missing the listener loses async transactions (Ask-to-Buy approval,
                    // Family Sharing, refund/revocation). Safe to call repeatedly — start() is idempotent.
                    StoreService.shared.start()
                    // Request mic + speech permissions (v1 path)
                    await PermissionManager.shared.requestAllPermissions()
                    // Request AlarmKit authorization — HomeView.onAppear will then
                    // sync all existing enabled alarms to AlarmKit (it has @Query alarms)
                    _ = await AlarmKitService.shared.requestAuthorization()
                }
        }
        .modelContainer(for: [Alarm.self, WakeRecord.self, VoiceClip.self, TodoPlayRecord.self, AlarmRingLog.self])
    }
}
