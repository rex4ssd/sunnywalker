// SunnyWalker — AlarmScheduler.swift  |  Day 2  |  UNUserNotificationCenter wrapper
//
// ⚠️ DEPRECATED — v1 path kept alongside AlarmKitService (v2) until device validation.
// Remove after confirming AlarmKit breaks silent/Focus mode and weekly repeats on real hardware.

import UserNotifications
import Foundation

@MainActor
final class AlarmScheduler {
    static let shared = AlarmScheduler()
    private init() {}

    // Schedule one notification request per active weekday so repeats honour the weekdays array.
    func schedule(alarm: Alarm) async throws {
        let center = UNUserNotificationCenter.current()

        print("🔔 AlarmScheduler.schedule: alarm=\(alarm.id.uuidString.prefix(8)) \(alarm.hour):\(String(format: "%02d", alarm.minute)) weekdays=\(alarm.weekdays) sound=\(alarm.soundFileName) AlarmKitAuthorized=\(AlarmKitService.shared.isAuthorized)")

        // Remove any stale requests (all 7 possible weekday slots + bare UUID fallback)
        let staleIDs = (1...7).map { "\(alarm.id.uuidString)-\($0)" } + [alarm.id.uuidString]
        center.removePendingNotificationRequests(withIdentifiers: staleIDs)

        // AlarmKit is the single source of truth once authorized. Scheduling both an
        // AlarmKit alarm AND a UNNotification makes the device fire twice (full-screen
        // alert + 30s banner). When AlarmKit is active this legacy path stands down and
        // only clears any leftover notifications. It still runs as a fallback on devices
        // where AlarmKit authorization was denied/unavailable.
        guard !AlarmKitService.shared.isAuthorized else {
            print("🔔 AlarmScheduler: AlarmKit authorized — standing down (UNNotification cleared)")
            return
        }

        // Self-heal: alarms recorded before the CAF export existed still point at the bundled
        // default sound. If a recording exists but no custom CAF is set, export one now so the
        // banner can ring the parent's voice on the next fire — no manual re-record needed.
        if !alarm.recordingName.isEmpty,
           alarm.soundFileName.isEmpty || alarm.soundFileName == "sunny_wake.caf" {
            if let caf = AlarmSoundExporter.exportLockScreenCAF(fromRecordingNamed: alarm.recordingName) {
                alarm.soundFileName = caf
                print("🔔 AlarmScheduler: self-healed custom sound → \(caf)")
            }
        }

        let content = UNMutableNotificationContent()
        content.title = L("起床囉！")
        content.body = alarm.recordingName.isEmpty
            ? L("早安！☀️ 快來聽鬧鐘")
            : L("點開來聽：%@", alarm.recordingName)
        // Sound selection (this UNNotification path is the one that actually fires while
        // AlarmKit is unauthorized — i.e. before the entitlement is approved):
        //   • Custom recording → ring its exported Library/Sounds/*.caf directly from the banner,
        //     so the parent's voice plays from the FIRST ring instead of only after tapping in.
        //     The export (AlarmSoundExporter) writes a mono 16-bit PCM CAF ≤30s — the format
        //     UNNotificationSound plays reliably (stereo/long CAFs are what used to fall through).
        //   • Otherwise → system default tone.
        let custom = alarm.soundFileName
        let wantsCustom = !custom.isEmpty && custom != "sunny_wake.caf" && !alarm.recordingName.isEmpty
        if wantsCustom {
            // Verify the CAF actually exists in Library/Sounds — UNNotificationSound(named:)
            // SILENTLY falls back to the default tone if the file is missing, wrong format, or
            // >30s. Checking here turns that invisible failure into a visible log line.
            let fm = FileManager.default
            let soundsDir = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Sounds", isDirectory: true)
            let cafPath = soundsDir.appendingPathComponent(custom).path
            let exists = fm.fileExists(atPath: cafPath)
            let dirList = (try? fm.contentsOfDirectory(atPath: soundsDir.path)) ?? []
            print("🔔 AlarmScheduler: custom sound check → name=\(custom) existsInLibrarySounds=\(exists) path=\(cafPath)")
            print("🔔 AlarmScheduler: Library/Sounds contents = \(dirList)")
            if exists {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: custom))
                print("🔔 AlarmScheduler: using CUSTOM banner sound → \(custom)")
            } else {
                content.sound = .default
                print("🔔 AlarmScheduler: ⚠️ custom CAF missing — FALLING BACK to default. (re-record or re-save to regenerate)")
            }
        } else {
            content.sound = .default
            print("🔔 AlarmScheduler: using DEFAULT banner sound (custom=\(custom) recording=\(alarm.recordingName.isEmpty ? "none" : "yes"))")
        }
        content.categoryIdentifier = "SUNNYWAKE_ALARM"
        content.userInfo = ["alarmID": alarm.id.uuidString]

        if alarm.weekdays.isEmpty {
            // One-shot: fire at the next occurrence of hour:minute (today or tomorrow).
            var comps = DateComponents()
            comps.hour = alarm.hour
            comps.minute = alarm.minute
            comps.second = 0
            guard let fireDate = Calendar.current.nextDate(
                after: Date(), matching: comps, matchingPolicy: .nextTime
            ) else { return }
            let dateParts = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateParts, repeats: false)
            let request = UNNotificationRequest(
                identifier: alarm.id.uuidString, content: content, trigger: trigger
            )
            try await center.add(request)
            await scheduleNagsIfNeeded(alarm: alarm, content: content, fireDate: fireDate, center: center)
            return
        }

        for weekday in alarm.weekdays {
            var components = DateComponents()
            components.hour = alarm.hour
            components.minute = alarm.minute
            components.weekday = weekday  // 1=Sun … 7=Sat, matches Alarm.weekdays convention

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: "\(alarm.id.uuidString)-\(weekday)",
                content: content,
                trigger: trigger)

            try await center.add(request)
        }
        // Strict mode for a repeating alarm: nag for the NEXT occurrence (one-shot). Renews on the
        // next app launch / re-arm. Keeps us well under the 64 pending-notification limit.
        if let next = nextOccurrence(for: alarm) {
            await scheduleNagsIfNeeded(alarm: alarm, content: content, fireDate: next, center: center)
        }
    }

    // MARK: - Strict mode ("貪睡模式") nag notifications

    /// When `requireAppToStop` is on, schedule a burst of follow-up notifications at +1…+N minutes
    /// after the alarm fires. Dismissing one (tapping ✕) just lets the next minute's nag fire, so
    /// the child can't silence the alarm without opening the app. `AlarmRingView` cancels these the
    /// moment the app actually opens for this alarm (`cancelNags`). N is capped by the configured
    /// ring duration (and 9) to stay within the per-app pending-notification limit.
    private func scheduleNagsIfNeeded(
        alarm: Alarm,
        content: UNNotificationContent,
        fireDate: Date,
        center: UNUserNotificationCenter
    ) async {
        guard alarm.effectiveRequireAppToStop else { return }
        let n = max(1, min(9, AppSettings.shared.alarmRingDurationMinutes))
        for k in 1...n {
            guard let nagDate = Calendar.current.date(byAdding: .minute, value: k, to: fireDate) else { continue }
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: nagDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let req = UNNotificationRequest(
                identifier: "\(alarm.id.uuidString)-nag-\(k)", content: content, trigger: trigger
            )
            try? await center.add(req)
        }
        print("🔔 AlarmScheduler: strict mode — scheduled \(n) nag(s) after \(fireDate)")
    }

    /// Soonest future fire date across an alarm's weekdays (for scheduling strict-mode nags).
    private func nextOccurrence(for alarm: Alarm) -> Date? {
        var comps = DateComponents()
        comps.hour = alarm.hour; comps.minute = alarm.minute; comps.second = 0
        let cal = Calendar.current
        if alarm.weekdays.isEmpty {
            return cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime)
        }
        var best: Date?
        for wd in alarm.weekdays {
            var c = comps; c.weekday = wd
            if let d = cal.nextDate(after: Date(), matching: c, matchingPolicy: .nextTime),
               best == nil || d < best! {
                best = d
            }
        }
        return best
    }

    /// Cancel only the strict-mode nag notifications for an alarm (leaves the main alarm intact so
    /// a repeating alarm still fires next time). Called when the app opens for the ringing alarm.
    func cancelNags(_ alarmID: UUID) {
        let ids = (1...9).map { "\(alarmID.uuidString)-nag-\($0)" }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        print("🔔 AlarmScheduler: cancelled nags for \(alarmID.uuidString.prefix(8))")
    }

    func cancel(_ alarmID: UUID) {
        let identifiers = (1...7).map { "\(alarmID.uuidString)-\($0)" }
            + (1...9).map { "\(alarmID.uuidString)-nag-\($0)" }
            + [alarmID.uuidString]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // Convenience: schedule if enabled, cancel if disabled.
    func syncWithModel(alarm: Alarm) async throws {
        if alarm.isEnabled {
            try await schedule(alarm: alarm)
        } else {
            cancel(alarm.id)
        }
    }
}
