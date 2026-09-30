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
    /// 這台模擬器根本沒有語音合成 → skip；有語音卻合不出上限內的版本 → 那是真的失敗（不能被 skip 蓋掉）。
    private func requireSpeech(_ locale: String) async throws {
        let ok = await Task.detached { ChimeSoundComposer.spokenSeconds("test", locale: Locale(identifier: locale)) }.value
        if ok == nil { throw XCTSkip("這台模擬器沒有可用的語音合成") }
    }

    private func render(hour: Int, minute: Int, locale: String, remaining: Int?,
                        purpose: String? = nil, voice: ChimeVoiceGender = .female) async throws -> Double {
        try await requireSpeech(locale)
        let url = await Task.detached {
            ChimeSoundComposer.composePreview(hour: hour, minute: minute, locale: Locale(identifier: locale),
                                              voice: voice, remainingMinutes: remaining, purpose: purpose,
                                              tag: "test_\(locale)_\(remaining ?? -1)_\(purpose ?? "")_\(voice.rawValue)")
        }.value
        let file = try XCTUnwrap(url, "每一版都超過 \(ChimeSoundComposer.maxSpokenSeconds)s，合成不出來")
        return try seconds(file)
    }

    /// 實際會念哪一版（不寫檔）。
    private func spoken(_ locale: String, remaining: Int, purpose: String, voice: ChimeVoiceGender = .female)
        async throws -> ChimeSoundComposer.SpokenChime {
        try await requireSpeech(locale)
        let s = await Task.detached {
            ChimeSoundComposer.bestSpoken(hour: 7, minute: 0, locale: Locale(identifier: locale), voice: voice,
                                          remainingMinutes: remaining, purpose: purpose)
        }.value
        return try XCTUnwrap(s)
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
            // 合成後的檔一定要在上限內（太長時 render 會自己加快／拿掉「要做什麼」）。
            XCTAssertLessThanOrEqual(s, ChimeSoundComposer.maxSpokenSeconds + 0.01, "\(name) 太長，通知音會被 iOS 換成預設音")
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
            // 合成後的檔一定要在上限內（太長時 render 會自己加快／拿掉「要做什麼」）。
            XCTAssertLessThanOrEqual(s, ChimeSoundComposer.maxSpokenSeconds + 0.01, "\(name) 太長，通知音會被 iOS 換成預設音")
        }
    }

    /// 原始長度（不經長度保險）：只印出來當紀錄，方便跟實機（-ChimeLengthProbe）比較。
    func testRawSpokenLengthsForReference() async throws {
        let zh = Locale(identifier: "zh-Hant"), en = Locale(identifier: "en")
        let cases: [(String, Locale)] = [
            (ChimeSoundComposer.phrase(hour: 7, minute: 0, locale: zh, remainingMinutes: 357, purpose: "要上學"), zh),
            (ChimeSoundComposer.phrase(hour: 7, minute: 0, locale: en, remainingMinutes: 357, purpose: "piano time"), en),
        ]
        for (text, loc) in cases {
            let normal = await Task.detached { ChimeSoundComposer.spokenSeconds(text, locale: loc) }.value
            let fast = await Task.detached {
                ChimeSoundComposer.spokenSeconds(text, locale: loc, rateFactor: ChimeSoundComposer.fastRateFactor)
            }.value
            guard let normal, let fast else { throw XCTSkip("這台模擬器沒有可用的語音合成") }
            print("⏱ raw \"\(text)\": normal \(String(format: "%.2f", normal))s, fast \(String(format: "%.2f", fast))s")
            XCTAssertLessThan(fast, normal, "加快語速要真的變短")
        }
    }

    /// 男聲也要在上限內（Mac 代理實測：英文男聲念同一句 4.9s，比女聲慢很多）。
    func testMaleVoiceAlsoStaysUnderHardLimit() async throws {
        let cases: [(String, String, Int?, String?, Int, Int)] = [
            ("zh 男聲 時刻最長", "zh-Hant", nil, nil, 23, 57),
            ("en 男聲 時刻最長", "en", nil, nil, 23, 57),
            ("zh 男聲 倒數＋事 最長", "zh-Hant", 357, "要上學", 7, 0),
            ("en 男聲 倒數＋事 最長", "en", 357, "piano time", 7, 0),
        ]
        for (name, loc, left, what, h, m) in cases {
            let s = try await render(hour: h, minute: m, locale: loc, remaining: left, purpose: what, voice: .male)
            print("⏱ \(name): \(String(format: "%.2f", s))s")
            XCTAssertLessThanOrEqual(s, ChimeSoundComposer.maxSpokenSeconds + 0.01, name)
        }
    }

    /// 退階順序：先保住「要做什麼」（加快），放不下才拿掉；最後才用標準語速念最短那句。
    func testLadderKeepsPurposeBeforeDroppingIt() {
        let ladder = ChimeSoundComposer.renderLadder(full: "剩十分鐘要上學", plain: "剩十分鐘")
        XCTAssertEqual(ladder.map(\.text), ["剩十分鐘要上學", "剩十分鐘要上學", "剩十分鐘", "剩十分鐘", "剩十分鐘"])
        XCTAssertEqual(ladder.map(\.rate), [ChimeSoundComposer.normalRateFactor, ChimeSoundComposer.fastRateFactor,
                                           ChimeSoundComposer.normalRateFactor, ChimeSoundComposer.fastRateFactor,
                                           ChimeSoundComposer.lastResortRateFactor])
        // 沒有「要做什麼」時不重複念同一句。
        XCTAssertEqual(ChimeSoundComposer.renderLadder(full: "剩十分鐘", plain: "剩十分鐘").count, 3)
    }

    /// 一般長度（30 分鐘）的倒數，「要做什麼」一定要念出來、而且不用加快。
    func testNormalCountdownKeepsPurposeAtNormalSpeed() async throws {
        for (loc, what) in [("zh-Hant", "要上學"), ("en", "school")] {
            for voice in ChimeVoiceGender.allCases {
                let s = try await spoken(loc, remaining: 30, purpose: what, voice: voice)
                print("⏱ 30 分＋事 \(loc) \(voice.rawValue): \"\(s.text)\" \(String(format: "%.2f", s.seconds))s rate×\(s.rate)")
                XCTAssertEqual(s.purposeMark, .spoken, "\(loc) \(voice.rawValue)")
                XCTAssertTrue(s.text.contains(what))
                XCTAssertEqual(s.rate, ChimeSoundComposer.normalRateFactor)
            }
        }
    }

    func testPurposeMarkParsesFileNames() {
        XCTAssertEqual(ChimeSoundComposer.purposeMark(ofFile: "chime_cd030p_zh_f_1790000000.caf"), .spoken)
        XCTAssertEqual(ChimeSoundComposer.purposeMark(ofFile: "chime_cd357x_en_m_1790000000.caf"), .dropped)
        XCTAssertEqual(ChimeSoundComposer.purposeMark(ofFile: "chime_cd030_zh_f_1790000000.caf"), .none)
        XCTAssertEqual(ChimeSoundComposer.purposeMark(ofFile: "chime_0705_zh_f_1790000000.caf"), .none)
        XCTAssertEqual(ChimeSoundComposer.purposeMark(ofFile: "sunny_wake.caf"), .none)
    }
}
