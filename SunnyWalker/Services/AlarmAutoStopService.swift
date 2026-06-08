// SunnyWalker — AlarmAutoStopService.swift
// 鬧鐘自動停止服務 (State Machine Push-down pattern)
//
// 架構：兩層保障 + 中斷復活 + watchdog
//   Layer 1 — BGProcessingTask: iOS 在 stopAt 附近喚醒 app（best-effort，不可靠，
//             鎖屏未充電時可能不觸發 — 只當最後保險）。
//   Layer 2 — AVAudioPlayer(靜音) + DispatchSourceTimer:
//             ★ 只在「響鈴視窗」運作：進背景時最近的 fire 時刻 ≤ lookAheadMinutes
//             才啟動靜音音訊 keep-alive；DispatchSourceTimer 在 stopAt 精準 stop()；
//             stop 完（dispatchTimers 清空）立即 teardown → app 自然 suspend。
//             設計原則（Rex 2026-06-08）：這是給小朋友的「提醒型」鬧鐘 —
//             響鈴只有 1~10 分鐘，響完 app 也要自動停止背景運作（不整夜保活耗電）；
//             無人回應時 app 要能獨立完成「自動停鈴 + 記錄 timeout」供統計
//             （準時率 / 回應率，見 WakeRecord dismissMethod="timeout"）。
//   Layer 2.5 — ★ Audio interruption 復活（本次新增，核心修復）：
//             AlarmKit 鬧鐘由 SpringBoard 播放，一響就會 INTERRUPT app 的 audio
//             session（即使 .mixWithOthers）→ 靜音 player 停 → app 失去 keep-alive
//             → 馬上被 suspend → stopAt 的 timer 永遠不會跑。
//             這正是 issue_alarm.md log「響鈴時刻後 log 完全停止」的失效點。
//             解法：interruption .began 時立刻拿 UIApplication background task
//             (~30s 額度)，額度內每秒重試 setActive(true)+play()；mixable session
//             在系統鬧鐘響的同時通常允許重新啟動 → app 恢復 keep-alive → timer 照常跑。
//   Watchdog — 響鈴視窗 keep-alive 期間每 5 秒輪詢：
//             (a) stopAt 過期 → stop()（one-shot timer 被凍結漏掉時的備援）
//             (b) 靜音 player 死了 → 重新踢活
//             (c) alarmState == alerting → 用「實際響鈴時刻 + ringSeconds」夾住 stopAt
//                 （預測 fireDate 錯誤時的保險）
//
// 已知殘餘風險（接受的取捨，iOS 平台限制）：
//   - 進背景時鬧鐘距離 > lookAheadMinutes（例如整夜睡覺）→ 不保活（省電優先），
//     app suspended 期間第一段響鈴只能靠 Layer 1 BGTask（best-effort）+ 系統自身
//     的自動靜音（Clock app 是 ~15 分鐘，AlarmKit 未文件化）。timeout 統計記錄
//     不會漏：下次開 app 時 checkAndStopOverdue 會補停 + 補記錄。
//   - 本地通知無法在背景執行程式碼（方向 B 不可行）；AlarmKit 沒有公開
//     ring-duration API（方向 C 不可行，iOS 26.x）。
//
// 整合點：
//   - AlarmKitService.syncAlarm()  → arm()
//   - AlarmKitService.stop(id:)    → disarm()
//   - HomeView.enterBackgroundAlarmMode() → beginTransitionProtection() + beginBackgroundLifecycle()
//   - HomeView.scenePhase → .active      → endBackgroundLifecycle() + checkAndStopOverdue()
//   - SunnyWalkerApp.AppDelegate.didFinishLaunching → BGTask handler registration

import AVFoundation
import BackgroundTasks
import Foundation
import UIKit

@MainActor
final class AlarmAutoStopService {

    static let shared = AlarmAutoStopService()
    private init() {}

    // MARK: - Constants

    static let bgTaskIdentifier = "com.sunnywalker.alarm.autostop"

    /// 響鈴視窗的前置量（分鐘）：進背景時最近的 fire 時刻在此範圍內 → 啟動 keep-alive。
    /// （≈ ring duration 上限：鬧鐘最長響 10 分鐘，與 AppSettings 1...10 一致）
    private let lookAheadMinutes: Double = 10

    /// 響鈴視窗 keep-alive 期間的 watchdog 輪詢間隔
    private let watchdogInterval: TimeInterval = 5

    /// interruption 復活的最大重試次數（每秒一次；UIApplication bg task 額度約 30s）
    private let maxRecoveryAttempts = 25

    // MARK: - Persisted armed state

    private struct ArmedEntry: Codable {
        let alarmID: UUID
        var stopAt: Date          // fireDate + ringSeconds（watchdog 偵測到 alerting 時可能下修）
        var ringSeconds: Int?     // optional：舊版持久化資料沒有此欄位，decode 相容
        var alertingSeenAt: Date? // watchdog 第一次看到 alerting 的時刻（只夾一次）
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

    // MARK: - In-process state (Layer 2)

    private var dispatchTimers: [UUID: DispatchSourceTimer] = [:]
    private var silentPlayer: AVAudioPlayer?
    private var watchdog: DispatchSourceTimer?
    private var interruptionObserver: NSObjectProtocol?
    private var recoveryBGTask: UIBackgroundTaskIdentifier = .invalid
    private var transitionBGTask: UIBackgroundTaskIdentifier = .invalid

    private struct PlayFailed: Error {}

    // MARK: - Timeout records（無人回應的統計來源）

    /// 自動停鈴 = 小朋友在響鈴視窗內沒有回應。先排進 UserDefaults queue
    /// （背景 service 不碰 SwiftData），HomeView 回前景時 drain 成
    /// WakeRecord(dismissMethod: "timeout") 供準時率/回應率統計。
    struct PendingTimeoutRecord: Codable {
        let alarmID: UUID
        let firedAt: Date     // alertingSeenAt（實際偵測到響鈴）優先，否則 stopAt - ringSeconds
        let stoppedAt: Date
    }

    private let pendingRecordsKey = "AlarmAutoStop.pendingTimeoutRecords"

    private func queueTimeoutRecord(for entry: ArmedEntry, stoppedAt: Date = Date()) {
        let firedAt = entry.alertingSeenAt
            ?? entry.stopAt.addingTimeInterval(-Double(entry.ringSeconds ?? 0))
        var pending = loadPendingRecords()
        // dedupe：同一鬧鐘同一次響鈴只記一筆（DispatchTimer 與 watchdog 可能同時觸發）
        guard !pending.contains(where: {
            $0.alarmID == entry.alarmID && abs($0.firedAt.timeIntervalSince(firedAt)) < 60
        }) else { return }
        pending.append(PendingTimeoutRecord(alarmID: entry.alarmID, firedAt: firedAt, stoppedAt: stoppedAt))
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: pendingRecordsKey)
        }
        print("🛡️ AlarmAutoStop.queueTimeoutRecord: \(entry.alarmID.uuidString.prefix(8)) firedAt=\(fmt(firedAt)) — \(pending.count) pending")
    }

    /// HomeView 回前景時呼叫：取出並清空所有待轉檔的 timeout 記錄
    func drainPendingTimeoutRecords() -> [PendingTimeoutRecord] {
        let pending = loadPendingRecords()
        guard !pending.isEmpty else { return [] }
        UserDefaults.standard.removeObject(forKey: pendingRecordsKey)
        return pending
    }

    private func loadPendingRecords() -> [PendingTimeoutRecord] {
        guard let data = UserDefaults.standard.data(forKey: pendingRecordsKey),
              let decoded = try? JSONDecoder().decode([PendingTimeoutRecord].self, from: data)
        else { return [] }
        return decoded
    }

    // MARK: - Public API

    /// 排好一個鬧鐘 → 記錄 stopAt，提交 BGTask
    func arm(alarmID: UUID, fireDate: Date, ringSeconds: Int) {
        let stopAt = fireDate.addingTimeInterval(Double(ringSeconds))
        var current = armedAlarms
        current[alarmID] = ArmedEntry(alarmID: alarmID, stopAt: stopAt,
                                      ringSeconds: ringSeconds, alertingSeenAt: nil)
        armedAlarms = current
        print("🛡️ AlarmAutoStop.arm: \(alarmID.uuidString.prefix(8)) stopAt=\(fmt(stopAt))")
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
        if dispatchTimers.isEmpty {
            stopWatchdog()
            stopSilentAudio()
            endRecoveryBGTask()
        }
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
                queueTimeoutRecord(for: entry, stoppedAt: entry.stopAt)   // 補記錄：響鈴視窗早已結束
                try? await AlarmKitService.shared.stop(id: entry.alarmID)   // stop() 內部會 disarm
            }
        }
    }

    /// 進背景後（syncAllEnabled 完成後）呼叫
    /// ★ 2026-06-08 第四輪（最終）：keep-alive 只在「響鈴視窗」運作 —
    /// 最近的 fire 時刻 ≤ lookAheadMinutes 才啟動；否則不保活（提醒型 app，省電優先），
    /// 整夜情境靠 BGTask 機會性升級 + 下次開 app 的 checkAndStopOverdue 補停/補記錄。
    /// 響鈴視窗結束（最後一個 timer stop → disarm → dispatchTimers 清空）會自動
    /// teardown audio/watchdog → app 自然 suspend（「超過十分鐘也自動停止 app 運作」）。
    func beginBackgroundLifecycle() {
        registerInterruptionObserver()
        let now = Date()
        let upcoming = armedAlarms.values.filter { $0.stopAt > now }
        guard !upcoming.isEmpty else {
            print("🛡️ AlarmAutoStop.beginBackgroundLifecycle: no armed alarms — BGTask only")
            return
        }

        // 視窗判定看 fire 時刻（stopAt - ringSeconds），不是 stopAt：
        // 要在「開始響」之前就活著，才能接住 interruption / 精準 stop。
        let nearestFire = upcoming
            .map { $0.stopAt.addingTimeInterval(-Double($0.ringSeconds ?? 0)) }
            .min()!
        let secondsUntilFire = nearestFire.timeIntervalSince(now)
        guard secondsUntilFire <= lookAheadMinutes * 60 else {
            print("🛡️ AlarmAutoStop.beginBackgroundLifecycle: nearest fire in \(Int(secondsUntilFire/60)) min — outside \(Int(lookAheadMinutes))-min ring window, BGTask only (no keep-alive, app will suspend)")
            return
        }

        print("🛡️ AlarmAutoStop.beginBackgroundLifecycle: nearest fire in \(Int(secondsUntilFire))s — starting audio keep-alive + DispatchTimers + watchdog for the ring window")
        startSilentAudio()
        for entry in upcoming { installDispatchTimer(entry) }
        startWatchdog()
    }

    /// scenePhase → .active 時呼叫：前景不需要 keep-alive，全部收掉。
    /// 注意：不 disarm — armedAlarms / BGTask 留著當 Layer 1 保險；
    /// enterForegroundAlarmMode 的 stop() 鏈會逐一 disarm。
    func endBackgroundLifecycle() {
        guard !dispatchTimers.isEmpty || silentPlayer != nil || watchdog != nil else { return }
        print("🛡️ AlarmAutoStop.endBackgroundLifecycle: tearing down timers/audio/watchdog")
        for (_, timer) in dispatchTimers { timer.cancel() }
        dispatchTimers.removeAll()
        stopWatchdog()
        stopSilentAudio()
        endRecoveryBGTask()
    }

    // MARK: - Background-transition protection

    /// 背景轉場保護：syncAllEnabled 要走多次 AlarmKit IPC + 啟動 keep-alive 音訊。
    /// 沒有 UIApplication background task 保護時，app 可能在完成前就被 suspend
    /// → AlarmKit 沒排上 / 靜音音訊沒啟動。HomeView.enterBackgroundAlarmMode 在
    /// spawn Task 前呼叫 begin，Task 尾端呼叫 end。
    func beginTransitionProtection() {
        guard transitionBGTask == .invalid else { return }
        transitionBGTask = UIApplication.shared.beginBackgroundTask(withName: "SunnyWalker.alarmReArm") {
            Task { @MainActor in AlarmAutoStopService.shared.endTransitionProtection() }
        }
        print("🛡️ AlarmAutoStop.beginTransitionProtection: bg task \(transitionBGTask.rawValue)")
    }

    func endTransitionProtection() {
        guard transitionBGTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(transitionBGTask)
        transitionBGTask = .invalid
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
        // Schedule the next BGTask for any still-future alarms first.
        rescheduleBGTask()
        Task { @MainActor in
            for entry in overdue {
                print("🛡️ BGTask: stopping overdue \(entry.alarmID.uuidString.prefix(8))")
                self.queueTimeoutRecord(for: entry, stoppedAt: entry.stopAt)
                try? await AlarmKitService.shared.stop(id: entry.alarmID)   // stop() 內部會 disarm
            }
            // 機會性升級：BGTask 給了我們執行權 — 如果還有 stopAt 在 lookAhead 內的鬧鐘
            // （例如鬧鐘正在響、stopAt 還沒到），趁活著的時候把 Layer 2 拉起來，
            // 讓 DispatchTimer 能在精準時刻 stop。這是整夜 suspended 情境的唯一逃生門。
            self.beginBackgroundLifecycle()
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
            print("🛡️ AlarmAutoStop.BGTask submitted: earliestBeginDate=\(fmt(earliest))")
        } catch BGTaskScheduler.Error.unavailable {
            // Simulator / extension context — not a real error
            print("🛡️ AlarmAutoStop.BGTask unavailable (simulator?)")
        } catch {
            print("🛡️ AlarmAutoStop.BGTask submit error: \(error)")
        }
    }

    // MARK: - Layer 2: DispatchSourceTimer

    private func installDispatchTimer(_ entry: ArmedEntry, replace: Bool = false) {
        if let existing = dispatchTimers[entry.alarmID], !existing.isCancelled {
            guard replace else { return }
            existing.cancel()
            dispatchTimers.removeValue(forKey: entry.alarmID)
        }
        let delay = max(0, entry.stopAt.timeIntervalSinceNow)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay, repeating: .never, leeway: .milliseconds(100))
        let alarmID = entry.alarmID
        timer.setEventHandler {
            print("🛡️ AlarmAutoStop.DispatchTimer fired for \(alarmID.uuidString.prefix(8))")
            Task { @MainActor in
                let service = AlarmAutoStopService.shared
                if let entry = service.armedAlarms[alarmID] {
                    service.queueTimeoutRecord(for: entry)   // 無人回應 → timeout 統計
                }
                try? await AlarmKitService.shared.stop(id: alarmID)   // stop() 內部會 disarm
            }
        }
        dispatchTimers[entry.alarmID] = timer
        timer.resume()
        print("🛡️ AlarmAutoStop.DispatchTimer \(replace ? "REinstalled" : "installed"): fires in \(Int(delay))s for \(entry.alarmID.uuidString.prefix(8))")
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + watchdogInterval, repeating: watchdogInterval)
        timer.setEventHandler {
            Task { @MainActor in AlarmAutoStopService.shared.watchdogTick() }
        }
        timer.resume()
        watchdog = timer
        print("🛡️ AlarmAutoStop.watchdog started (every \(Int(watchdogInterval))s)")
    }

    private func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    private func watchdogTick() {
        let now = Date()
        // (c) alerting 偵測 → 夾 stopAt（每個 alarm 只夾一次）
        clampStopAtForAlertingAlarms(now: now)

        // (a) overdue 備援：one-shot timer 被凍結漏掉時由這裡收尾
        let overdue = armedAlarms.values.filter { $0.stopAt <= now }
        if !overdue.isEmpty {
            print("🛡️ watchdog: \(overdue.count) overdue — stopping")
            Task { @MainActor in
                for entry in overdue {
                    self.queueTimeoutRecord(for: entry)
                    try? await AlarmKitService.shared.stop(id: entry.alarmID)
                }
            }
        }

        // (b) 靜音 player 死了（被中斷後沒復活成功）→ 再踢一次
        if let player = silentPlayer, !player.isPlaying {
            print("🛡️ watchdog: silent player not playing — re-kicking")
            recoverPlayback(attempt: 1)
        }
    }

    /// alarmState == alerting 的鬧鐘：stopAt = min(原值, 實際響鈴偵測時刻 + ringSeconds)。
    /// 修正「預測 fireDate 與 AlarmKit 實際觸發時刻不一致」時 stopAt 飄到幾天後的情況。
    private func clampStopAtForAlertingAlarms(now: Date) {
        var entries = armedAlarms
        var dirty = false
        for (id, var entry) in entries {
            guard entry.alertingSeenAt == nil,
                  AlarmKitService.shared.alarmState(id: id).contains("alerting")
            else { continue }
            entry.alertingSeenAt = now
            if let ring = entry.ringSeconds {
                let clamped = min(entry.stopAt, now.addingTimeInterval(Double(ring)))
                if clamped < entry.stopAt {
                    print("🛡️ AlarmAutoStop: \(id.uuidString.prefix(8)) alerting NOW — stopAt clamped \(fmt(entry.stopAt)) → \(fmt(clamped))")
                    entry.stopAt = clamped
                    installDispatchTimer(entry, replace: true)
                } else {
                    print("🛡️ AlarmAutoStop: \(id.uuidString.prefix(8)) alerting NOW — stopAt \(fmt(entry.stopAt)) unchanged")
                }
            }
            entries[id] = entry
            dirty = true
        }
        if dirty { armedAlarms = entries }
    }

    // MARK: - Layer 2.5: Audio-interruption recovery（核心修復）

    /// AlarmKit 響鈴 = SpringBoard 播音 = 我們的 audio session 被 INTERRUPT。
    /// 沒有這段的話：靜音 player 停 → app 失去 audio keep-alive → 立刻 suspend
    /// → stopAt 的 DispatchTimer 永遠不會跑（issue log 的「響鈴後 log 全停」）。
    private func registerInterruptionObserver() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let info = note.userInfo,
                  let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in
                AlarmAutoStopService.shared.handleInterruption(type)
            }
        }
        print("🛡️ AlarmAutoStop: interruption observer registered")
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType) {
        guard silentPlayer != nil else { return }   // Layer 2 沒在跑 → 不關我們的事
        switch type {
        case .began:
            // 大概率就是 AlarmKit 鬧鐘剛開始響。此刻 app 還活著（收得到這個 callback），
            // 抓住機會：(1) 拿 bg task 額度撐住不被 suspend；(2) 立刻夾 stopAt；
            // (3) 每秒重試把 mixable 靜音 player 救回來。
            print("🛡️ AlarmAutoStop.interruption BEGAN (likely AlarmKit ring) — fighting suspension")
            beginRecoveryBGTask()
            clampStopAtForAlertingAlarms(now: Date())
            recoverPlayback(attempt: 1)
        case .ended:
            print("🛡️ AlarmAutoStop.interruption ENDED — resuming keep-alive")
            recoverPlayback(attempt: 1)
        @unknown default:
            break
        }
    }

    /// 重試重啟靜音 player：setActive(true) + play()，每秒一次，最多 maxRecoveryAttempts 次。
    /// .mixWithOthers session 在系統鬧鐘播音期間通常允許重新啟動。
    private func recoverPlayback(attempt: Int) {
        guard let player = silentPlayer else { endRecoveryBGTask(); return }
        if player.isPlaying {
            print("🛡️ AlarmAutoStop.recoverPlayback: already playing (attempt \(attempt))")
            endRecoveryBGTask()
            return
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            guard player.play() else { throw PlayFailed() }
            print("🛡️ AlarmAutoStop.recoverPlayback: RECOVERED on attempt \(attempt) — keep-alive restored")
            endRecoveryBGTask()   // 音訊已恢復，由 audio background mode 接手保活
            return
        } catch {
            print("🛡️ AlarmAutoStop.recoverPlayback: attempt \(attempt) failed — \(error)")
        }
        guard attempt < maxRecoveryAttempts else {
            print("🛡️ AlarmAutoStop.recoverPlayback: GAVE UP after \(attempt) attempts — app will suspend; Layer 1 BGTask / 前景 fallback 接手")
            endRecoveryBGTask()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Task { @MainActor in
                AlarmAutoStopService.shared.recoverPlayback(attempt: attempt + 1)
            }
        }
    }

    private func beginRecoveryBGTask() {
        guard recoveryBGTask == .invalid else { return }
        recoveryBGTask = UIApplication.shared.beginBackgroundTask(withName: "AlarmAutoStop.recovery") {
            Task { @MainActor in AlarmAutoStopService.shared.endRecoveryBGTask() }
        }
        print("🛡️ AlarmAutoStop.beginRecoveryBGTask: \(recoveryBGTask.rawValue)")
    }

    private func endRecoveryBGTask() {
        guard recoveryBGTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(recoveryBGTask)
        recoveryBGTask = .invalid
    }

    // MARK: - Silent audio keep-alive

    private func startSilentAudio(attempt: Int = 1) {
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
            guard player.play() else { throw PlayFailed() }
            silentPlayer = player
            print("🛡️ AlarmAutoStop.startSilentAudio: 0-vol keep-alive audio started (attempt \(attempt))")
        } catch {
            // HomeView 的 scenePhase 背景分支剛 setActive(false)（解 UN 鈴聲 ducking 雷）→
            // 這裡啟動可能撞 56055xxxx session 競態（同 AudioPlayer 的 560557684 lore）。
            // 比照修法：短延遲重試。
            print("🛡️ AlarmAutoStop.startSilentAudio: attempt \(attempt) failed — \(error)")
            guard attempt < 3 else {
                print("🛡️ AlarmAutoStop.startSilentAudio: GAVE UP — Layer 2 inactive, BGTask only")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Task { @MainActor in
                    AlarmAutoStopService.shared.startSilentAudio(attempt: attempt + 1)
                }
            }
        }
    }

    private func stopSilentAudio() {
        guard let player = silentPlayer else { return }
        player.stop()
        silentPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        print("🛡️ AlarmAutoStop.stopSilentAudio: keep-alive audio stopped")
    }

    // MARK: - Helpers

    private func fmt(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
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
