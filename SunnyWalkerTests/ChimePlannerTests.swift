// SunnyWalkerTests — ChimePlannerTests.swift
// 部分星期的區間報時：全域「最近優先」規劃（64 顆通知額度）。
// 回歸：iPad 實機 pending=62，第二顆倒數報時只排進第 0 個時刻 →「只響一次，後面完全沒反應」。

import XCTest
@testable import SunnyWalker

final class ChimePlannerTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return c
    }()

    /// 2026-09-21（一）22:00
    private var mondayNight: Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 22, minute: 0))!
    }

    private func slots(from h: Int, _ m: Int, every step: Int, count: Int) -> [(hour: Int, minute: Int)] {
        (0..<count).map { i in (hour: h + (m + i * step) / 60, minute: (m + i * step) % 60) }
    }

    func testOccurrencesCoverEverySlotAndWeekdayOnce() {
        let occ = AlarmScheduler.chimeOccurrences(alarmID: UUID(), slots: slots(from: 22, 27, every: 2, count: 12),
                                                  weekdays: [2, 3, 4, 5, 6], after: mondayNight, calendar: cal)
        XCTAssertEqual(occ.count, 60)
        XCTAssertTrue(occ.allSatisfy { $0.date > mondayNight })
        XCTAssertTrue(occ.allSatisfy { $0.date < mondayNight.addingTimeInterval(7 * 86_400 + 3_600) })
    }

    func testTightBudgetKeepsTonightsWholeCountdownNotJustSlotZero() {
        let a = UUID(), b = UUID()
        let cands = AlarmScheduler.chimeOccurrences(alarmID: a, slots: slots(from: 22, 27, every: 2, count: 12),
                                                    weekdays: [2, 3, 4, 5, 6], after: mondayNight, calendar: cal)
                  + AlarmScheduler.chimeOccurrences(alarmID: b, slots: slots(from: 7, 0, every: 5, count: 6),
                                                    weekdays: [2, 3, 4, 5, 6], after: mondayNight, calendar: cal)
        let plan = AlarmScheduler.planChimes(cands, budget: 20)
        XCTAssertEqual(plan.count, 20)
        // 今晚（週一）a 的 12 個時刻必須全數入選——舊版只排得進 slot 0。
        let tonight = plan.filter { $0.alarmID == a && $0.weekday == 2 }
        XCTAssertEqual(Set(tonight.map(\.slot)), Set(0..<12))
        // 接著是明早 b 的 6 個時刻。
        XCTAssertEqual(Set(plan.filter { $0.alarmID == b && $0.weekday == 3 }.map(\.slot)), Set(0..<6))
        // 依時間排序。
        XCTAssertEqual(plan.map(\.date), plan.map(\.date).sorted())
    }

    func testZeroOrNegativeBudgetPlansNothing() {
        let cands = AlarmScheduler.chimeOccurrences(alarmID: UUID(), slots: [(hour: 7, minute: 0)],
                                                    weekdays: [2], after: mondayNight, calendar: cal)
        XCTAssertTrue(AlarmScheduler.planChimes(cands, budget: 0).isEmpty)
        XCTAssertTrue(AlarmScheduler.planChimes(cands, budget: -3).isEmpty)
    }

    func testAmpleBudgetSchedulesTheWholeWeek() {
        let cands = AlarmScheduler.chimeOccurrences(alarmID: UUID(), slots: slots(from: 7, 0, every: 5, count: 6),
                                                    weekdays: [2, 3, 4, 5, 6], after: mondayNight, calendar: cal)
        XCTAssertEqual(AlarmScheduler.planChimes(cands, budget: 62).count, 30)
    }
}

/// 切段響鈴長度：6…12 秒、預設 10（2026-09-21 由 10/20/30 改短，省通知額度）。
@MainActor
final class BurstSpanSettingTests: XCTestCase {
    func testOptionsAreSixToTwelveWithDefaultTen() {
        XCTAssertEqual(AppSettings.burstSpanOptions, Array(6...12))
        XCTAssertEqual(AppSettings.defaultBurstSpanSeconds, 10)
        XCTAssertTrue(AppSettings.burstSpanOptions.contains(AppSettings.defaultBurstSpanSeconds))
    }

    func testLegacyThirtyFallsBackToTen() {
        let s = AppSettings.shared
        let saved = s.burstSpanSeconds
        defer { s.burstSpanSeconds = saved }
        s.burstSpanSeconds = 30
        XCTAssertEqual(s.effectiveBurstSpanSeconds, 10)
        s.burstSpanSeconds = 6
        XCTAssertEqual(s.effectiveBurstSpanSeconds, 6)
    }
}
