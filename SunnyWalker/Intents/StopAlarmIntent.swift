// SunnyWalker — StopAlarmIntent.swift  |  Day 14  |  P1 AlarmKit stop button → foreground + AlarmRingView

import AppIntents
import AlarmKit

/// Fired when the user taps the stop button on the AlarmKit lock-screen UI.
///
/// Flow:
///   Lock screen stop tap
///   → StopAlarmIntent.perform() runs
///   → `.foreground(.immediate)` brings app to foreground
///   → Posts `.alarmFired` notification (caught by HomeView.onReceive when in foreground)
///   → Stores in UserDefaults (caught by AppDelegate on killed-state launch)
///   → HomeView routes to AlarmRingView for the matching alarm
struct StopAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "停止鬧鐘"
    static var description = IntentDescription("關掉 SunnyWalker 鬧鐘並開啟起床互動畫面。")

    /// Bring app to foreground immediately.
    /// Replaces deprecated `openAppWhenRun = true` (deprecated iOS 26.0).
    static var supportedModes: IntentModes {
        .foreground(.immediate)
    }

    @Parameter(title: "鬧鐘 ID")
    var alarmID: String

    init() { alarmID = "" }
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        print("⏹️ StopAlarmIntent.perform (STRICT/貪睡) alarmID=\(alarmID.prefix(8))")
        guard let uuid = UUID(uuidString: alarmID) else {
            return .result()
        }

        // Stop the AlarmKit alarm — safe to call even if already stopped/timed-out.
        // AlarmManager.stop(id:) is async, so perform() must be async too.
        try? AlarmManager.shared.stop(id: uuid)
        // Note: AlarmAutoStopService.disarm() is called automatically when the main app comes to
        // foreground (via AlarmKitService.stop → disarm, triggered from enterForegroundAlarmMode).
        // We cannot call it here because StopAlarmIntent is compiled in a separate target.

        // ── Routing ──────────────────────────────────────────────────────────
        // Strict (貪睡) alarms must open the app so the child completes the wake task.
        // Killed-state: AppDelegate reads this key in application(_:didFinishLaunchingWithOptions:)
        UserDefaults.standard.set(alarmID, forKey: "pendingAlarmKitAlarmID")

        // Foreground/background state: HomeView's .onReceive(.alarmFired) catches this
        NotificationCenter.default.post(name: .alarmFired, object: alarmID)
        print("⏹️ StopAlarmIntent: strict → opening app + routing to AlarmRingView")

        return .result()
    }
}

/// Stop intent for NON-strict (貪睡 off) alarms.
///
/// Wired in for alarms whose `requireAppToStop == false`. Pressing the AlarmKit stop button just
/// turns the alarm OFF — it runs in the BACKGROUND, so it does NOT open the app and does NOT route
/// to the wake-up screen. (This is the AlarmKit-path equivalent of "✕ on the banner just closes the
/// alarm"; the old UNNotification dismiss handler only runs when AlarmKit is unauthorized.)
struct DismissAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "關閉鬧鐘"
    static var description = IntentDescription("關掉 SunnyWalker 鬧鐘，不開啟 App。")

    /// Background only — never bring the app to the foreground.
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "鬧鐘 ID")
    var alarmID: String

    init() { alarmID = "" }
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        print("⏹️ DismissAlarmIntent.perform (NON-strict) alarmID=\(alarmID.prefix(8))")
        guard let uuid = UUID(uuidString: alarmID) else { return .result() }

        // Just stop the alarm. No app open, no ring screen.
        try? AlarmManager.shared.stop(id: uuid)
        // Note: AlarmAutoStopService.disarm() runs later via BGTask or on next app foreground.
        // Cannot call it here — DismissAlarmIntent is compiled in a separate target.

        // Defensive: clear any stale routing marker and stamp the same short-lived suppression
        // HomeView honours, so a racing .alarmFired / checkPendingAlarm can't re-open the ring.
        let d = UserDefaults.standard
        d.removeObject(forKey: "pendingAlarmKitAlarmID")
        d.set(alarmID, forKey: "dismissedAlarmID")
        d.set(Date().timeIntervalSince1970, forKey: "dismissedAlarmAt")
        print("⏹️ DismissAlarmIntent: stopped \(alarmID.prefix(8)) — no app open, routing suppressed")

        return .result()
    }
}
