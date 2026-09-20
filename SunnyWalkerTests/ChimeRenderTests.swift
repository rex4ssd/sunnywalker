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
    private func render(hour: Int, minute: Int, locale: String, remaining: Int?) async throws -> Double {
        let url = await Task.detached {
            ChimeSoundComposer.composePreview(hour: hour, minute: minute, locale: Locale(identifier: locale),
                                              voice: .female, remainingMinutes: remaining)
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
}
