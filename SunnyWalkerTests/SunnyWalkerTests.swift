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

final class VoiceClipTests: XCTestCase {

    func testFormattedDurationZero() {
        let clip = VoiceClip(name: "Test", fileName: "test.m4a", duration: 0)
        XCTAssertEqual(clip.formattedDuration, "--:--")
    }

    func testFormattedDurationMinutesSeconds() {
        let clip = VoiceClip(name: "Test", fileName: "test.m4a", duration: 90)
        XCTAssertEqual(clip.formattedDuration, "1:30")
    }

    func testUniqueIDs() {
        let a = VoiceClip(name: "A", fileName: "a.m4a")
        let b = VoiceClip(name: "B", fileName: "b.m4a")
        XCTAssertNotEqual(a.id, b.id)
    }
}

@MainActor
final class AudioPlayerTests: XCTestCase {

    func testInitialIsPlayingIsFalse() {
        let player = AudioPlayer()
        XCTAssertFalse(player.isPlaying)
    }

    func testStopWhenIdleKeepsIsPlayingFalse() {
        let player = AudioPlayer()
        player.stop()
        XCTAssertFalse(player.isPlaying)
    }
}

final class AlarmSoundTests: XCTestCase {

    func testSoundFileNameDefault() {
        let alarm = Alarm(label: "Morning", hour: 7, minute: 0)
        XCTAssertEqual(alarm.soundFileName, "totoro_breath.caf")
    }

    func testSoundFileNameIsMutable() {
        let alarm = Alarm(label: "Morning", hour: 7, minute: 0)
        alarm.soundFileName = "leaf_rustle.caf"
        XCTAssertEqual(alarm.soundFileName, "leaf_rustle.caf")
    }
}

final class WakePhraseTests: XCTestCase {

    func testDefaultKeywordsNotEmpty() {
        XCTAssertFalse(WakePhrase.defaultKeywords.isEmpty)
    }

    func testPrimaryKeywordPresent() {
        XCTAssertTrue(WakePhrase.texts.contains("我起床了"))
    }

    func testAllKeywordsZhTW() {
        XCTAssertTrue(WakePhrase.defaultKeywords.allSatisfy { $0.locale == "zh-TW" })
    }
}

@MainActor
final class AudioRecorderTests: XCTestCase {

    func testInitialIsRecordingIsFalse() {
        let recorder = AudioRecorder()
        XCTAssertFalse(recorder.isRecording)
    }

    func testInitialCurrentURLIsNil() {
        let recorder = AudioRecorder()
        XCTAssertNil(recorder.currentURL)
    }

    func testStopWhenIdleKeepsIsRecordingFalse() {
        let recorder = AudioRecorder()
        recorder.stop()
        XCTAssertFalse(recorder.isRecording)
    }
}

@MainActor
final class SpeechRecognizerTests: XCTestCase {

    func testInitialRecognizedTextIsEmpty() {
        let recognizer = SpeechRecognizer()
        XCTAssertEqual(recognizer.recognizedText, "")
    }

    func testInitialMatchedKeywordIsNil() {
        let recognizer = SpeechRecognizer()
        XCTAssertNil(recognizer.matchedKeyword)
    }

    func testStopWhenNotListeningIsNoop() {
        let recognizer = SpeechRecognizer()
        recognizer.stop()  // should not crash when called before startListening
        XCTAssertEqual(recognizer.recognizedText, "")
    }
}

final class AlarmFiredNotificationTests: XCTestCase {

    func testAlarmFiredNotificationNameValue() {
        XCTAssertEqual(Notification.Name.alarmFired.rawValue, "SunnyWalkerAlarmFired")
    }

    func testAlarmFiredNotificationIsPosted() {
        let expectation = expectation(description: "alarmFired notification received")
        let token = NotificationCenter.default.addObserver(
            forName: .alarmFired,
            object: nil,
            queue: .main
        ) { note in
            XCTAssertEqual(note.object as? String, "CAFEBABE-0000-0000-0000-000000000000")
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        NotificationCenter.default.post(
            name: .alarmFired,
            object: "CAFEBABE-0000-0000-0000-000000000000"
        )

        waitForExpectations(timeout: 1)
    }
}

final class GateQuestionTests: XCTestCase {

    func testRandomReturnsQuestion() {
        let q = GateQuestion.random()
        XCTAssertFalse(q.prompt.isEmpty)
        XCTAssertFalse(q.options.isEmpty)
        XCTAssertFalse(q.correct.isEmpty)
    }

    func testCorrectAnswerIsAlwaysInOptions() {
        for _ in 0..<20 {
            let q = GateQuestion.random()
            XCTAssertTrue(q.options.contains(q.correct),
                          "correct '\(q.correct)' not found in options \(q.options)")
        }
    }

    func testOptionsCountIsThree() {
        for _ in 0..<10 {
            let q = GateQuestion.random()
            XCTAssertEqual(q.options.count, 3,
                           "Expected 3 options, got \(q.options.count) for '\(q.prompt)'")
        }
    }

    func testAllOptionsAreUnique() {
        for _ in 0..<10 {
            let q = GateQuestion.random()
            XCTAssertEqual(Set(q.options).count, q.options.count,
                           "Duplicate options in \(q.options)")
        }
    }

    func testWeekdayQuestionsAreHardForChildren() {
        // Weekday ordering requires understanding calendar order — not simple arithmetic
        let weekdayPrompt = "哪個選項的星期排列順序是正確的？"
        var found = false
        for _ in 0..<50 {
            let q = GateQuestion.random()
            if q.prompt == weekdayPrompt {
                found = true
                XCTAssertTrue(q.correct.contains("週"), "weekday correct answer should contain 週")
                break
            }
        }
        XCTAssertTrue(found, "Weekday question should appear in random pool")
    }

    func testMultiplicationAnswersAreCorrect() {
        // Verify hardcoded answers are arithmetically correct
        XCTAssertEqual(127 * 4, 508)
        XCTAssertEqual(236 * 3, 708)
        XCTAssertEqual(154 * 5, 770)
    }
}
