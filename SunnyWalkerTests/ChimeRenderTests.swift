// SunnyWalker — ChimeRenderTests.swift  |  報時語音實際合成出來的長度
//
// iOS 對「過長」的自訂通知音會悄悄退成預設音（真機只驗到 ~4.6s 安全，見 AlarmSoundExporter）。
// 報時／倒數的句子是程式組出來的，最長的那幾句要實際合成量過，不能只看字數。

import XCTest
import AVFAudio
@testable import SunnyWalker

final class ChimeRenderTests: XCTestCase {

    private func seconds(_ url: URL) throws -> Double {
        let f = try AVAudioFile(forReading: url)
        return Double(f.length) / f.fileFormat.sampleRate
    }

    /// ⚠️ composePreview 內部用 semaphore 等合成 callback，不能在 main thread 呼叫 → 丟到背景執行緒。
    private func render(hour: Int, minute: Int, locale: String, remaining: Int?,
                        purpose: String? = nil) async throws -> Double {
        let url = await Task.detached {
            ChimeSoundComposer.composePreview(hour: hour, minute: minute, locale: Locale(identifier: locale),
                                              voice: .female, remainingMinutes: remaining, purpose: purpose,
                                              tag: "test_\(locale)_\(remaining ?? -1)_\(purpose ?? "")")
        }.value
        guard let url else {
            throw XCTSkip("這台模擬器沒有可用的語音合成")
        }
        return try seconds(url)
    }

    func testLongestPhrasesStayUnderSafeNotificationLength() async throws {
        let cases: [(String, Int, Int, String, Int?)] = [
            ("zh 時刻最長", 23, 57, "zh-Hant", nil),          // 晚上十一點五十七分
            ("en 時刻最長", 23, 57, "en", nil),               // It's eleven fifty-seven at night.
            ("zh 倒數", 7, 0, "zh-Hant", 30),
            ("en 倒數", 7, 0, "en", 30),
            ("zh 倒數最長", 7, 0, "zh-Hant", 357),            // 剩五小時五十七分鐘
            ("en 倒數最長", 7, 0, "en", 357),                 // Five hours fifty-seven minutes left.
        ]
        for (name, h, m, loc, left) in cases {
            let s = try await render(hour: h, minute: m, locale: loc, remaining: left)
            print("⏱ \(name): \(String(format: "%.2f", s))s")
            XCTAssertGreaterThan(s, 0.5, name)
            XCTAssertLessThan(s, AlarmSoundExporter.bundledSafeSeconds + 0.1, "\(name) 太長，通知音會被 iOS 換成預設音")
        }
    }

    /// 倒數後面接「要念的事」：用上限內最長的字（中文 3 字、英文 10 字母）配最長的倒數，實際合成量秒數。
    func testLongestCountdownWithPurposeStaysUnderSafeLength() async throws {
        let zh = "要上學了"                 // 超過上限 → 截成「要上學」（9 bytes）
        let en = "piano time"               // 10 bytes（上限）
        XCTAssertEqual(Alarm.sanitizedCountdownPurpose(zh), "要上學")
        XCTAssertEqual(Alarm.sanitizedCountdownPurpose(en), en)
        let cases: [(String, String, Int, String)] = [
            ("zh 倒數＋事 一般", "zh-Hant", 30, zh),     // 剩三十分鐘要上學
            ("en 倒數＋事 一般", "en", 30, en),          // Thirty minutes until piano time.
            ("zh 倒數＋事 最長", "zh-Hant", 357, zh),    // 剩五小時五十七分鐘要上學
            ("en 倒數＋事 最長", "en", 357, en),         // Five hours fifty-seven minutes until piano time.
        ]
        for (name, loc, left, what) in cases {
            let s = try await render(hour: 7, minute: 0, locale: loc, remaining: left, purpose: what)
            print("⏱ \(name): \(String(format: "%.2f", s))s")
            XCTAssertGreaterThan(s, 0.5, name)
            XCTAssertLessThan(s, AlarmSoundExporter.bundledSafeSeconds + 0.1, "\(name) 太長，通知音會被 iOS 換成預設音")
        }
    }
}
