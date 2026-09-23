// SunnyWalker — NewAlarmDefaultsTests.swift  |  新增鬧鐘記住上次設定

import XCTest
@testable import SunnyWalker

final class NewAlarmDefaultsTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "NewAlarmDefaultsTests")
        defaults.removePersistentDomain(forName: "NewAlarmDefaultsTests")
    }

    /// 沒存過 → 跟以前一模一樣的出廠預設（起床囉、平日、內建音）。
    func testFreshInstallUsesFactoryDefaults() {
        let d = NewAlarmDefaults.load(from: defaults)
        XCTAssertEqual(d.label, "起床囉")
        XCTAssertFalse(d.labelFollowsTime)
        XCTAssertEqual(d.weekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(d.soundFileName, "sunny_wake.caf")
    }

    /// 存了再讀，欄位一個不少。
    func testRoundTrip() {
        var d = NewAlarmDefaults()
        d.labelFollowsTime = true
        d.weekdays = [1, 7]
        d.soundFileName = "sunny_wake.caf"
        d.notificationMode = true
        d.segmentedBurst = true
        d.chimeVoice = .male
        d.todoIcon = .star
        d.store(to: defaults)
        XCTAssertEqual(NewAlarmDefaults.load(from: defaults), d)
    }

    /// 上次選的錄音已被刪 → 退回沒有錄音、口令關閉也跟著關；自訂音檔不在 → 退回內建預設音。
    func testValidationFallsBackWhenFilesAreGone() {
        var d = NewAlarmDefaults()
        d.recordingName = "gone"
        d.voiceDismiss = true
        d.soundFileName = "alarm_deleted.caf"
        let v = d.validated(fileExists: { _ in false }, recordingExists: { _ in false })
        XCTAssertEqual(v.recordingName, "")
        XCTAssertFalse(v.voiceDismiss)
        XCTAssertEqual(v.soundFileName, "sunny_wake.caf")
    }

    /// 報時合成檔是每顆各自產的，不能當下一顆的預設；壞掉的星期／群組夾回合法值。
    func testValidationClampsAndDropsChimeFile() {
        var d = NewAlarmDefaults()
        d.soundFileName = "chime_abc.caf"
        d.weekdays = [0, 9, 3, 3]
        d.groupIndex = 42
        d.chimeIntervalMinutes = 7
        let v = d.validated(fileExists: { _ in true }, recordingExists: { _ in true })
        XCTAssertEqual(v.soundFileName, "sunny_wake.caf")
        XCTAssertEqual(v.weekdays, [3])
        XCTAssertEqual(v.groupIndex, 4)
        XCTAssertEqual(v.chimeIntervalMinutes, 5)
    }
}
