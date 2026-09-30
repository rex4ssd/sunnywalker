// SunnyWalkerTests — DuplicateAndChimeEndTests.swift
// 2026-09-24 Rex 回饋：(1) 區間報時的迄要跟著起走 (2) 長按鬧鐘卡「複製並修改」。

import XCTest
@testable import SunnyWalker

final class ChimeEndFollowsStartTests: XCTestCase {
    func testEndKeepsSpanWhenStartMoves() {
        // 起 00:10 → 07:00，原本迄 00:40（長度 30）→ 迄 07:30。
        XCTAssertEqual(AlarmEditorView.followedChimeEnd(oldStart: 10, newStart: 420, end: 40, fallbackSpan: 25), 450)
        // 起往前移也一樣：19:26 → 19:20，迄 19:32（長度 6）→ 19:26。
        XCTAssertEqual(AlarmEditorView.followedChimeEnd(oldStart: 1166, newStart: 1160, end: 1172, fallbackSpan: 30), 1166)
    }

    func testEndBeforeStartUsesFallbackSpan() {
        // 迄 00:40、起從 07:00 再轉到 07:05 → 原本就不在起之後 → 起 + 上次長度 25。
        XCTAssertEqual(AlarmEditorView.followedChimeEnd(oldStart: 420, newStart: 425, end: 40, fallbackSpan: 25), 450)
    }

    func testEndClampsBeforeMidnight() {
        XCTAssertEqual(AlarmEditorView.followedChimeEnd(oldStart: 600, newStart: 1420, end: 630, fallbackSpan: 30), 1439)
    }
}

final class DuplicateAlarmTemplateTests: XCTestCase {
    private func countdownChime() -> Alarm {
        let a = Alarm(label: "妹妹英文課", hour: 19, minute: 20, taskType: .button)
        a.weekdays = [2]
        a.soundFileName = "chime_cd006_zh_f_1790000000.caf"
        a.chimeSlotSoundFiles = ["chime_cd006_zh_f_1790000000.caf", "chime_cd004_zh_f_1790000000.caf"]
        a.chimeEndHour = 19; a.chimeEndMinute = 26
        a.chimeIntervalMinutes = 2
        a.chimeCountdown = true
        a.chimeCount = 2
        a.groupIndex = 1
        return a
    }

    func testCopyCarriesChimeSettings() {
        let d = NewAlarmDefaults(copying: countdownChime())
        XCTAssertEqual(d.label, "妹妹英文課")
        XCTAssertFalse(d.labelFollowsTime)
        XCTAssertEqual(d.weekdays, [2])
        XCTAssertEqual(d.groupIndex, 1)
        XCTAssertTrue(d.chimeIntervalOn)
        XCTAssertEqual(d.chimeSpanMinutes, 6)
        XCTAssertEqual(d.chimeIntervalMinutes, 2)
        XCTAssertTrue(d.chimeCountdown)
        XCTAssertEqual(d.chimeCount, 2)
    }

    /// 報時合成檔每顆各自一份：複製品不能指向範本的檔（刪掉任一顆會讓另一顆無聲）。
    func testCopyNeverSharesChimeSoundFile() {
        let d = NewAlarmDefaults(copying: countdownChime()).validated(fileExists: { _ in true },
                                                                       recordingExists: { _ in true })
        XCTAssertEqual(d.soundFileName, "sunny_wake.caf")
    }

    func testLabelThatIsItsOwnTimeFollowsTime() {
        let a = Alarm(label: "07:05", hour: 7, minute: 5, taskType: .button)
        XCTAssertTrue(NewAlarmDefaults(copying: a).labelFollowsTime)
    }
}

/// 2026-09-30：切段長度改成每顆鬧鐘選 4／8／12／14 秒（圓鈕）。
final class BurstSpanChipTests: XCTestCase {
    func testOffsetsMatchSchedulerRules() {
        // 一段 3 秒 + 間隔 2 秒 → 每 5 秒一聲。
        XCTAssertEqual(AlarmScheduler.burstOffsets(voiceSeconds: 3, gap: 2, span: 4), [])        // 只響一次
        XCTAssertEqual(AlarmScheduler.burstOffsets(voiceSeconds: 3, gap: 2, span: 12), [5, 10])
        XCTAssertEqual(AlarmScheduler.burstOffsets(voiceSeconds: 3, gap: 2, span: 14), [5, 10])
        // 很短的聲音：間距最少 2 秒。
        XCTAssertEqual(AlarmScheduler.burstOffsets(voiceSeconds: 0.5, gap: 0, span: 8), [2, 4, 6, 8])
        XCTAssertEqual(AlarmScheduler.burstOffsets(voiceSeconds: 1.2, gap: 1, span: 8), [3, 6])
    }

    func testNearestChipPrefersLongerOnTie() {
        XCTAssertEqual(Alarm.nearestBurstSpan(to: 10), 12)   // 舊預設 10 秒 → 12
        XCTAssertEqual(Alarm.nearestBurstSpan(to: 6), 8)
        XCTAssertEqual(Alarm.nearestBurstSpan(to: 7), 8)
        XCTAssertEqual(Alarm.nearestBurstSpan(to: 30), 14)
        XCTAssertEqual(Alarm.nearestBurstSpan(to: 1), 4)
    }

    func testOnlyChipValuesCountAsChosen() {
        let a = Alarm(label: "起床囉", hour: 7, minute: 0, taskType: .button)
        XCTAssertNil(a.chosenBurstSpanSeconds)              // 舊資料 → 用全域值
        a.burstSpanSeconds = 10
        XCTAssertNil(a.chosenBurstSpanSeconds)              // 不在圓鈕上的值不算
        a.burstSpanSeconds = 8
        XCTAssertEqual(a.chosenBurstSpanSeconds, 8)
    }

    /// 舊版存的「新增鬧鐘預設」沒有 burstSpanSeconds：一定要解得開，否則家長記住的預設全部消失。
    func testLegacyNewAlarmDefaultsStillDecode() throws {
        var legacy = NewAlarmDefaults()
        legacy.label = "上學囉"
        legacy.segmentedBurst = true
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        json.removeValue(forKey: "burstSpanSeconds")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(NewAlarmDefaults.self, from: data)
        XCTAssertEqual(decoded.label, "上學囉")
        XCTAssertTrue(decoded.segmentedBurst)
        XCTAssertNil(decoded.burstSpanSeconds)
    }

    func testDefaultsDropInvalidSpan() {
        var d = NewAlarmDefaults()
        d.burstSpanSeconds = 30
        XCTAssertNil(d.validated(fileExists: { _ in true }, recordingExists: { _ in true }).burstSpanSeconds)
        d.burstSpanSeconds = 12
        XCTAssertEqual(d.validated(fileExists: { _ in true }, recordingExists: { _ in true }).burstSpanSeconds, 12)
    }
}
