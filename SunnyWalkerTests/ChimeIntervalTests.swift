// SunnyWalker — ChimeIntervalTests.swift  |  區間報時 / 通知 id / 家族鬧鐘請求 / 首頁「下一個」

import XCTest
@testable import SunnyWalker

// MARK: - 區間報時的時刻展開

final class ChimeSlotTimesTests: XCTestCase {

    private func slots(_ sh: Int, _ sm: Int, _ eh: Int?, _ em: Int?, _ interval: Int?) -> [String] {
        Alarm.chimeSlotTimes(startHour: sh, startMinute: sm, endHour: eh, endMinute: em, intervalMinutes: interval)
            .map { String(format: "%02d:%02d", $0.hour, $0.minute) }
    }

    /// Rex 的原始需求：7:00–7:30 每 5 分 → 7:00, 7:05 … 7:25（迄本身不報）。
    func testSevenToSevenThirtyEveryFive() {
        XCTAssertEqual(slots(7, 0, 7, 30, 5), ["07:00", "07:05", "07:10", "07:15", "07:20", "07:25"])
    }

    func testNoEndMeansSingleSlot() {
        XCTAssertEqual(slots(7, 0, nil, nil, 5), ["07:00"])
        XCTAssertEqual(slots(7, 0, 7, 30, nil), ["07:00"])
        XCTAssertEqual(slots(7, 0, 7, 30, 0), ["07:00"])
    }

    func testEndBeforeOrEqualStartMeansSingleSlot() {
        XCTAssertEqual(slots(7, 30, 7, 0, 5), ["07:30"])
        XCTAssertEqual(slots(7, 30, 7, 30, 5), ["07:30"])
    }

    func testIntervalNotDividingRangeStopsBeforeEnd() {
        XCTAssertEqual(slots(7, 0, 7, 12, 5), ["07:00", "07:05", "07:10"])
    }

    func testCappedAtMaxSlots() {
        let s = slots(6, 0, 8, 0, 1)   // 120 個候選 → 夾到上限
        XCTAssertEqual(s.count, Alarm.maxChimeSlots)
        XCTAssertEqual(s.first, "06:00")
    }

    func testAlarmModelExposesIntervalFlags() {
        let a = Alarm(label: "上學", hour: 7, minute: 0)
        XCTAssertFalse(a.isIntervalChime)
        a.chimeEndHour = 7; a.chimeEndMinute = 30; a.chimeIntervalMinutes = 10
        XCTAssertTrue(a.isIntervalChime)
        XCTAssertEqual(a.chimeSlotTimes.count, 3)
        XCTAssertEqual(a.formattedChimeRange(use24h: true), "07:00–07:30")
        // slot 檔清單長度不符 → nil（要重合成）
        a.chimeSlotSoundFiles = ["a.caf"]
        XCTAssertNil(a.alignedChimeSlotFiles)
        a.chimeSlotSoundFiles = ["a.caf", "b.caf", "c.caf"]
        XCTAssertEqual(a.alignedChimeSlotFiles?.count, 3)
    }

    func testChimeVoiceDefaultsToFemale() {
        let a = Alarm(label: "x", hour: 7, minute: 0)
        XCTAssertEqual(a.effectiveChimeVoice, .female)
        a.chimeVoice = "male"
        XCTAssertEqual(a.effectiveChimeVoice, .male)
        a.chimeVoice = "robot"
        XCTAssertEqual(a.effectiveChimeVoice, .female)
    }

    func testKindClassification() {
        let a = Alarm(label: "x", hour: 7, minute: 0)
        XCTAssertEqual(a.kind, .alarm)
        a.soundFileName = "chime_0700_zh_f_1.caf"
        XCTAssertEqual(a.kind, .chime)
        a.todoIcon = TodoIcon.star.rawValue
        XCTAssertEqual(a.kind, .todo)   // 待辦優先於報時
    }
}

// MARK: - 通知 identifier

final class AlarmNotificationIDsTests: XCTestCase {

    func testAllCoversEveryFamily() {
        let id = UUID()
        let all = Set(AlarmNotificationIDs.all(for: id))
        XCTAssertTrue(all.contains(id.uuidString))
        XCTAssertTrue(all.contains("\(id.uuidString)-3"))
        XCTAssertTrue(all.contains("\(id.uuidString)-nag-1"))
        XCTAssertTrue(all.contains("\(id.uuidString)-rep-12"))
        XCTAssertTrue(all.contains("\(id.uuidString)-chime-2"))
        XCTAssertTrue(all.contains("\(id.uuidString)-slot-0"))
        XCTAssertTrue(all.contains("\(id.uuidString)-slot-11-7"))
        XCTAssertTrue(all.contains("\(id.uuidString)-slot-5-chime-5"))
        // 全部都屬於這顆鬧鐘
        XCTAssertTrue(all.allSatisfy { $0.hasPrefix(id.uuidString) })
    }

    func testFollowUpsExcludeBaselinesAndSlots() {
        let id = UUID()
        let follow = Set(AlarmNotificationIDs.followUps(for: id))
        XCTAssertFalse(follow.contains(id.uuidString))
        XCTAssertFalse(follow.contains("\(id.uuidString)-2"))
        XCTAssertFalse(follow.contains("\(id.uuidString)-slot-0"))
        XCTAssertTrue(follow.contains("\(id.uuidString)-rep-1"))
        XCTAssertTrue(follow.contains("\(id.uuidString)-slot-0-chime-2"))
    }

    func testIDsAreUnique() {
        let id = UUID()
        let all = AlarmNotificationIDs.all(for: id)
        XCTAssertEqual(all.count, Set(all).count)
    }
}

// MARK: - 家族 app 傳來的鬧鐘請求

final class FamilyAlarmRequestTests: XCTestCase {

    func testParseFullURL() throws {
        let url = try XCTUnwrap(URL(string: "rexsunny://alarm?time=07:30&label=%E4%B8%8A%E5%AD%B8%E5%9B%89&days=2,3,4,5,6&kind=chime&from=LetAbacus"))
        let r = try XCTUnwrap(FamilyAlarmRequest.parse(url))
        XCTAssertEqual(r.hour, 7)
        XCTAssertEqual(r.minute, 30)
        XCTAssertEqual(r.label, "上學囉")
        XCTAssertEqual(r.weekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(r.kind, .chime)
        XCTAssertEqual(r.sourceApp, "LetAbacus")
    }

    func testDefaultsWhenOptionalFieldsMissing() throws {
        let r = try XCTUnwrap(FamilyAlarmRequest.parse(URL(string: "rexsunny://alarm?time=6:05")!))
        XCTAssertEqual(r.hour, 6)
        XCTAssertEqual(r.minute, 5)
        XCTAssertEqual(r.weekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(r.kind, .alarm)
        XCTAssertNil(r.sourceApp)
        XCTAssertEqual(r.label, "")
    }

    func testRejectsBadInput() {
        XCTAssertNil(FamilyAlarmRequest.parse(URL(string: "rexsunny://alarm?time=25:00")!))
        XCTAssertNil(FamilyAlarmRequest.parse(URL(string: "rexsunny://alarm?label=x")!))
        XCTAssertNil(FamilyAlarmRequest.parse(URL(string: "rexsunny://other?time=07:00")!))
        XCTAssertNil(FamilyAlarmRequest.parse(URL(string: "https://example.com/alarm?time=07:00")!))
    }

    func testRoundTripThroughURL() throws {
        let r = FamilyAlarmRequest(hour: 21, minute: 0, label: "刷牙", weekdays: [1, 7], kind: .todo, sourceApp: "RestBud")
        let url = try XCTUnwrap(r.makeURL())
        XCTAssertEqual(FamilyAlarmRequest.parse(url), r)
    }

    func testMakeAlarmForChimeIsNotificationModeChime() {
        let r = FamilyAlarmRequest(hour: 7, minute: 0, label: "", weekdays: [], kind: .chime, sourceApp: nil)
        let a = r.makeAlarm()
        XCTAssertTrue(a.isChimeAlarm)
        XCTAssertEqual(a.effectiveBackgroundMode, .notification)
        XCTAssertEqual(a.weekdays, [2, 3, 4, 5, 6])   // 空 → 平日
        XCTAssertEqual(a.label, "起床囉")
    }
}

// MARK: - 首頁「下一個」

@MainActor
final class NextUpcomingAlarmTests: XCTestCase {

    private func date(weekday: Int, hour: Int, minute: Int) -> Date {
        // 找一個符合 weekday 的日期（從今天往後找）
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var d = cal.startOfDay(for: Date())
        while cal.component(.weekday, from: d) != weekday { d = cal.date(byAdding: .day, value: 1, to: d)! }
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d)!
    }

    func testPicksEarliestRemainingToday() {
        let a = Alarm(label: "a", hour: 7, minute: 0); a.weekdays = [1, 2, 3, 4, 5, 6, 7]
        let b = Alarm(label: "b", hour: 12, minute: 0); b.weekdays = [1, 2, 3, 4, 5, 6, 7]
        let c = Alarm(label: "c", hour: 18, minute: 0); c.weekdays = [1, 2, 3, 4, 5, 6, 7]
        let now = date(weekday: 3, hour: 8, minute: 0)
        XCTAssertEqual(AlarmListView.nextUpcomingAlarmID(in: [a, b, c], now: now), b.id)
    }

    func testSkipsDisabledTodoAndOtherDays() {
        let disabled = Alarm(label: "off", hour: 9, minute: 0); disabled.weekdays = [3]; disabled.isEnabled = false
        let todo = Alarm(label: "todo", hour: 9, minute: 30); todo.weekdays = [3]; todo.todoIcon = "star"
        let otherDay = Alarm(label: "thu", hour: 10, minute: 0); otherDay.weekdays = [5]
        let good = Alarm(label: "ok", hour: 11, minute: 0); good.weekdays = [3]
        let now = date(weekday: 3, hour: 8, minute: 0)
        XCTAssertEqual(AlarmListView.nextUpcomingAlarmID(in: [disabled, todo, otherDay, good], now: now), good.id)
    }

    func testNilWhenNothingLeftToday() {
        let a = Alarm(label: "a", hour: 7, minute: 0); a.weekdays = [3]
        let now = date(weekday: 3, hour: 20, minute: 0)
        XCTAssertNil(AlarmListView.nextUpcomingAlarmID(in: [a], now: now))
    }
}
