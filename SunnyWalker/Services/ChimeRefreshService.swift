// SunnyWalker — ChimeRefreshService.swift
// 通知額度（iOS 每 app 64 顆 pending）不夠排滿一週時，區間報時是「一次性、最近優先」的滾動排程，
// 響完就要續排。App 在背景是被暫停的、不會自己續——這裡用 BGAppRefreshTask 請 iOS 不定時叫醒幾秒來補。
// ⚠️ 喚醒時機由 iOS 決定（常用的 app 比較常被叫），不保證；所以設定卡另有「目前保證到何時」的提示。

import BackgroundTasks
import Foundation
import SwiftData

/// 規劃器最近一次的結果，給 UI 顯示「目前保證到何時」。
@MainActor
final class ChimeCoverage: ObservableObject {
    static let shared = ChimeCoverage()
    private init() {}
    /// nil＝整週排得下（每週重複、不需要續排）；有值＝一次性滾動排程，只排到這個時間點。
    @Published var coveredUntil: Date?
}

@MainActor
enum ChimeRefreshService {
    static let taskIdentifier = "app.rexcode.sunnywalker.chime.replan"

    /// 必須在 didFinishLaunching 結束前呼叫（iOS 規定）。
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in await handle(refresh) }
        }
    }

    /// 進背景時／每次跑完都再排下一次。只有滾動排程中才需要；整週排滿就不麻煩系統。
    static func scheduleNext() {
        guard ChimeCoverage.shared.coveredUntil != nil else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(60 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { print("🔔 ChimeRefresh: submit failed — \(error.localizedDescription)") }
    }

    private static func handle(_ task: BGAppRefreshTask) async {
        let work = Task { @MainActor in await rearm() }
        task.expirationHandler = { work.cancel() }
        await work.value
        scheduleNext()
        task.setTaskCompleted(success: !work.isCancelled)
    }

    /// 背景喚醒時沒有 SwiftUI 的 modelContext → 自己開一個讀同一份 store。
    static func rearm() async {
        guard let container = try? ModelContainer(for: Alarm.self, WakeRecord.self, VoiceClip.self,
                                                  TodoPlayRecord.self, AlarmRingLog.self) else { return }
        let context = ModelContext(container)
        guard let alarms = try? context.fetch(FetchDescriptor<Alarm>()) else { return }
        let live = alarms.filter {
            $0.isEnabled && !$0.isTodo && $0.effectiveBackgroundMode == .notification
                && AppSettings.groupAllowsFiring($0.effectiveGroupIndex)
        }
        // 每週的溫和提醒：切段連響只預排 48 小時內那一次，也靠這裡補。
        for a in live where !a.isChimeAlarm && !a.weekdays.isEmpty {
            if Task.isCancelled { return }
            try? await AlarmScheduler.shared.schedule(alarm: a)
        }
        await AlarmScheduler.shared.replanWeekdayChimes(alarms: live)
        try? context.save()
        print("🔔 ChimeRefresh: background re-arm done (coveredUntil=\(String(describing: ChimeCoverage.shared.coveredUntil)))")
    }
}
