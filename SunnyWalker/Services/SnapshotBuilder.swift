// SunnyWalker — SnapshotBuilder.swift  |  統一學習快照（kids.snapshot.v1）
//
// 把 SwiftData 的 WakeRecord 聚合成家族統一的 KidsLearningSnapshot：
//   • progress   ：近 30 天成功起床天數、連續天數、平均回應秒數
//   • weaknesses ：fallback（需要大人幫忙關）比率、回應特別慢的鬧鐘（依 alarmLabel 分組）
//   • favorites  ：各鬧鐘觸發次數排行
//   • avoidances ：留空（起床 app 沒有「少碰」語意）
//
// 渲染／檔名交給共用件 KidsSnapshotMarkdown（正本：common_lib_ios/KidsDataCore，
// 規格：common_lib_ios/docs/KIDS_SNAPSHOT_v1.md）。本檔只做「自家格式 → 快照」映射，
// 純函式、可餵假資料單元測試（now / calendar / isZh 皆可注入）。
//
// 隱私（Made for Kids）：對外身分只帶匿名 profileId（kid-xxxxxx）。快照裡的
// `alarmLabel` 是**家長自訂**的鬧鐘名稱（家長自己打的字，可能含小孩名字）——
// 這是家長閘之後、家長主動匯出自己輸入的內容，不屬於 app 洩漏兒童資料；
// app 端自己的欄位一律不得放真名／生日／email。

import Foundation
import KidsDataCore
import AppLocalization

enum SnapshotBuilder {

    // MARK: - 聚合參數（統一放這裡，測試與 tuning 都看得到）

    /// 統計視窗：近 30 天（含 now 當天）。
    static let windowDays = 30
    /// 回應超過這個秒數算「特別慢」。
    static let slowResponseSeconds = 120
    /// 一顆鬧鐘至少要有這麼多筆有回應紀錄，才夠格進「回應特別慢」判斷（避免單筆離群值）。
    static let slowResponseMinSamples = 3
    /// favorites 排行最多列出幾顆鬧鐘。
    static let favoritesLimit = 5

    // MARK: - 對外入口

    /// 從 WakeRecord 聚合出統一快照。預設參數取自執行環境；測試時全部可注入。
    static func build(records: [WakeRecord],
                      now: Date = .now,
                      calendar: Calendar = .current,
                      appVersion: String = Bundle.main
                          .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                      profileId: String = AnonymousProfileID.resolve(),
                      timezone: String = TimeZone.current.identifier,
                      isZh: Bool = Lang.store.isZh) -> KidsLearningSnapshot {
        let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1),
                                        to: calendar.startOfDay(for: now)) ?? now
        let window = records.filter { $0.wokeAt >= windowStart && $0.wokeAt <= now }

        return KidsLearningSnapshot(
            app: .sunnywalker,
            appVersion: appVersion,
            profileId: profileId,
            generatedAt: now,
            timezone: timezone,
            progress: progressItems(window, now: now, calendar: calendar, isZh: isZh),
            favorites: favoriteSignals(window, isZh: isZh),
            weaknesses: weaknessItems(window, isZh: isZh),
            avoidances: [])
    }

    /// 家長頁匯出用：render 成 .md 文字＋建議檔名（不含副檔名，fileExporter 會照 contentType 補 .md）。
    /// 語言跟著 app 目前的語言設定（AppLocalization.Lang）。
    static func renderExport(records: [WakeRecord], now: Date = .now) -> (markdown: String, fileName: String) {
        let isZh = Lang.store.isZh
        let snapshot = build(records: records, now: now, isZh: isZh)
        let markdown = KidsSnapshotMarkdown.render(snapshot,
                                                   strings: isZh ? .zhHant : .en,
                                                   appDisplayName: "SunnyWalker")
        var fileName = KidsSnapshotMarkdown.suggestedFileName(for: snapshot)
        if fileName.hasSuffix(".md") { fileName.removeLast(3) }
        return (markdown, fileName)
    }

    // MARK: - progress（學到哪了：起床習慣）

    static func progressItems(_ records: [WakeRecord],
                              now: Date, calendar: Calendar, isZh: Bool) -> [ProgressItem] {
        var items: [ProgressItem] = []

        // 成功起床＝小朋友有回應（voice / button / fallback），同 WakeHistoryMarkdown 的口徑。
        let responded = records.filter { WakeHistoryMarkdown.isResponded($0.dismissMethod) }
        let successDays = Set(responded.map { calendar.startOfDay(for: $0.wokeAt) })

        items.append(ProgressItem(
            domain: "habit",
            title: isZh ? "成功起床天數（近 30 天）" : "Successful wake days (last 30 days)",
            metric: "success_days",
            value: Double(successDays.count),
            display: isZh ? "\(successDays.count) 天" : "\(successDays.count) days"))

        // 連續天數：從今天（今天還沒成功就從昨天）往回數連續的成功日。
        let streak = streakDays(successDays: successDays, now: now, calendar: calendar)
        items.append(ProgressItem(
            domain: "streak",
            title: isZh ? "連續起床天數" : "Wake-up streak",
            metric: "streak_days",
            value: Double(streak),
            display: isZh ? "連續 \(streak) 天" : "\(streak) day(s) in a row"))

        // 平均回應秒數只看有回應的紀錄（timeout 的 responseSeconds ≈ 響鈴時長，會拉高平均）。
        if !responded.isEmpty {
            let avg = responded.map(\.responseSeconds).reduce(0, +) / responded.count
            items.append(ProgressItem(
                domain: "habit",
                title: isZh ? "平均回應時間" : "Average response time",
                metric: "avg_response_seconds",
                value: Double(avg),
                display: isZh ? "\(avg) 秒" : "\(avg)s"))
        }
        return items
    }

    /// 從今天往回數連續成功日；今天還沒成功不斷鏈（改從昨天起算）。
    static func streakDays(successDays: Set<Date>, now: Date, calendar: Calendar) -> Int {
        var day = calendar.startOfDay(for: now)
        if !successDays.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while successDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    // MARK: - favorites（愛玩什麼：各鬧鐘觸發次數排行）

    static func favoriteSignals(_ records: [WakeRecord], isZh: Bool) -> [FavoriteSignal] {
        guard !records.isEmpty else { return [] }
        var counts: [String: Int] = [:]
        for record in records { counts[record.alarmLabel, default: 0] += 1 }
        let total = records.count
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(favoritesLimit)
            .map { label, count in
                FavoriteSignal(
                    title: label.isEmpty ? (isZh ? "（未命名鬧鐘）" : "(Unnamed alarm)") : label,
                    count: count,
                    share: Double(count) / Double(total))
            }
    }

    // MARK: - weaknesses（常錯什麼）

    static func weaknessItems(_ records: [WakeRecord], isZh: Bool) -> [WeaknessItem] {
        var items: [WeaknessItem] = []

        // 1) fallback 比率：需要大人幫忙關的次數 / 全部次數。
        let fallbackCount = records.filter { $0.dismissMethod == "fallback" }.count
        if fallbackCount > 0 {
            let total = records.count
            let ratio = Double(fallbackCount) / Double(total)
            items.append(WeaknessItem(
                skill: "fallback_dismiss",
                title: isZh ? "需要大人幫忙關" : "Needed a grown-up to dismiss",
                mistakeCount: fallbackCount,
                opportunities: total,
                successRate: 1 - ratio,
                hint: isZh ? "多練習用語音或按鈕自己關鬧鐘"
                           : "Practice dismissing with voice or the button"))
        }

        // 2) 回應特別慢的鬧鐘：依 alarmLabel 分組，只看有回應的紀錄，
        //    平均回應 ≥ slowResponseSeconds 且樣本數夠才列入。
        let responded = records.filter { WakeHistoryMarkdown.isResponded($0.dismissMethod) }
        var groups: [String: [WakeRecord]] = [:]
        for record in responded { groups[record.alarmLabel, default: []].append(record) }

        let slowGroups = groups
            .compactMap { label, groupRecords -> SlowAlarmGroup? in
                guard groupRecords.count >= slowResponseMinSamples else { return nil }
                let average = groupRecords.map(\.responseSeconds).reduce(0, +) / groupRecords.count
                guard average >= slowResponseSeconds else { return nil }
                let slowCount = groupRecords.filter { $0.responseSeconds >= slowResponseSeconds }.count
                return SlowAlarmGroup(label: label, averageSeconds: average,
                                      slowCount: slowCount, totalCount: groupRecords.count)
            }
            .sorted {
                $0.averageSeconds == $1.averageSeconds
                    ? $0.label < $1.label
                    : $0.averageSeconds > $1.averageSeconds
            }

        for group in slowGroups {
            let label = group.label.isEmpty ? (isZh ? "（未命名鬧鐘）" : "(Unnamed alarm)") : group.label
            items.append(WeaknessItem(
                skill: "slow_response",
                title: isZh ? "起床特別慢：\(label)" : "Slow to wake: \(label)",
                mistakeCount: group.slowCount,
                opportunities: group.totalCount,
                successRate: 1 - Double(group.slowCount) / Double(group.totalCount),
                hint: isZh ? "這顆鬧鐘平均要 \(group.averageSeconds) 秒才起床，可以試著把手機放遠一點"
                           : "Averages \(group.averageSeconds)s to respond — try placing the phone farther away"))
        }
        return items
    }

    /// 「回應特別慢」分組的中間結果（避免 4 欄 tuple 觸發 SwiftLint large_tuple）。
    private struct SlowAlarmGroup {
        let label: String
        let averageSeconds: Int
        let slowCount: Int
        let totalCount: Int
    }
}
