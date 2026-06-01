// SunnyWalker — AlarmKitService.swift  |  Day 15  |  syncAlarm / removeAlarm for P1 completion

import AlarmKit
import AppIntents
import Foundation

// MARK: - Metadata

/// Metadata attached to each AlarmKit alarm so `StopAlarmIntent` can route
/// to the correct `Alarm` record when the stop button fires.
nonisolated struct SunnyWalkerAlarmMetadata: AlarmMetadata {
    var alarmID: String
}

// MARK: - Service

/// Wraps AlarmKit scheduling, cancellation, and authorization.
///
/// v1 `AlarmScheduler` (UNUserNotificationCenter) is kept side-by-side until P1
/// confirms AlarmKit works on a real device with the approved entitlement.
///
/// ⚠️  AlarmKit requires a special entitlement from Apple.
///    Apply via: Xcode → Signing & Capabilities → "+" → "Alarms"
///    then submit the entitlement request at developer.apple.com.
///    Without the approved entitlement, `requestAuthorization()` will throw.
@MainActor
final class AlarmKitService {

    static let shared = AlarmKitService()
    private init() {}

    private let manager = AlarmManager.shared

    // MARK: - Authorization

    var isAuthorized: Bool {
        manager.authorizationState == .authorized
    }

    func requestAuthorization() async -> Bool {
        switch manager.authorizationState {
        case .authorized:
            return true
        case .notDetermined:
            do {
                let state = try await manager.requestAuthorization()
                print("AlarmKitService: authorization → \(state)")
                return state == .authorized
            } catch {
                print("AlarmKitService: requestAuthorization failed — \(error)")
                return false
            }
        case .denied:
            print("AlarmKitService: denied — user must enable in Settings → SunnyWalker")
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Presentation helpers

    private func makePresentation(title: String) -> AlarmPresentation {
        // stopButton is deprecated in iOS 26.1 (system uses slider gesture instead).
        // Keep for iOS 26.0 compatibility; system ignores it on 26.1+.
        let stopButton = AlarmButton(
            text: "我起床了",
            textColor: .white,
            systemImageName: "sun.max.fill"
        )
        let alert = AlarmPresentation.Alert(
            title: title,
            stopButton: stopButton
        )
        return AlarmPresentation(alert: alert)
    }

    private func makeAttributes(
        alarmID: String,
        title: String
    ) -> AlarmAttributes<SunnyWalkerAlarmMetadata> {
        AlarmAttributes(
            presentation: makePresentation(title: title),
            metadata: SunnyWalkerAlarmMetadata(alarmID: alarmID),  // carries alarmID to intent
            tintColor: .orange
        )
    }

    // MARK: - Weekday mapping

    /// Converts the Alarm model's weekday integer (1=Sun … 7=Sat) to `Locale.Weekday`.
    /// Alarm model mirrors Calendar.weekdaySymbols ordering; Locale.Weekday uses named cases.
    private func localeWeekday(from modelWeekday: Int) -> Locale.Weekday? {
        switch modelWeekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return nil
        }
    }

    // MARK: - Schedule: 60-second test timer (P0 PoC — no stopIntent needed)

    @discardableResult
    func scheduleTestAlarm() async throws -> UUID {
        let id = UUID()
        let attrs = makeAttributes(alarmID: id.uuidString, title: "SunnyWalker PoC 測試！")
        // AlarmKit supports .caf and .mp3; .aiff does NOT work (verified WWDC25)
        let config = AlarmConfiguration.timer(
            duration: 60,
            attributes: attrs,
            sound: .named("totoro_breath.caf")
        )
        try await manager.schedule(id: id, configuration: config)
        print("AlarmKitService: test timer scheduled — id=\(id), fires in 60s")
        return id
    }

    // MARK: - Schedule: fixed-time one-shot (P1)

    @discardableResult
    func scheduleAlarm(at date: Date, label: String, alarmID: String) async throws -> UUID {
        let id = UUID()
        let title = label.isEmpty ? "該起床囉！☀️" : label
        let attrs = makeAttributes(alarmID: alarmID, title: title)
        let config = AlarmConfiguration(
            schedule: .fixed(date),
            attributes: attrs,
            sound: .named("totoro_breath.caf"),
            stopIntent: StopAlarmIntent(alarmID: alarmID)
        )
        try await manager.schedule(id: id, configuration: config)
        print("AlarmKitService: fixed alarm scheduled — id=\(id), fires at \(date)")
        return id
    }

    // MARK: - Schedule: recurring weekly (P1)

    /// Schedules a weekly recurring alarm.
    /// `weekdays` mirrors Alarm model: [1=Sun, 2=Mon, …, 7=Sat].
    @discardableResult
    func scheduleRecurringAlarm(
        hour: Int,
        minute: Int,
        weekdays: [Int],
        label: String,
        alarmID: String
    ) async throws -> UUID {
        let id = UUID()
        let title = label.isEmpty ? "該起床囉！☀️" : label
        let attrs = makeAttributes(alarmID: alarmID, title: title)

        let time = Alarm.Schedule.Relative.Time(hour: hour, minute: minute)

        let localeWeekdays = weekdays.compactMap { localeWeekday(from: $0) }
        let recurrence: Alarm.Schedule.Relative.Recurrence
        if localeWeekdays.isEmpty {
            // No weekdays — fire once at next occurrence of this time (not repeating)
            recurrence = .never
        } else {
            recurrence = .weekly(localeWeekdays)
        }

        let schedule = Alarm.Schedule.relative(
            Alarm.Schedule.Relative(time: time, repeats: recurrence)
        )

        let config = AlarmConfiguration(
            schedule: schedule,
            attributes: attrs,
            stopIntent: StopAlarmIntent(alarmID: alarmID)
        )
        try await manager.schedule(id: id, configuration: config)
        print("AlarmKitService: recurring alarm scheduled — id=\(id), \(hour):\(String(format: "%02d", minute)), weekdays=\(weekdays)")
        return id
    }

    // MARK: - Bulk sync (called from HomeView.onAppear after auth is granted)

    /// Sync all enabled alarms to AlarmKit in one pass.
    /// Called once on launch so pre-existing SwiftData alarms appear in the system alarm list.
    /// Errors per-alarm are swallowed — a single bad alarm should not block the rest.
    func syncAllEnabled(_ alarms: [Alarm]) async {
        guard isAuthorized else { return }
        for alarm in alarms where alarm.isEnabled {
            try? await syncAlarm(alarm)
        }
        print("AlarmKitService: bulk sync complete — \(alarms.filter(\.isEnabled).count) alarms")
    }

    // MARK: - Sync (primary P1 API)

    /// Upsert an alarm into AlarmKit using `alarm.id` as the AlarmKit alarm UUID.
    /// Using the same UUID means calling this again replaces the existing entry — no cleanup needed.
    ///
    /// - If `alarm.isEnabled == false`: removes any existing AlarmKit entry.
    /// - If weekdays is non-empty: schedules a weekly recurring alarm.
    /// - If weekdays is empty: schedules a one-shot alarm at the next occurrence of the alarm's time.
    func syncAlarm(_ alarm: Alarm) async throws {
        guard alarm.isEnabled else {
            try await removeAlarm(alarm)
            return
        }

        let title = alarm.label.isEmpty ? "該起床囉！☀️" : alarm.label
        let attrs = makeAttributes(alarmID: alarm.id.uuidString, title: title)
        let time = Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
        let localeWeekdays = alarm.weekdays.compactMap { localeWeekday(from: $0) }

        let schedule: Alarm.Schedule
        if localeWeekdays.isEmpty {
            // No weekdays: one-shot at next occurrence of this hour:minute (today or tomorrow)
            var comps = DateComponents()
            comps.hour = alarm.hour
            comps.minute = alarm.minute
            comps.second = 0
            var fireDate = Calendar.current.nextDate(
                after: Date(),
                matching: comps,
                matchingPolicy: .nextTime
            ) ?? Date().addingTimeInterval(3600)
            schedule = .fixed(fireDate)
        } else {
            let recurrence = Alarm.Schedule.Relative.Recurrence.weekly(localeWeekdays)
            schedule = .relative(Alarm.Schedule.Relative(time: time, repeats: recurrence))
        }

        let soundName = alarm.soundFileName.isEmpty ? "totoro_breath.caf" : alarm.soundFileName
        let config = AlarmConfiguration(
            schedule: schedule,
            attributes: attrs,
            sound: .named(soundName),
            stopIntent: StopAlarmIntent(alarmID: alarm.id.uuidString)
        )
        // Scheduling with the same id upserts (replaces) any existing AlarmKit entry.
        try await manager.schedule(id: alarm.id, configuration: config)
        print("AlarmKitService: synced \(alarm.id) — \(alarm.hour):\(String(format: "%02d", alarm.minute)), weekdays=\(alarm.weekdays)")
    }

    /// Remove an alarm from AlarmKit. Safe to call if the alarm was never scheduled.
    func removeAlarm(_ alarm: Alarm) async throws {
        try? await manager.cancel(id: alarm.id)
        print("AlarmKitService: removed \(alarm.id)")
    }

    // MARK: - Cancel / Stop (low-level, used internally and by StopAlarmIntent)

    func cancel(id: UUID) async throws {
        try await manager.cancel(id: id)
    }

    func stop(id: UUID) async throws {
        try await manager.stop(id: id)
    }

    // MARK: - List

    var scheduledAlarms: [Alarm] {
        manager.alarms
    }
}
