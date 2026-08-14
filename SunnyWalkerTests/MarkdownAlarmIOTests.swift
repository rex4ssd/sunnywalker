import XCTest
@testable import SunnyWalker

/// MarkdownAlarmIO——鬧鐘設定的逗號行表格（KidsLineTable 換裝後補的回歸測試）。
final class MarkdownAlarmIOTests: XCTestCase {

    func testBasicLine() {
        let parsed = MarkdownAlarmIO.parseLine("daily, 08:00, go to school")
        XCTAssertEqual(parsed?.hour, 8)
        XCTAssertEqual(parsed?.minute, 0)
        XCTAssertEqual(parsed?.label, "go to school")
        XCTAssertEqual(parsed?.weekdays, MarkdownAlarmIO.allDays)
        XCTAssertEqual(parsed?.isEnabled, true)
    }

    func testLabelMayContainCommas() {
        // KidsLineTable 換裝的重點：中段自由文字，逗號不再被吃掉
        let parsed = MarkdownAlarmIO.parseLine("weekdays, 07:30, 起床, 刷牙, 吃早餐")
        XCTAssertEqual(parsed?.label, "起床, 刷牙, 吃早餐")
        XCTAssertEqual(parsed?.weekdays, MarkdownAlarmIO.workdays)
    }

    func testOffSuffixDisables() {
        let parsed = MarkdownAlarmIO.parseLine("daily, 13:00, 午睡 (off)")
        XCTAssertEqual(parsed?.isEnabled, false)
        XCTAssertEqual(parsed?.label, "午睡")
    }

    func testCustomWeekdaysAndChineseTokens() {
        let parsed = MarkdownAlarmIO.parseLine("一三五, 06:30, gym")
        XCTAssertEqual(parsed?.weekdays, [2, 4, 6])
        let second = MarkdownAlarmIO.parseLine("每天, 09:15, 中文別名")
        XCTAssertEqual(second?.weekdays, MarkdownAlarmIO.allDays)
    }

    func testTwoFieldLineHasEmptyLabel() {
        let parsed = MarkdownAlarmIO.parseLine("weekends, 09:30")
        XCTAssertEqual(parsed?.label, "")
        XCTAssertEqual(parsed?.weekdays, MarkdownAlarmIO.weekend)
    }

    func testInvalidLinesReturnNil() {
        XCTAssertNil(MarkdownAlarmIO.parseLine("# 註解行"))
        XCTAssertNil(MarkdownAlarmIO.parseLine(""))
        XCTAssertNil(MarkdownAlarmIO.parseLine("daily"))                 // 缺時間
        XCTAssertNil(MarkdownAlarmIO.parseLine("daily, 25:00, bad"))     // 時間越界
        XCTAssertNil(MarkdownAlarmIO.parseLine("nonsense, 08:00, x"))    // repeat 解不開
    }

    func testParseWholeTextSkipsCommentsAndBlanks() {
        let text = """
        # SunnyWalker Alarms
        daily, 08:00, morning

        weekends, 09:30, 賴床 (off)
        """
        let all = MarkdownAlarmIO.parse(text)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[1].isEnabled, false)
    }
}
