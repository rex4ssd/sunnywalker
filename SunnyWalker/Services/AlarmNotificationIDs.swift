// SunnyWalker — AlarmNotificationIDs.swift  |  UNNotification identifier 的唯一正本
//
// 一顆鬧鐘會在 UNUserNotificationCenter 留下好幾種 request：
//   • baseline   `{uuid}`（單次）／`{uuid}-{weekday}`（每週重複）
//   • nag        `{uuid}-nag-{k}`      嚴格模式的分鐘級連發（功能已停用，id 仍要清）
//   • rep        `{uuid}-rep-{k}`      溫和提醒「切段響滿 N 秒」的秒級堆疊
//   • chime      `{uuid}-chime-{k}`    報時「連報 N 次」（單一時刻的舊格式，slot 0）
//   • slot       `{uuid}-slot-{s}` / `{uuid}-slot-{s}-{weekday}`      區間報時第 s 個時刻
//   • slot chime `{uuid}-slot-{s}-chime-{k}`                          區間報時第 s 個時刻連報第 k 次
//
// 以前這些字串在 AlarmScheduler.schedule / cancel / cancelNags 與 AlarmListView.deleteAlarm
// 各拼一份，而且 deleteAlarm 只清 baseline——刪掉鬧鐘後 -rep-/-chime- 的一次性通知會留在系統裡
// 照響（鬧鐘已經不在清單上卻還在響）。所有 id 一律從這裡拿，清理一律用 `all(for:)`。

import Foundation

enum AlarmNotificationIDs {

    static let maxNags = 9
    /// 清理 `-rep-k` 用的列舉上限（scheduleGentleRepeatBurst 最多排這麼多顆）。
    static let maxRepeatSlots = 12

    // MARK: - Builders

    static func base(_ id: UUID) -> String { id.uuidString }

    static func weekday(_ id: UUID, _ weekday: Int) -> String { "\(id.uuidString)-\(weekday)" }

    static func nag(_ id: UUID, _ k: Int) -> String { "\(id.uuidString)-nag-\(k)" }

    static func repeatSlot(_ id: UUID, _ k: Int) -> String { "\(id.uuidString)-rep-\(k)" }

    /// 單一時刻報時的第 k 次（k ≥ 2；第 1 次是 baseline）。
    static func chimeRepeat(_ id: UUID, _ k: Int) -> String { "\(id.uuidString)-chime-\(k)" }

    /// 區間報時第 `slot` 個時刻（slot 從 0 起）。`weekday` nil ＝ 每天重複的單一 request。
    static func chimeSlot(_ id: UUID, slot: Int, weekday: Int? = nil) -> String {
        if let weekday { return "\(id.uuidString)-slot-\(slot)-\(weekday)" }
        return "\(id.uuidString)-slot-\(slot)"
    }

    /// 區間報時第 `slot` 個時刻的連報第 k 次（k ≥ 2）。
    static func chimeSlotRepeat(_ id: UUID, slot: Int, _ k: Int) -> String {
        "\(id.uuidString)-slot-\(slot)-chime-\(k)"
    }

    // MARK: - Groups

    /// baseline 那幾顆（單次 + 七個星期）。
    static func baselines(for id: UUID) -> [String] {
        [base(id)] + (1...7).map { weekday(id, $0) }
    }

    /// 響鈴之後的「後續」通知：nag / 切段堆疊 / 報時連報（含區間 slot 的連報）。
    /// 孩子已回應（開了 app、點了橫幅）時要清掉的就是這一組——baseline 留著給下週用。
    static func followUps(for id: UUID) -> [String] {
        (1...maxNags).map { nag(id, $0) }
            + (1...maxRepeatSlots).map { repeatSlot(id, $0) }
            + (2...Alarm.maxChimeCount).map { chimeRepeat(id, $0) }
            + (0..<Alarm.maxChimeSlots).flatMap { s in
                (2...Alarm.maxChimeCount).map { chimeSlotRepeat(id, slot: s, $0) }
            }
    }

    /// 區間報時的所有 slot request（每天 + 每個星期）。
    static func chimeSlots(for id: UUID) -> [String] {
        (0..<Alarm.maxChimeSlots).flatMap { s in
            [chimeSlot(id, slot: s)] + (1...7).map { chimeSlot(id, slot: s, weekday: $0) }
        }
    }

    /// 這顆鬧鐘可能留在系統裡的【每一個】identifier。刪除／停用／換模式時一律用這個清。
    static func all(for id: UUID) -> [String] {
        baselines(for: id) + followUps(for: id) + chimeSlots(for: id)
    }
}
