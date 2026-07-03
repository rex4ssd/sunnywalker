// SunnyWalker — AlarmRingLog.swift  |  響鈴診斷 log（實測 iPad「有時只響2聲」用）
//
// 為什麼需要這個：
//   「持續 ~30s」提醒模式其實不是「一個長音檔」，而是「baseline 通知 + rep-k 短音通知」
//   秒級錯開堆疊而成（見 AlarmScheduler.scheduleGentleRepeatBurst）。app 被關掉／殺掉時
//   完全沒有 app code 在跑，無法「即時」記錄到底響了幾聲、響多久。
//
//   唯一能【事後重建】的訊號＝下次開 app 時掃「已送達通知」(getDeliveredNotifications)：
//   同一顆鬧鐘的每一則 delivered 通知都帶實際送達時間 (.date) 且共用 threadIdentifier(=alarmID)。
//     • delivered 則數  ≈ 實際「響幾聲」
//     • 頭尾送達時間差   ＝ 實際「響多久」
//   「只響 2 聲就停」＝ iOS 只送達 2 則（把後面的 rep 丟了）；「響滿 30s」＝ 全部送達。
//
//   這個 model 把每次開 app 掃到的結果存起來，顯示在「起床紀錄」——家長不用接電腦看 Xcode
//   console 也能在 iPad 上直接讀到「7/3 08:00 響 2 次 / 4 秒、09:00 響 7 次 / 30 秒」。

import SwiftData
import Foundation

@Model
final class AlarmRingLog {
    @Attribute(.unique) var id: UUID
    var alarmID: UUID
    /// 鬧鐘 label 快照（之後被編輯／刪除也不影響這筆診斷）。
    var alarmLabel: String
    /// 第一則通知的實際送達時間 ≈ 鬧鐘真正開始響的時刻。
    var firedAt: Date
    /// 這次實際「送達」了幾則鬧鐘通知 ≈ 響幾聲。
    var soundCount: Int
    /// 頭尾兩則通知的送達時間差（秒）＝實際響多久；只有 1 則時為 0。
    var spanSeconds: Int
    /// 掃到這筆的時刻（開 app 的時間）——純供除錯參考。
    var capturedAt: Date

    init(alarmID: UUID, alarmLabel: String, firedAt: Date,
         soundCount: Int, spanSeconds: Int, capturedAt: Date = .now) {
        self.id = UUID()
        self.alarmID = alarmID
        self.alarmLabel = alarmLabel
        self.firedAt = firedAt
        self.soundCount = soundCount
        self.spanSeconds = spanSeconds
        self.capturedAt = capturedAt
    }

    /// 「響 2 次 / 4 秒」風格摘要。
    var summary: String {
        "響 \(soundCount) 次 / \(spanSeconds) 秒"
    }
}
