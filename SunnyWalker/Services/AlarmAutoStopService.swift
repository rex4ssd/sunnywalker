// SunnyWalker — AlarmAutoStopService.swift
// 鬧鐘自動停止服務 (State Machine Push-down pattern)
//
// 架構：兩層保障
//   Layer 1 — BGProcessingTask: iOS 在 stopAt 附近喚醒 app，呼叫 AlarmKitService.stop()
//             適合：app 完全 suspended、距離鬧鐘還有數分鐘以上
//   Layer 2 — AVAudioPlayer(靜音) + DispatchSourceTimer:
//             app 進背景前 10 分鐘內有鬧鐘即啟動靜音音訊保持 app 活著，
//             DispatchSourceTimer 精準計時 stopAt 到了就 stop()
//             適合：距離鬧鐘 ≤ 10 分鐘、app 已在背景活著
//
// 整合點：
//   - AlarmKitService.syncAlarm()  → arm()
//   - AlarmKitService.stop(id:)    → disarm()
//   - HomeView.enterBackgroundAlarmMode() → beginBackgroundLifecycle()
//   - HomeView.scenePhase → .active      → checkAndStopOverdue()
//   - SunnyWalkerApp.AppDelegate.didFinishLaunching → BGTask handler registration

import AVFoundation
import BackgroundTasks
import Foundation

@MainActor
final class AlarmAutoStopService {

    static let shared = AlarmAutoStopService()
    private init() {}

    // MARK: - Constants

    static let bgTaskIdentifier = "com.sunnywalker.alarm.autostop"

    /// 進背景時距離 stopAt 在這個分鐘數內 → 啟動靜音音訊 + DispatchTimer
    private let lookAheadMinutes: Double = 10

    // MARK: - Persisted armed state

    private struct ArmedEntry: Codable {
        let alarmID: UUID
        let stopAt: Date        // fireDate + ringSeconds
    }

    private var armedAlarms: [UUID: ArmedEntry] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "AlarmAutoStop.armed"),
                  let decoded = try? JSONDecoder().decode([ArmedEntry].self, from: data)
            else { return [:] }
            return Dictionary(uniqueKeysWithValues: decoded.map { ($0.alarmID, $0) })
        }
        set {
            let array = Array(newValue.values)
            if let data = try? JSONEncoder().encode(array) {
                UserDefaults.standard.set(data, forKey: "AlarmAutoStop.armed")
            }
        }
    }

    // MARK: - In-process (Layer 2)

    private var dispatchTimers: [UUID: DispatchSourceTimer] = [:]
    private var silentPlayer: AVAudioPlayer?

    // MARK: - Public API

    /// 排好一個鬧鐘 → 記錄 stopAt，提交 BGTask
    func arm(alarmID: UUID, fireDate: Date, ringSeconds: Int) {
        let stopAt = fireDate.addingTimeInterval(Double(ringSeconds))
        var current = armedAlarms
        current[alarmID] = ArmedEntry(alarmID: alarmID, stopAt: stopAt)
        armedAlarms = current
        print("🛡️ AlarmAutoStop.arm: \(alarmID.uuidString.prefix(8)) stopAt=\(stopAt.formatted(.dateTime.hour().minute().second()))")
        rescheduleBGTask()
    }

    /// 使用者或自動已停 → 清除記錄與 DispatchTimer
    func disarm(alarmID: UUID) {
        var current = armedAlarms
        current.removeValue(forKey: alarmID)
        armedAlarms = current
        dispatchTimers[alarmID]?.cancel()
        dispatchTimers.removeValue(forKey: alarmID)
        print("🛡️ AlarmAutoStop.disarm: \(alarmID.uuidString.prefix(8)) — \(current.count) still armed")
        if dispatchTimers.isEmpty { stopSilentAudio() }
        rescheduleBGTask()
    }

    /// scenePhase → .active 時呼叫：停掉所有「早該停了」的鬧鐘
    func checkAndStopOverdue() {
        let now = Date()
        let overdue = armedAlarms.values.filter { $0.stopAt <= now }
        guard !overdue.isEmpty else { return }
        print("🛡️ AlarmAutoStop.checkAndStopOverdue: \(overdue.count) overdue")
        Task { @MainActor in
            for entry in overdue {
                print("🛡️ checkAndStopOverdue: stopping \(entry.alarmID.uuidString.prefix(8))")
                try? await AlarmKitService.shared.stop(id: entry.alarmID)
                disarm(alarmID: entry.alarmID)
            }
        }
    }

    /// 進背景後（syncAllEnabled 完成後）呼叫
    /// 距離最近的 stopAt ≤ lookAheadMinutes → 啟動靜音音訊 + DispatchTimer
    func beginBackgroundLifecycle() {
        let now = Date()
        let upcoming = armedAlarms.values.filter { $0.stopAt > now }
        guard !upcoming.isEmpty else {
            print("🛡️ AlarmAutoStop.beginBackgroundLifecycle: no armed alarms — BGTask only")
            return
        }

        let nearestStop = upcoming.map { $0.stopAt }.min()!
        let secondsUntilStop = nearestStop.timeIntervalSince(now)
        guard secondsUntilStop <= lookAheadMinutes * 60 else {
            print("🛡️ AlarmAutoStop.beginBackgroundLifecycle: nearest stopAt in \(Int(secondsUntilStop/60)) min — BGTask only (> \(Int(lookAheadMinutes)) min threshold)")
            return
        }

        print("🛡️ AlarmAutoStop.beginBackgroundLifecycle: nearest stopAt in \(Int(secondsUntilStop))s — starting audio keep-alive + DispatchTimers")
        startSilentAudio()
        for entry in upcoming { installDispatchTimer(entry) }
    }

    // MARK: - BGProcessingTask (Layer 1)

    /// BGTask handler — 在 SunnyWalkerApp.AppDelegate.didFinishLaunching 裡註冊
    func handleBGTask(_ task: BGProcessingTask) {
        print("🛡️ AlarmAutoStop.handleBGTask fired")
        task.expirationHandler = {
            print("🛡️ AlarmAutoStop.handleBGTask: expired before completion")
        }
        let now = Date()
        let overdue = armedAlarms.values.filter { $0.stopAt <= now }
        if overdue.isEmpty {
            task.setTaskCompleted(success: true)
            return
        }
        // Schedule the next BGTask for any still-future alarms, then stop overdue ones.
        rescheduleBGTask()
        Task { @MainActor in
            for entry in overdue {
                print("🛡️ BGTask: stopping overdue \(entry.alarmID.uuidString.prefix(8))")
                try? await AlarmKitService.shared.stop(id: entry.alarmID)
                disarm(alarmID: entry.alarmID)
            }
            task.setTaskCompleted(success: true)
        }
    }

    /// 最早的 stopAt 即為 BGTask 的 earliestBeginDate；重新提交會取代上一個
    /// 若已無 armed alarms → 主動取消排隊中的 BGTask，避免空跑
    private func rescheduleBGTask() {
        let future = armedAlarms.values.filter { $0.stopAt > Date() }
        guard !future.isEmpty else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.bgTaskIdentifier)
            print("🛡️ AlarmAutoStop.BGTask cancelled — no armed alarms remaining")
            return
        }
        let earliest = future.map { $0.stopAt }.min()!
        let request = BGProcessingTaskRequest(identifier: Self.bgTaskIdentifier)
        request.earliestBeginDate = earliest
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
            print("🛡️ AlarmAutoStop.BGTask submitted: earliestBeginDate=\(earliest.formatted(.dateTime.hour().minute().second()))")
        } catch BGTaskScheduler.Error.unavailable {
            // Simulator / extension context — not a real error
            print("🛡️ AlarmAutoStop.BGTask unavailable (simulator?)")
        } catch {
            print("🛡️ AlarmAutoStop.BGTask submit error: \(error)")
        }
    }

    // MARK: - Layer 2: DispatchSourceTimer

    private func installDispatchTimer(_ entry: ArmedEntry) {
        // Don't double-install
        if let existing = dispatchTimers[entry.alarmID], !existing.isCancelled { return }
        let delay = max(0, entry.stopAt.timeIntervalSinceNow)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay, repeating: .never)
        let alarmID = entry.alarmID
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            print("🛡️ AlarmAutoStop.DispatchTimer fired for \(alarmID.uuidString.prefix(8))")
            Task { @MainActor in
                try? await AlarmKitService.shared.stop(id: alarmID)
                self.disarm(alarmID: alarmID)
            }
        }
        dispatchTimers[entry.alarmID] = timer
        timer.resume()
        print("🛡️ AlarmAutoStop.DispatchTimer installed: fires in \(Int(delay))s for \(entry.alarmID.uuidString.prefix(8))")
    }

    // MARK: - Silent audio keep-alive

    private func startSilentAudio() {
        guard silentPlayer == nil else { return }

        // Use the bundled alarm CAF at volume 0 — any audio file works; we only need the
        // audio session active so the OS keeps the app alive under the `audio` background mode.
        guard let url = Bundle.main.url(forResource: "sunny_wake", withExtension: "caf") else {
            print("🛡️ AlarmAutoStop.startSilentAudio: sunny_wake.caf not found — Layer 2 inactive")
            return
        }

        do {
            // .mixWithOthers: don't duck / interfere with AlarmKit's system alarm sound.
            // .playback category: required for background audio execution.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.0          // truly inaudible — we only need the session active
            player.numberOfLoops = -1    // loop until disarmed
            player.prepareToPlay()
            player.play()
            silentPlayer = player
            print("🛡️ AlarmAutoStop.startSilentAudio: 0-vol keep-alive audio started")
        } catch {
            print("🛡️ AlarmAutoStop.startSilentAudio: failed — \(error)")
        }
    }

    private func stopSilentAudio() {
        guard let player = silentPlayer else { return }
        player.stop()
        silentPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        print("🛡️ AlarmAutoStop.stopSilentAudio: keep-alive audio stopped")
    }

    // MARK: - Next-occurrence helper (used by AlarmKitService.syncAlarm)

    /// 計算鬧鐘下一次觸發時間（供 arm() 使用）
    static func nextFireDate(hour: Int, minute: Int, weekdays: [Int]) -> Date? {
        let cal = Calendar.current
        let now = Date()

        if weekdays.isEmpty {
            // 單次：下一個符合 hour:minute 的時刻
            var comps = DateComponents()
            comps.hour = hour; comps.minute = minute; comps.second = 0
            return cal.nextDate(after: now, matching: comps, matchingPolicy: .nextTime)
        }

        // 重複：往後找最多 8 天，取第一個符合 weekday + time 的時刻
        for dayOffset in 0..<8 {
            guard let candidate = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let wd = cal.component(.weekday, from: candidate)
            guard weekdays.contains(wd) else { continue }
            var comps = DateComponents()
            comps.year   = cal.component(.year,  from: candidate)
            comps.month  = cal.component(.month, from: candidate)
            comps.day    = cal.component(.day,   from: candidate)
            comps.hour   = hour
            comps.minute = minute
            comps.second = 0
            guard let fireDate = cal.date(from: comps), fireDate > now else { continue }
            return fireDate
        }
        return nil
    }
}

