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

    /// Runtime-verified flag — only true after requestAuthorization() succeeds THIS session.
    /// Intentionally NOT derived from manager.authorizationState alone: iOS caches
    /// the user's "Alarms: ON" permission even after the com.apple.developer.alarmkit
    /// entitlement is removed from the binary, so authorizationState can return .authorized
    /// while manager.schedule() throws. Trusting the cached state would cause AlarmScheduler
    /// (UNNotification fallback) to bail out, leaving no alarm scheduled at all.
    private var _isAuthorized = false

    var isAuthorized: Bool { _isAuthorized }

    func requestAuthorization() async -> Bool {
        // Always call through to the system — never short-circuit on cached .authorized.
        // If the entitlement is missing from the binary, manager.requestAuthorization()
        // will throw even when authorizationState == .authorized, and we catch that here.
        do {
            let state = try await manager.requestAuthorization()
            _isAuthorized = state == .authorized
            print("AlarmKitService: authorization → \(state), isAuthorized=\(_isAuthorized)")
            if _isAuthorized {
                // AlarmKit now owns ringing. The always-on keep-alive mic (BackgroundListeningManager)
                // is both redundant and keeps the orange mic dot lit all the time. Kill it — from here
                // the ONLY mic we open is inside AlarmRingView during an actual ring (foreground
                // voice-stop). This also closes the cold-launch window where BGListen started before
                // authorization resolved (isAuthorized was still false in HomeView.task).
                BackgroundListeningManager.shared.stop()
            }
            return _isAuthorized
        } catch {
            _isAuthorized = false
            print("AlarmKitService: requestAuthorization failed (entitlement missing or denied) — \(error)")
            return false
        }
    }

    // MARK: - Presentation helpers

    private func makePresentation(title: String) -> AlarmPresentation {
        // stopButton is deprecated in iOS 26.1 (system uses slider gesture instead).
        // Keep for iOS 26.0 compatibility; system ignores it on 26.1+.
        let stopButton = AlarmButton(
            text: "我起床了",   // LocalizedStringResource literal — auto-localizes via Localizable.xcstrings (device language)
            textColor: .white,
            systemImageName: "sun.max.fill"
        )
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),   // Alert.title is LocalizedStringResource, not String
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

    #if DEBUG
    // MARK: - Schedule: 60-second test timer (P0 PoC — no stopIntent needed)

    @discardableResult
    func scheduleTestAlarm() async throws -> UUID {
        let id = UUID()
        let attrs = makeAttributes(alarmID: id.uuidString, title: "SunnyWalker 測試鬧鐘")
        // NOTE: custom AlarmKit sounds (.named) crash the Simulator's ToneLibrary (SpringBoard
        // aborts in -[TLAlertQueuePlayerController _prepareAudioEnvironmentForStateDescriptor:]).
        // Using the system default alarm tone here; the parent's recording still plays in-app.
        // To re-enable branded sound on a REAL device, add: sound: .named("sunny_wake.caf")
        _ = try await manager.schedule(
            id: id,
            configuration: .timer(
                duration: 60,
                attributes: attrs
            )
        )
        print("AlarmKitService: test timer scheduled — id=\(id), fires in 60s")
        return id
    }

    #endif // DEBUG

    // MARK: - Schedule: fixed-time one-shot (P1)

    @discardableResult
    func scheduleAlarm(at date: Date, label: String, alarmID: String) async throws -> UUID {
        let id = UUID()
        let title = label.isEmpty ? L("該起床囉！☀️") : label
        let attrs = makeAttributes(alarmID: alarmID, title: title)
        // On Simulator: omit sound — .named() crashes Simulator ToneLibrary (SpringBoard abort).
        // On real device: ring with the custom CAF.
        #if targetEnvironment(simulator)
        _ = try await manager.schedule(
            id: id,
            configuration: .alarm(
                schedule: .fixed(date),
                attributes: attrs,
                stopIntent: StopAlarmIntent(alarmID: alarmID)
            )
        )
        #else
        _ = try await manager.schedule(
            id: id,
            configuration: .alarm(
                schedule: .fixed(date),
                attributes: attrs,
                stopIntent: StopAlarmIntent(alarmID: alarmID),
                sound: .named("sunny_wake.caf")
            )
        )
        #endif
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
        let title = label.isEmpty ? L("該起床囉！☀️") : label
        let attrs = makeAttributes(alarmID: alarmID, title: title)

        // Qualify as AlarmKit.Alarm — the SwiftData model `Alarm` shadows the unqualified name.
        let time = AlarmKit.Alarm.Schedule.Relative.Time(hour: hour, minute: minute)

        let localeWeekdays = weekdays.compactMap { localeWeekday(from: $0) }
        let recurrence: AlarmKit.Alarm.Schedule.Relative.Recurrence =
            localeWeekdays.isEmpty ? .never : .weekly(localeWeekdays)

        let schedule = AlarmKit.Alarm.Schedule.relative(
            AlarmKit.Alarm.Schedule.Relative(time: time, repeats: recurrence)
        )

        #if targetEnvironment(simulator)
        _ = try await manager.schedule(
            id: id,
            configuration: .alarm(
                schedule: schedule,
                attributes: attrs,
                stopIntent: StopAlarmIntent(alarmID: alarmID)
            )
        )
        #else
        _ = try await manager.schedule(
            id: id,
            configuration: .alarm(
                schedule: schedule,
                attributes: attrs,
                stopIntent: StopAlarmIntent(alarmID: alarmID),
                sound: .named("sunny_wake.caf")
            )
        )
        #endif
        print("AlarmKitService: recurring alarm scheduled — id=\(id), \(hour):\(String(format: "%02d", minute)), weekdays=\(weekdays)")
        return id
    }

    // MARK: - Bulk sync (called from HomeView.onAppear after auth is granted)

    /// Sync all enabled alarms to AlarmKit in one pass.
    /// Called once on launch so pre-existing SwiftData alarms appear in the system alarm list.
    /// Errors per-alarm are swallowed — a single bad alarm should not block the rest.
    ///
    /// ⚠️ Race-fix: alarms queued via the legacy UNNotification path (AlarmScheduler)
    /// before AlarmKit auth was granted remain pending in UNUserNotificationCenter.
    /// Once AlarmKit takes over we must cancel them; otherwise the device fires BOTH
    /// a full-screen AlarmKit alert AND a 30-second UNNotification banner (double-fire).
    func syncAllEnabled(_ alarms: [Alarm]) async {
        guard isAuthorized else { return }
        // Cancel UNNotification only for alarms that AlarmKit successfully takes over.
        // If syncAlarm throws (entitlement revoked, API error, etc.) the UNNotification
        // stays active as a fallback — prevents an alarm from silently disappearing.
        var successIDs: [UUID] = []
        for alarm in alarms where alarm.isEnabled && AppSettings.groupAllowsFiring(alarm.effectiveGroupIndex) {
            do {
                try await syncAlarm(alarm)
                // 只有「AlarmKit 模式」的鬧鐘才需要清掉殘留 UNNotification（避免雙重響）。
                // 「通知模式」的鬧鐘故意保留它的 .timeSensitive UNNotification——那正是它的響鈴來源。
                if alarm.effectiveBackgroundMode == .alarmKit {
                    successIDs.append(alarm.id)
                }
            } catch {
                print("AlarmKitService: syncAlarm failed for \(alarm.id) — keeping UNNotification fallback. \(error)")
            }
        }
        for id in successIDs {
            AlarmScheduler.shared.cancel(id)
        }
        // Disabled alarms — or alarms whose group is off/hidden — should not fire via either path.
        // (AlarmKit disarm is handled by the foreground cancel-all + background arm-only-enabled cycle;
        // here we just make sure no UNNotification fallback lingers for them.)
        for alarm in alarms where !alarm.isEnabled || !AppSettings.groupAllowsFiring(alarm.effectiveGroupIndex) {
            AlarmScheduler.shared.cancel(alarm.id)
        }
        print("AlarmKitService: bulk sync complete — \(successIDs.count)/\(alarms.filter(\.isEnabled).count) synced to AlarmKit")
    }

    // MARK: - Sync (primary P1 API)

    /// Upsert an alarm into AlarmKit using `alarm.id` as the AlarmKit alarm UUID.
    /// Using the same UUID means calling this again replaces the existing entry — no cleanup needed.
    ///
    /// - If `alarm.isEnabled == false`: removes any existing AlarmKit entry.
    /// - If weekdays is non-empty: schedules a weekly recurring alarm.
    /// - If weekdays is empty: schedules a one-shot alarm at the next occurrence of the alarm's time.
    func syncAlarm(_ alarm: Alarm) async throws {
        // 鬧鐘本身關閉，或其群組被首頁關掉 / 超出群組數 → 從 AlarmKit 移除，不排程。
        guard alarm.isEnabled, AppSettings.groupAllowsFiring(alarm.effectiveGroupIndex) else {
            try removeAlarm(alarm)
            return
        }

        // ★ 2026-06-12 per-alarm 背景策略：「通知模式」不使用 AlarmKit（避免 force-quit 後無限響），
        //   改排 .timeSensitive UNNotification（響一次自動停）。移除任何既有 AlarmKit 條目 + 解除
        //   auto-stop keep-alive（這顆鬧鐘不需要背景保活）。UNNotification 由 AlarmScheduler 排。
        if alarm.effectiveBackgroundMode == .notification {
            try? manager.stop(id: alarm.id)      // 若上一版是 AlarmKit 模式且正在響 → 先靜音
            try? manager.cancel(id: alarm.id)     // 從系統排程移除，否則會跟通知雙重響
            AlarmAutoStopService.shared.disarm(alarmID: alarm.id)
            // ⚠️ 2026-06-12 根因修正：這裡【故意不】呼叫 AlarmScheduler.schedule()。
            //   syncAlarm 是在「進背景」時跑的，schedule() 會先 removePending 再 async add()；
            //   user 上滑 force-quit 會在 remove 之後、add 完成之前殺掉 app → 通知被清掉又沒補回
            //   → 「提醒模式什麼都沒發生」。.timeSensitive 通知是 repeats:true、會自己持續存在，
            //   只需在【前景】(editor 儲存 / AlarmList 開關 / HomeView.task 啟動) 排一次即可，
            //   背景不要再 remove-readd。這裡只負責把 AlarmKit 條目清乾淨。
            print("AlarmKitService.syncAlarm: \(alarm.id.uuidString.prefix(8)) → NOTIFICATION mode; AlarmKit removed, UNNotification left intact (scheduled in foreground)")
            return
        }

        let title = alarm.label.isEmpty ? L("該起床囉！☀️") : alarm.label
        let attrs = makeAttributes(alarmID: alarm.id.uuidString, title: title)
        let time = AlarmKit.Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
        let localeWeekdays = alarm.weekdays.compactMap { localeWeekday(from: $0) }

        let schedule: AlarmKit.Alarm.Schedule
        // nextFireDate is used by AlarmAutoStopService to arm the auto-stop timer.
        let nextFireDate: Date?
        if localeWeekdays.isEmpty {
            // No weekdays: one-shot at next occurrence of this hour:minute (today or tomorrow)
            var comps = DateComponents()
            comps.hour = alarm.hour
            comps.minute = alarm.minute
            comps.second = 0
            let fd = Calendar.current.nextDate(
                after: Date(),
                matching: comps,
                matchingPolicy: .nextTime
            ) ?? Date().addingTimeInterval(3600)
            schedule = .fixed(fd)
            nextFireDate = fd
        } else {
            let recurrence = AlarmKit.Alarm.Schedule.Relative.Recurrence.weekly(localeWeekdays)
            schedule = .relative(AlarmKit.Alarm.Schedule.Relative(time: time, repeats: recurrence))
            nextFireDate = AlarmAutoStopService.nextFireDate(
                hour: alarm.hour,
                minute: alarm.minute,
                weekdays: alarm.weekdays
            )
        }

        // ⚠️ AlarmKit will NOT re-arm an id that has already fired and been stopped — once an
        // alarm is in a terminal (.stopped/.countdown-finished) state, calling schedule() with
        // the same id is silently ignored. Symptom: a rung alarm whose time is later pushed back
        // never rings again. Explicitly cancelling first frees the id so the reschedule re-arms.
        //
        // Also: cancel() alone does NOT silence a currently-ringing alarm — stop() must be called
        // first. Without this, syncAlarm (called on every background transition) leaves the system
        // alarm ringing even after the occurrence is "removed" from the schedule.
        let stateBeforeSync = alarmState(id: alarm.id)
        if stateBeforeSync != "not-found" {
            print("AlarmKitService.syncAlarm: \(alarm.id.uuidString.prefix(8)) state=\(stateBeforeSync) — stop()+cancel() before reschedule")
        }
        try? manager.stop(id: alarm.id)
        try? manager.cancel(id: alarm.id)

        // Scheduling with the same id upserts (replaces) any existing AlarmKit entry.
        // On Simulator: omit sound — .named() crashes Simulator ToneLibrary.
        // On real device: ring with the custom CAF (or fallback to default name).
        let soundName = alarm.soundFileName.isEmpty ? "sunny_wake.caf" : alarm.soundFileName
        let idStr = alarm.id.uuidString

        // Stop-button behaviour depends on 貪睡模式 (requireAppToStop):
        //   • strict (true)  → StopAlarmIntent: opens the app + routes to AlarmRingView so the
        //                       child completes the wake task.
        //   • non-strict     → DismissAlarmIntent: background-only, just turns the alarm OFF with
        //                       no app open and no ring screen ("✕ 直接關閉鬧鐘").
        let strict = alarm.effectiveRequireAppToStop
        print("AlarmKitService: scheduling \(idStr.prefix(8)) strict(requireAppToStop)=\(strict) → stopIntent=\(strict ? "StopAlarmIntent" : "DismissAlarmIntent")")

        #if targetEnvironment(simulator)
        if strict {
            _ = try await manager.schedule(id: alarm.id, configuration: .alarm(
                schedule: schedule, attributes: attrs,
                stopIntent: StopAlarmIntent(alarmID: idStr)))
        } else {
            _ = try await manager.schedule(id: alarm.id, configuration: .alarm(
                schedule: schedule, attributes: attrs,
                stopIntent: DismissAlarmIntent(alarmID: idStr)))
        }
        #else
        if strict {
            _ = try await manager.schedule(id: alarm.id, configuration: .alarm(
                schedule: schedule, attributes: attrs,
                stopIntent: StopAlarmIntent(alarmID: idStr),
                sound: .named(soundName)))
        } else {
            _ = try await manager.schedule(id: alarm.id, configuration: .alarm(
                schedule: schedule, attributes: attrs,
                stopIntent: DismissAlarmIntent(alarmID: idStr),
                sound: .named(soundName)))
        }
        #endif
        print("AlarmKitService: synced \(alarm.id) — \(alarm.hour):\(String(format: "%02d", alarm.minute)), weekdays=\(alarm.weekdays)")

        // Arm the background auto-stop so AlarmKit alarm silences itself after ring duration
        // even when nobody opens the app (BGProcessingTask) or app is kept alive by audio
        // background mode (DispatchSourceTimer via beginBackgroundLifecycle).
        if let fd = nextFireDate {
            let ringSeconds = AppSettings.shared.alarmRingDurationMinutes * 60
            AlarmAutoStopService.shared.arm(alarmID: alarm.id, fireDate: fd, ringSeconds: ringSeconds)
        }
    }

    /// Remove an alarm from AlarmKit. Safe to call if the alarm was never scheduled.
    func removeAlarm(_ alarm: Alarm) throws {
        try? manager.stop(id: alarm.id)    // silence if currently ringing
        try? manager.cancel(id: alarm.id)
        AlarmAutoStopService.shared.disarm(alarmID: alarm.id)   // cancel BGTask / DispatchTimer
        print("AlarmKitService: removed \(alarm.id)")
    }

    // MARK: - Cancel / Stop (low-level, used internally and by StopAlarmIntent)

    func cancel(id: UUID) async throws {
        try manager.cancel(id: id)
    }

    func stop(id: UUID) async throws {
        // Log the alarm's state before and after stop so we can see if AlarmKit
        // accepts the stop request or silently ignores it (e.g. already-stopped state).
        // ★ disarm() 一定要執行——即使 manager.stop() 對 not-found 鬧鐘 throw。否則殘留 armed
        //   條目會讓 watchdog 每 5s 無限空轉、背景 keep-alive 永不 teardown、持續耗電（2026-06-10
        //   真機 log：stop(722A79FC) BEFORE=not-found 無限洗版、永遠沒有 AFTER）。放進 defer 保證收尾。
        defer { AlarmAutoStopService.shared.disarm(alarmID: id) }

        let before = alarmState(id: id)
        print("🔔 AlarmKitService.stop(\(id.uuidString.prefix(8))) — state BEFORE=\(before)")
        // AlarmKit 端已不存在 → 不要呼叫 manager.stop()（對 not-found 會 throw）；只靠 defer 清殘留登記。
        guard before != "not-found" else {
            print("🔔 AlarmKitService.stop(\(id.uuidString.prefix(8))) — not-found → disarm only (skip manager.stop)")
            return
        }
        try manager.stop(id: id)
        let after = alarmState(id: id)
        print("🔔 AlarmKitService.stop(\(id.uuidString.prefix(8))) — state AFTER=\(after)")
    }

    // MARK: - List

    var scheduledAlarms: [AlarmKit.Alarm] {   // AlarmKit's Alarm, not the SwiftData model
        (try? manager.alarms) ?? []           // manager.alarms is a throwing property
    }

    /// Human-readable alarm state string for logging.
    func alarmState(id: UUID) -> String {
        guard let alarm = (try? manager.alarms)?.first(where: { $0.id == id }) else {
            return "not-found"
        }
        return "\(alarm.state)"
    }
}
