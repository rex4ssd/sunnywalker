// SunnyWalker — StoreShots.swift  |  上架截圖模式（DEBUG 專用，Release 整段不編進去）
//
// 家族其他 app 用 UITests target + seed script 拍上架截圖；SunnyWalker 沒有那一套，
// 所以用啟動參數做一個輕量版（搭配 scripts/shoot_store_shots.sh）：
//
//   xcrun simctl launch <UDID> app.rexcode.sunnywalker \
//       -StoreShots 1 -appLanguageCode zh-Hant -StoreShotScreen editor -StoreShotGroup 2
//
//   • 灌示範資料（三個群組：哥哥／妹妹／報時，含區間＋倒數報時）——只在鬧鐘清單是空的時候灌。
//   • 首頁固定成早上 9:41 的晴天場景（半夜拍也不會是夜景），排列用「依時段」。
//   • 不跳任何權限對話框、不排通知／AlarmKit（拍照用的模擬器上不需要真的響）。
//   • `-StoreShotScreen home|editor|new|settings` 直接開到那個畫面，不用過家長閘、不靠點擊。
//
// 🔴 只准用在**專用的截圖模擬器**：它會改群組／排列等 UserDefaults，也會往 SwiftData 灌資料。

import Foundation
import SwiftData

enum StoreShots {
    #if DEBUG
    static let isActive = ProcessInfo.processInfo.arguments.contains("-StoreShots")
    #else
    static let isActive = false
    #endif

    /// 要直接開到哪個畫面（home＝不開任何 sheet）。
    static var screen: String {
        guard isActive else { return "home" }
        return UserDefaults.standard.string(forKey: "StoreShotScreen") ?? "home"
    }

    /// 首頁一開始停在哪個群組。
    static var initialGroup: Int {
        guard isActive else { return 0 }
        return min(max(UserDefaults.standard.integer(forKey: "StoreShotGroup"), 0), 2)
    }

    /// 截圖模式下的「現在」：今天早上 9:41（跟狀態列一致、場景是晴天）。平常是 nil。
    static var fixedNow: Date? {
        guard isActive else { return nil }
        return Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date())
    }

    #if DEBUG
    private static var isChinese: Bool { SunnyLocalization.code.hasPrefix("zh") }

    /// 要在 AppSettings.shared 第一次被碰到【之前】呼叫（它在 init 時讀 UserDefaults）。
    static func prepareDefaults() {
        guard isActive else { return }
        let d = UserDefaults.standard
        let zh = isChinese
        d.set(true, forKey: "groupEnabled")
        d.set(3, forKey: "groupCount")
        d.set(zh ? ["哥哥", "妹妹", "出門倒數"] : ["Leo", "Mia", "Out the door"], forKey: "groupNames")
        d.set(["sunny", "bunny", "giraffe", "", ""], forKey: "groupMascots")
        d.set([true, true, true, true, true], forKey: "groupActiveStates")
        d.set([false, false, true, false, false], forKey: "groupChimeStates")
        d.set([false, false, false, false, false], forKey: "groupTodoStates")
        d.set(HomeListLayout.daypart.rawValue, forKey: "homeListLayout")
        d.set(zh, forKey: "use24HourClock")
        // 家長閘視為已解鎖：設定頁／新增鬧鐘直接開，截圖不用答題。
        d.set(Date().addingTimeInterval(3600).timeIntervalSince1970, forKey: "parentalUnlockUntil")
    }

    /// 清單是空的才灌；回傳「出門倒數」那顆（給 editor 畫面用）。
    @MainActor
    @discardableResult
    static func seedIfNeeded(_ context: ModelContext, existing: [Alarm]) -> Alarm? {
        guard isActive else { return nil }
        if let hero = existing.first(where: { $0.isIntervalChime }) { return hero }
        guard existing.isEmpty else { return nil }
        let zh = isChinese
        let weekdays = [2, 3, 4, 5, 6], weekend = [1, 7], all = [1, 2, 3, 4, 5, 6, 7]

        func add(_ h: Int, _ m: Int, _ zhLabel: String, _ enLabel: String, _ days: [Int],
                 group: Int, sound: String = "sunny_wake.caf", enabled: Bool = true) -> Alarm {
            let a = Alarm(label: zh ? zhLabel : enLabel, hour: h, minute: m, taskType: .button)
            a.weekdays = days
            a.groupIndex = group
            a.soundFileName = sound
            a.isEnabled = enabled
            context.insert(a)
            return a
        }

        // 哥哥
        _ = add(6, 50, "起床囉", "Wake up", weekdays, group: 0)
        _ = add(7, 30, "上學囉", "Time for school", weekdays, group: 0, sound: "leaf_rustle.caf")
        _ = add(13, 0, "午睡起床", "Nap's over", weekend, group: 0, enabled: false)
        _ = add(16, 30, "寫作業", "Homework time", weekdays, group: 0)
        _ = add(20, 30, "刷牙準備睡覺", "Brush teeth, bedtime", all, group: 0, sound: "leaf_rustle.caf")
        // 妹妹
        _ = add(7, 0, "起床囉", "Wake up", weekdays, group: 1)
        _ = add(19, 30, "洗澡時間", "Bath time", all, group: 1, sound: "leaf_rustle.caf")
        // 報時群組：區間＋倒數是主角，另外一顆單一時刻報時
        let hero = add(7, 0, "出門倒數", "Out the door", weekdays, group: 2, sound: "\(Alarm.chimeFilePrefix)shots_0700.caf")
        hero.backgroundRingMode = .notification
        hero.chimeCount = 1
        hero.chimeEndHour = 7; hero.chimeEndMinute = 30
        hero.chimeIntervalMinutes = 10
        hero.chimeCountdown = true
        let dinner = add(18, 0, "吃晚餐囉", "Dinner time", all, group: 2, sound: "\(Alarm.chimeFilePrefix)shots_1800.caf")
        dinner.backgroundRingMode = .notification
        dinner.chimeCount = 2
        try? context.save()
        return hero
    }
    #endif
}
