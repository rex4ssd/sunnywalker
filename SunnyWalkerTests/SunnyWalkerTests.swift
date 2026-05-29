// SunnyWalker — SunnyWalkerTests.swift  |  Day 1  |  smoke + Alarm model tests

import XCTest
@testable import SunnyWalker

final class SunnyWalkerSmokeTests: XCTestCase {
    func testTrueIsTrue() {
        XCTAssertTrue(true, "bootstrap smoke test")
    }
}

final class AlarmModelTests: XCTestCase {

    func testTimeStringZeroPadded() {
        let alarm = Alarm(label: "Test", hour: 7, minute: 5)
        XCTAssertEqual(alarm.timeString, "07:05")
    }

    func testTimeStringFullHour() {
        let alarm = Alarm(label: "Test", hour: 13, minute: 0)
        XCTAssertEqual(alarm.timeString, "13:00")
    }

    func testDefaultWeekdaysIsMonToFri() {
        let alarm = Alarm(label: "Test", hour: 7, minute: 30)
        XCTAssertEqual(alarm.weekdays, [2, 3, 4, 5, 6])
    }

    func testDefaultIsEnabled() {
        let alarm = Alarm(label: "Test", hour: 7, minute: 30)
        XCTAssertTrue(alarm.isEnabled)
    }

    func testWeekdaySymbolsMonToFri() {
        let alarm = Alarm(label: "Test", hour: 7, minute: 30)
        XCTAssertEqual(alarm.weekdaySymbols, ["一", "二", "三", "四", "五"])
    }
}
