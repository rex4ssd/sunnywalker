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

        // Remove any stale requests (all 7 possible weekday slots + bare UUID fallback)
        let staleIDs = (1...7).map { "\(alarm.id.uuidString)-\($0)" } + [alarm.id.uuidString]
        center.removePendingNotificationRequests(withIdentifiers: staleIDs)

        let content = UNMutableNotificationContent()
        content.title = L("起床囉！")
        content.body = alarm.recordingName.isEmpty
            ? L("早安！☀️ 快來聽鬧鐘")
            : L("點開來聽：%@", alarm.recordingName)
        content.sound = UNNotificationSound(
            named: UNNotificationSoundName(rawValue: alarm.soundFileName)
        )
        content.categoryIdentifier = "SUNNYWAKE_ALARM"
        content.userInfo = ["alarmID": alarm.id.uuidString]

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
    }

    func cancel(_ alarmID: UUID) {
        let identifiers = (1...7).map { "\(alarmID.uuidString)-\($0)" } + [alarmID.uuidString]
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers)
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
