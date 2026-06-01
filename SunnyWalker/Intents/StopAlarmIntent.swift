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

    func perform() throws -> some IntentResult {
        guard let uuid = UUID(uuidString: alarmID) else {
            return .result()
        }

        // Stop the AlarmKit alarm — safe to call even if already stopped/timed-out
        try? AlarmManager.shared.stop(id: uuid)

        // ── Routing ──────────────────────────────────────────────────────────
        // Killed-state: AppDelegate reads this key in application(_:didFinishLaunchingWithOptions:)
        UserDefaults.standard.set(alarmID, forKey: "pendingAlarmKitAlarmID")

        // Foreground/background state: HomeView's .onReceive(.alarmFired) catches this
        NotificationCenter.default.post(name: .alarmFired, object: alarmID)

        return .result()
    }
}
