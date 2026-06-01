// SunnyWalker — AlarmKitService.swift  |  Day 13  |  P0 AlarmKit PoC wrapper

import AlarmKit
import Foundation

// MARK: - Metadata

/// Metadata attached to each AlarmKit alarm so we can route back to the
/// correct Alarm record when the stop intent fires (P1 wires this through AppIntents).
nonisolated struct SunnyWalkerAlarmMetadata: AlarmMetadata {
    /// The Alarm.id this AlarmKit entry corresponds to.
    var alarmID: String
}

// MARK: - Service

/// Wraps AlarmKit scheduling, cancellation, and authorization.
/// v1 `AlarmScheduler` (UNUserNotificationCenter) is kept side-by-side until P1 confirms
/// AlarmKit works on a real device with the approved entitlement.
///
/// ⚠️  AlarmKit requires a special entitlement from Apple.
///    To apply: Xcode → Signing & Capabilities → "+" → "Alarms",
///    then submit an entitlement request at developer.apple.com.
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

    /// Request AlarmKit permission. Call once on app launch (or lazily before scheduling).
    /// Returns `true` if authorized, `false` if denied or error.
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
            print("AlarmKitService: denied — user must enable in Settings")
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Presentation helpers

    private func makePresentation(title: String = "該起床囉！☀️") -> AlarmPresentation {
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
        title: String = "該起床囉！☀️"
    ) -> AlarmAttributes<SunnyWalkerAlarmMetadata> {
        AlarmAttributes(
            presentation: makePresentation(title: title),
            tintColor: .orange   // GhibliColors.lanternOrange equivalent
        )
    }

    // MARK: - Schedule: 60-second test timer (P0 PoC)

    /// Schedule a one-shot 60-second countdown timer for PoC validation.
    /// Lock device after tapping — alarm should fire and break silent/Focus mode.
    @discardableResult
    func scheduleTestAlarm() async throws -> UUID {
        let id = UUID()
        let attrs = makeAttributes(alarmID: id.uuidString, title: "SunnyWalker PoC 測試！")
        let config = AlarmConfiguration.timer(duration: 60, attributes: attrs)
        try await manager.schedule(id: id, configuration: config)
        print("AlarmKitService: test timer scheduled — id=\(id), fires in 60s")
        return id
    }

    // MARK: - Schedule: fixed-time alarm (used by P1 full integration)

    /// Schedule a one-shot alarm at a specific Date.
    @discardableResult
    func scheduleAlarm(at date: Date, label: String, alarmID: String) async throws -> UUID {
        let id = UUID()
        let attrs = makeAttributes(alarmID: alarmID, title: label.isEmpty ? "該起床囉！☀️" : label)
        let config = AlarmConfiguration(schedule: .fixed(date), attributes: attrs)
        try await manager.schedule(id: id, configuration: config)
        print("AlarmKitService: fixed alarm scheduled — id=\(id), fires at \(date)")
        return id
    }

    // MARK: - Schedule: recurring weekly alarm (used by P1 full integration)

    /// Schedule a weekly recurring alarm.
    /// `weekdays` mirrors the Alarm model: [1=Sun, 2=Mon, …, 7=Sat].
    @discardableResult
    func scheduleRecurringAlarm(
        hour: Int,
        minute: Int,
        weekdays: [Int],
        label: String,
        alarmID: String
    ) async throws -> UUID {
        let id = UUID()
        let attrs = makeAttributes(alarmID: alarmID, title: label.isEmpty ? "該起床囉！☀️" : label)

        let time = Alarm.Schedule.Relative.Time(hour: hour, minute: minute)
        let days = weekdays.compactMap { Alarm.Schedule.Relative.Weekday(rawValue: $0) }

        let schedule: Alarm.Schedule
        if days.isEmpty {
            // No weekdays selected — treat as daily (all days)
            let allDays = (1...7).compactMap { Alarm.Schedule.Relative.Weekday(rawValue: $0) }
            let recurrence = Alarm.Schedule.Relative.Recurrence.weekly(allDays)
            schedule = .relative(Alarm.Schedule.Relative(time: time, repeats: recurrence))
        } else {
            let recurrence = Alarm.Schedule.Relative.Recurrence.weekly(days)
            schedule = .relative(Alarm.Schedule.Relative(time: time, repeats: recurrence))
        }

        let config = AlarmConfiguration(schedule: schedule, attributes: attrs)
        try await manager.schedule(id: id, configuration: config)
        print("AlarmKitService: recurring alarm scheduled — id=\(id), \(hour):\(String(format: "%02d", minute)), weekdays=\(weekdays)")
        return id
    }

    // MARK: - Cancel

    func cancel(id: UUID) async throws {
        try await manager.stop(id: id)
        print("AlarmKitService: cancelled alarm id=\(id)")
    }

    // MARK: - List

    var scheduledAlarms: [Alarm] {
        manager.alarms
    }
}
