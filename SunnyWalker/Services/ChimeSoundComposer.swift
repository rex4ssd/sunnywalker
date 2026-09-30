// SunnyWalker — ChimeSoundComposer.swift  |  報時語音合成（單一時刻 / 區間多時刻）
//
// 把「報時鬧鐘」要念的時刻（例：早上七點整 / It's seven o'clock）用 iOS 內建語音合成
// (AVSpeechSynthesizer) 離線 render 成 PCM，寫成一個 16-bit linear PCM 的 CAF 放到 Library/Sounds
// —— 這是 iOS 唯一會讀「自訂鬧鐘/通知音」的容器目錄。
//
// 為什麼產生實體檔（而不是鬧鐘響時即時 TTS）：
//   • 背景 / 鎖屏 / App 被殺時是系統層直接放音，第三方 App 沒有執行機會去跑 AVSpeechSynthesizer。
//     先 render 成 CAF 設成 soundFileName，通知與前景 AlarmRingView 就都能放同一份報時音。
//   • 與既有的 AlarmSoundExporter（錄音 m4a→CAF）走完全相同的格式 / 目錄慣例，下游無需特例。
//
// 區間報時（2026-09-03）：起 07:00 迄 07:30 每 5 分 → 六個時刻各自一個檔（每句話都不一樣），
// 由 `composeSlots` 一次合成、全部成功才回傳（避免半套：7:05 有聲、7:10 沒聲）。
//
// 人聲：家長可選女聲 / 男聲（AVSpeechSynthesisVoice.gender）。該語言沒裝對應性別的語音
// （例：中文預設只有女聲）就退回該語言預設語音——寧可聲音不對，不能沒聲。
//
// 語言：跟著 App 的語言設定（預設＝系統），只分中文 / 英文（其餘一律走英文）。
//
// ⚠️ compose(...) 內部用 semaphore 等 render 完成 —— 嚴禁在 main thread 呼叫（會與
//    AVSpeechSynthesizer 的 callback 互鎖）。呼叫端請用 Task.detached { ChimeSoundComposer.compose(...) }。

import AVFoundation
import Foundation

enum ChimeSoundComposer {

    // MARK: - 單一時刻

    /// 合成「一次」報時音檔（單句，例：早上七點整），寫進 Library/Sounds。
    /// - Returns: CAF 檔名（存進 `Alarm.soundFileName` / `chimeSlotSoundFiles`），失敗回 nil。
    /// - Important: **不可在 main thread 呼叫**（見檔頭）。
    ///
    /// ⚠️ 為什麼只合成「一次」：報時走通知模式，iOS 對「過長」的自訂通知音會悄悄退成預設音
    ///    （真機只驗到 ~4.6s 安全）。連報 N 次塞進同一個檔會超過上限 → 報時整個不出聲。
    ///    所以單句檔保持短（~2-3s），「連報 N 次」由 AlarmScheduler 排 N 顆秒級錯開的通知達成。
    /// - Parameter remainingMinutes: 倒數模式——非 nil 時不念時刻，改念「剩 N 分鐘」。
    /// - Parameter purpose: 倒數模式才用——接在「剩 N 分鐘」後面念的事（例：要上學 → 剩十分鐘要上學）。
    static func compose(hour: Int, minute: Int, locale: Locale,
                        voice: ChimeVoiceGender = .female,
                        remainingMinutes: Int? = nil, purpose: String? = nil) -> String? {
        let h = min(max(hour, 0), 23)
        let m = min(max(minute, 0), 59)
        let isChinese = isChineseLocale(locale)
        guard let spoken = bestSpoken(hour: h, minute: m, locale: locale, voice: voice,
                                      remainingMinutes: remainingMinutes, purpose: purpose) else { return nil }
        // 內容指紋：一般＝HHMM；倒數＝cdNNN（同一時刻切換倒數／改迄時刻，念的字不同 → 檔名也要不同），
        // 倒數再加「要做什麼」標記（p＝有念、x＝太長拿掉了）——橫幅文字照檔名走，跟實際念的一致。
        let fingerprint = remainingMinutes.map { String(format: "cd%03d", $0) + spoken.purposeMark.rawValue }
            ?? String(format: "%02d%02d", h, m)
        // 檔名帶內容指紋（時刻+語言+人聲）＋ epoch：系統音伺服器會用「檔名」快取 CAF，重用同名會放到舊內容；
        // 改時間 / 語言 / 人聲都會換檔名，確保放到最新報時。前綴 chime_ ＝ Alarm.isChimeAlarm 判斷依據。
        let cafName = "\(Alarm.chimeFilePrefix)\(fingerprint)_\(isChinese ? "zh" : "en")_\(voice == .male ? "m" : "f")_\(Int(Date().timeIntervalSince1970)).caf"
        let cafURL = AppPaths.ensureSoundsDirectory().appendingPathComponent(cafName)
        guard write(spoken, to: cafURL, voice: voice) else { return nil }
        return cafName
    }

    /// 區間報時：每個時刻各合成一個檔，**全部成功才回傳**（任一失敗就把已寫的清掉、回 nil）。
    /// 回傳陣列與 `slots` 索引對齊。
    /// - Parameter remaining: 倒數模式每個時刻的「剩幾分鐘」（與 slots 對齊）；nil＝念時刻。
    static func composeSlots(_ slots: [(hour: Int, minute: Int)], locale: Locale,
                             voice: ChimeVoiceGender, remaining: [Int]? = nil,
                             purpose: String? = nil) -> [String]? {
        var out: [String] = []
        for (i, slot) in slots.enumerated() {
            let left = remaining.flatMap { i < $0.count ? $0[i] : nil }
            guard let name = compose(hour: slot.hour, minute: slot.minute, locale: locale,
                                     voice: voice, remainingMinutes: left, purpose: purpose) else {
                for n in out { removeChimeFile(named: n) }
                print("🔔 ChimeSoundComposer.composeSlots: slot \(slot.hour):\(slot.minute) FAILED — rolled back \(out.count) file(s)")
                return nil
            }
            out.append(name)
        }
        return out
    }

    /// 編輯器「試聽」用：寫到 tmp（不進 Library/Sounds、不留垃圾），每次覆蓋同一個檔。
    /// `tag` 讓不同內容的試聽各自一個 tmp 檔（改時間後重合成時，不會覆寫正在播的那個）。
    static func composePreview(hour: Int, minute: Int, locale: Locale,
                               voice: ChimeVoiceGender, remainingMinutes: Int? = nil,
                               purpose: String? = nil, tag: String = "") -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("chime_preview\(tag.isEmpty ? "" : "_" + tag).caf")
        try? FileManager.default.removeItem(at: url)
        guard let spoken = bestSpoken(hour: hour, minute: minute, locale: locale, voice: voice,
                                      remainingMinutes: remainingMinutes, purpose: purpose) else { return nil }
        return write(spoken, to: url, voice: voice) ? url : nil
    }

    /// 刪掉某個舊報時檔（呼叫端在「換掉某顆鬧鐘的報時檔」時用，避免 Library/Sounds 累積）。
    /// 只刪指定檔名，不會誤砍其他報時鬧鐘的檔（每顆鬧鐘的報時檔名各自獨立）。
    static func removeChimeFile(named name: String) {
        guard name.hasPrefix(Alarm.chimeFilePrefix) else { return }
        try? FileManager.default.removeItem(at: AppPaths.soundURL(named: name))
    }

    /// 通知橫幅的文字：跟語音念的一模一樣（例：早上七點零五分；倒數模式：剩三十分鐘／剩三十分鐘要上學）。
    static func phrase(hour: Int, minute: Int, locale: Locale, remainingMinutes: Int? = nil,
                       purpose: String? = nil) -> String {
        if let left = remainingMinutes {
            let what = Alarm.sanitizedCountdownPurpose(purpose)
            return isChineseLocale(locale) ? chineseRemainingPhrase(left, purpose: what)
                                           : englishRemainingPhrase(left, purpose: what)
        }
        let h = min(max(hour, 0), 23), m = min(max(minute, 0), 59)
        return isChineseLocale(locale) ? chinesePhrase(hour: h, minute: m) : englishPhrase(hour: h, minute: m)
    }

    // MARK: - 人聲

    /// 這個語言裝置上有哪些性別的語音可選（給編輯器決定要不要顯示男聲）。
    static func availableGenders(for locale: Locale) -> Set<ChimeVoiceGender> {
        let lang = voiceLanguage(for: locale)
        var out: Set<ChimeVoiceGender> = []
        for v in AVSpeechSynthesisVoice.speechVoices() where v.language == lang {
            switch v.gender {
            case .male:   out.insert(.male)
            case .female: out.insert(.female)
            default:      break
            }
        }
        return out
    }

    /// 挑語音：同語言 + 指定性別，品質高的優先；沒有就退回該語言預設（最後退 en-US）。
    private static func selectVoice(language: String, gender: ChimeVoiceGender) -> AVSpeechSynthesisVoice? {
        let wanted: AVSpeechSynthesisVoiceGender = gender == .male ? .male : .female
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language && $0.gender == wanted }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
        if let best = candidates.first { return best }
        return AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// 檔名裡的語言標籤（zh / en）——AlarmScheduler 用它判斷「App 語言換了，語音檔要重合成」。
    static func languageTag(for locale: Locale) -> String { isChineseLocale(locale) ? "zh" : "en" }

    private static func isChineseLocale(_ locale: Locale) -> Bool {
        locale.identifier.lowercased().hasPrefix("zh")
    }

    private static func voiceLanguage(for locale: Locale) -> String {
        isChineseLocale(locale) ? "zh-TW" : "en-US"
    }

    // MARK: - Render

    /// 一句報時（含前後靜音）最多幾秒——**硬上限**，超過的檔一律不寫。
    /// 依據（2026-10-01 整理 repo／Vein／Apple 論壇）：真機只驗過 3.0s、4.6s 播完整（iPhone 15，鎖屏＋App 被殺）；
    /// 29s 某天播完整、隔天被換成約 2 秒的系統預設音（門檻會隨 iOS 狀態變動）；5.4s 失敗是使用者回報推論、非對照實驗。
    /// 「~2 秒」是 iOS 換上的預設音長度，不是門檻。3.5s 在已驗證的 4.6s 之下留 1 秒以上餘裕。
    /// 模擬器量的是模擬器女聲；實機可能是加強版語音、男聲更慢（Mac 代理實測英文男聲 4.9s）→ 一律合成後量實際長度。
    static let maxSpokenSeconds: Double = 3.5
    /// 平常語速（給小朋友聽，比預設慢；0.92× 被嫌太快）、太長時的加快語速、最後手段的標準語速。
    static let normalRateFactor: Float = 0.7
    static let fastRateFactor: Float = 0.85
    static let lastResortRateFactor: Float = 1.0

    /// 念哪一句、用什麼語速——由長到短依序試，第一個 ≤ `maxSpokenSeconds` 的就寫檔。
    /// 先保住「要做什麼」（加快一點），真的放不下才拿掉它；最後才用標準語速念最短那句。
    static func renderLadder(full: String, plain: String) -> [(text: String, rate: Float)] {
        var ladder: [(text: String, rate: Float)] = [(full, normalRateFactor), (full, fastRateFactor)]
        if plain != full { ladder += [(plain, normalRateFactor), (plain, fastRateFactor)] }
        ladder.append((plain, lastResortRateFactor))
        return ladder
    }

    /// 檔名裡「要做什麼」的標記：p＝有念、x＝有設但整句太長、拿掉了、空＝沒設（或這個功能之前的舊檔）。
    enum PurposeMark: String { case spoken = "p", dropped = "x", none = "" }

    /// 實際要寫進檔的那一版（已過長度保險）。
    struct SpokenChime {
        let buffer: AVAudioPCMBuffer
        let text: String
        let seconds: Double
        let rate: Float
        let purposeMark: PurposeMark
    }

    /// 依退階（`renderLadder`）找第一個 ≤ `maxSpokenSeconds` 的版本，不寫檔。每一版都量實際秒數（硬上限）；
    /// 全部都太長就回 nil（呼叫端保留舊檔／不排這一句），絕不把會被 iOS 換成預設音的長檔交出去。
    /// **不可在 main thread 呼叫**（見檔頭）。
    static func bestSpoken(hour: Int, minute: Int, locale: Locale, voice: ChimeVoiceGender,
                           remainingMinutes: Int? = nil, purpose: String? = nil) -> SpokenChime? {
        let full = phrase(hour: hour, minute: minute, locale: locale, remainingMinutes: remainingMinutes,
                          purpose: purpose)
        let plain = phrase(hour: hour, minute: minute, locale: locale, remainingMinutes: remainingMinutes)
        let voiceObj = selectVoice(language: voiceLanguage(for: locale), gender: voice)

        for step in renderLadder(full: full, plain: plain) {
            guard let sequence = paddedSpeech(step.text, voice: voiceObj, rateFactor: step.rate) else {
                print("🔔 ChimeSoundComposer: render FAILED for phrase=\(step.text)")
                return nil
            }
            let secs = Double(sequence.frameLength) / sequence.format.sampleRate
            guard secs <= maxSpokenSeconds else {
                print("🔔 ChimeSoundComposer: \"\(step.text)\" rate×\(step.rate) = \(String(format: "%.2f", secs))s > \(maxSpokenSeconds)s — trying a shorter version")
                continue
            }
            let mark: PurposeMark = full == plain ? .none : (step.text == full ? .spoken : .dropped)
            return SpokenChime(buffer: sequence, text: step.text, seconds: secs, rate: step.rate, purposeMark: mark)
        }
        print("🔔 ChimeSoundComposer: ⚠️ every version of \"\(full)\" is over \(maxSpokenSeconds)s — not writing")
        return nil
    }

    private static func write(_ spoken: SpokenChime, to url: URL, voice: ChimeVoiceGender) -> Bool {
        do {
            try AlarmSoundExporter.writePCMCAF(spoken.buffer, to: url)
        } catch {
            print("🔔 ChimeSoundComposer: write CAF FAILED — \(error.localizedDescription)")
            return false
        }
        print("🔔 ChimeSoundComposer: wrote \(url.lastPathComponent) — \"\(spoken.text)\" (\(String(format: "%.2f", spoken.seconds))s, \(voice.rawValue), rate×\(spoken.rate))")
        return true
    }

    /// 從報時檔名讀出「要做什麼」有沒有念（橫幅文字要跟實際念的一樣）。
    /// chime_cd030p_zh_f_…caf → .spoken；chime_cd030x_… → .dropped；chime_cd030_… / chime_0705_… → .none。
    static func purposeMark(ofFile name: String) -> PurposeMark {
        guard name.hasPrefix(Alarm.chimeFilePrefix) else { return .none }
        let fingerprint = name.dropFirst(Alarm.chimeFilePrefix.count).prefix { $0 != "_" }
        guard fingerprint.hasPrefix("cd"), let last = fingerprint.last else { return .none }
        return PurposeMark(rawValue: String(last)) ?? .none
    }

    /// 已寫好的報時檔長度（秒）；讀不到回 nil。排程時用來揪出上限之前合成的過長舊檔。
    static func fileSeconds(named name: String) -> Double? {
        guard let f = try? AVAudioFile(forReading: AppPaths.soundURL(named: name)), f.fileFormat.sampleRate > 0 else { return nil }
        return Double(f.length) / f.fileFormat.sampleRate
    }

    /// 量一句話實際念出來（含前後靜音）幾秒，不寫檔——測試與 DEBUG 實機量測用。**不可在 main thread 呼叫。**
    static func spokenSeconds(_ text: String, locale: Locale, voice: ChimeVoiceGender = .female,
                              rateFactor: Float = normalRateFactor) -> Double? {
        let v = selectVoice(language: voiceLanguage(for: locale), gender: voice)
        guard let b = paddedSpeech(text, voice: v, rateFactor: rateFactor) else { return nil }
        return Double(b.frameLength) / b.format.sampleRate
    }

    #if DEBUG
    /// 實機量測（啟動參數 -ChimeLengthProbe 1）：印出最長幾句在「這台裝置的語音」下的實際秒數。
    /// 模擬器語音和實機不同，上限要用實機數字定。
    static func runLengthProbe() {
        let zh = Locale(identifier: "zh-Hant"), en = Locale(identifier: "en")
        let cases: [(String, Locale)] = [
            (phrase(hour: 23, minute: 57, locale: zh), zh),
            (phrase(hour: 23, minute: 57, locale: en), en),
            (phrase(hour: 7, minute: 0, locale: zh, remainingMinutes: 30), zh),
            (phrase(hour: 7, minute: 0, locale: zh, remainingMinutes: 357), zh),
            (phrase(hour: 7, minute: 0, locale: en, remainingMinutes: 357), en),
            (phrase(hour: 7, minute: 0, locale: zh, remainingMinutes: 30, purpose: "要上學"), zh),
            (phrase(hour: 7, minute: 0, locale: zh, remainingMinutes: 357, purpose: "要上學"), zh),
            (phrase(hour: 7, minute: 0, locale: en, remainingMinutes: 30, purpose: "piano time"), en),
            (phrase(hour: 7, minute: 0, locale: en, remainingMinutes: 357, purpose: "piano time"), en),
        ]
        for (text, loc) in cases {
            for voice in ChimeVoiceGender.allCases {
                let normal = spokenSeconds(text, locale: loc, voice: voice)
                let fast = spokenSeconds(text, locale: loc, voice: voice, rateFactor: fastRateFactor)
                print("⏱PROBE \(voice.rawValue) \"\(text)\" normal=\(normal.map { String(format: "%.2f", $0) } ?? "nil")s fast=\(fast.map { String(format: "%.2f", $0) } ?? "nil")s")
            }
        }
        print("⏱PROBE done (limit \(maxSpokenSeconds)s)")
    }
    #endif

    /// 念一句 → 前後各補 0.15 秒靜音（避免開頭／結尾被截）。
    private static func paddedSpeech(_ text: String, voice: AVSpeechSynthesisVoice?, rateFactor: Float) -> AVAudioPCMBuffer? {
        guard let speech = renderPhrase(text, voice: voice, rateFactor: rateFactor), speech.frameLength > 0 else {
            return nil
        }
        let format = speech.format
        let sr = format.sampleRate
        let leadFrames = AVAudioFrameCount(sr * 0.15)
        let tailFrames = AVAudioFrameCount(sr * 0.15)
        let one = speech.frameLength
        let total = leadFrames + one + tailFrames

        guard let sequence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total),
              let dst = sequence.floatChannelData,
              let src = speech.floatChannelData else {
            print("🔔 ChimeSoundComposer: sequence buffer alloc FAILED")
            return nil
        }
        let channels = Int(format.channelCount)
        for c in 0..<channels {
            memset(dst[c], 0, Int(total) * MemoryLayout<Float>.size)
            memcpy(dst[c] + Int(leadFrames), src[c], Int(one) * MemoryLayout<Float>.size)
        }
        sequence.frameLength = total
        return sequence
    }

    /// 用 AVSpeechSynthesizer 離線把一句話 render 成連續 float PCM buffer。
    /// 收集 write callback 吐出的每一塊 buffer（最後一塊 frameLength==0 代表結束），再串成一顆。
    /// 🔴 一顆 app 生命週期共用的 synthesizer，絕不 dealloc。
    /// 之前每次 render 各 new 一顆 local synthesizer，`done.wait` 回來（最後一塊空 buffer 或 15s 逾時）就 return
    /// → synthesizer 被釋放，但 TextToSpeech 內部還有派到 main queue 的收尾工作引用它 →
    /// 主執行緒 SIGSEGV（i15 實機：試聽一按就閃退，TextToSpeech +0x43c2c）。LetCube 同雷（Vein 20260804）。
    /// 一次只 render 一句（renderLock），語音本來就只有一個聲道，共用等於現實。
    private static let sharedSynth = AVSpeechSynthesizer()
    private static let renderLock = NSLock()

    private static func renderPhrase(_ phrase: String, voice: AVSpeechSynthesisVoice?,
                                     rateFactor: Float = normalRateFactor) -> AVAudioPCMBuffer? {
        renderLock.lock()
        defer { renderLock.unlock() }
        let synth = sharedSynth
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = voice
        // 報時念慢一點、咬字清楚（給小朋友聽）。AVSpeechUtteranceDefaultSpeechRate=0.5；
        // 之前 0.92×（≈0.46）使用者反映太快 → 降到 0.7×（≈0.35）放慢。
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rateFactor

        // callback 在 TTS 內部 queue：chunks / finished 用鎖保護，別跟 wait 端搶。
        let state = RenderState()
        synth.write(utterance) { (buffer: AVAudioBuffer) in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 {
                state.finish()
                return
            }
            if let copy = copyFloatBuffer(pcm) { state.append(copy) }
        }

        // render 是非同步的，等它吐完最後一塊空 buffer。15s 上限防呆——逾時就主動叫停，
        // 並再等一下讓它真的收尾（不能帶著還在講的 utterance 離開，下一句會撞）。
        if !state.wait(seconds: 15) {
            print("🔔 ChimeSoundComposer: render TIMEOUT for phrase=\(phrase) — stopping synthesizer")
            synth.stopSpeaking(at: .immediate)
            _ = state.wait(seconds: 2)
            return nil
        }
        let chunks = state.chunks
        guard !chunks.isEmpty else { return nil }
        return concatenate(chunks)
    }

    /// renderPhrase 的跨執行緒狀態（TTS callback queue ↔ 等待端）。
    private final class RenderState: @unchecked Sendable {
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var finished = false
        private var buffers: [AVAudioPCMBuffer] = []

        var chunks: [AVAudioPCMBuffer] { lock.lock(); defer { lock.unlock() }; return buffers }
        func append(_ b: AVAudioPCMBuffer) { lock.lock(); buffers.append(b); lock.unlock() }
        func finish() {
            lock.lock()
            let first = !finished
            finished = true
            lock.unlock()
            if first { done.signal() }
        }
        /// true＝正常收到結束訊號；false＝逾時。
        func wait(seconds: Double) -> Bool { done.wait(timeout: .now() + seconds) == .success }
    }

    /// 深拷貝一塊 float PCM buffer（callback 提供的 buffer 可能被系統重用，必須複製保存）。
    private static func copyFloatBuffer(_ src: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let srcData = src.floatChannelData,
              let dst = AVAudioPCMBuffer(pcmFormat: src.format, frameCapacity: src.frameLength),
              let dstData = dst.floatChannelData else { return nil }
        dst.frameLength = src.frameLength
        let channels = Int(src.format.channelCount)
        for c in 0..<channels {
            memcpy(dstData[c], srcData[c], Int(src.frameLength) * MemoryLayout<Float>.size)
        }
        return dst
    }

    /// 把多塊同格式 float buffer 串成一顆。
    private static func concatenate(_ buffers: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        guard let first = buffers.first else { return nil }
        let format = first.format
        let totalFrames = buffers.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
        guard totalFrames > 0,
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames),
              let outData = out.floatChannelData else { return nil }
        let channels = Int(format.channelCount)
        var cursor = 0
        for buf in buffers {
            guard let src = buf.floatChannelData else { continue }
            for c in 0..<channels {
                memcpy(outData[c] + cursor, src[c], Int(buf.frameLength) * MemoryLayout<Float>.size)
            }
            cursor += Int(buf.frameLength)
        }
        out.frameLength = totalFrames
        return out
    }

    // MARK: - Phrase building

    /// 中文（含時段詞）：早上七點整 / 早上七點零五分 / 晚上七點三十分。
    static func chinesePhrase(hour: Int, minute: Int) -> String {
        let period: String
        switch hour {
        case 0...4:   period = "凌晨"
        case 5...8:   period = "早上"
        case 9...11:  period = "上午"
        case 12:      period = "中午"
        case 13...17: period = "下午"
        default:      period = "晚上"
        }
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let minutePart: String
        if minute == 0 {
            minutePart = "整"
        } else if minute < 10 {
            minutePart = "零" + cnNumber(minute) + "分"
        } else {
            minutePart = cnNumber(minute) + "分"
        }
        return period + cnNumber(h12) + "點" + minutePart
    }

    /// 倒數（中文）：剩三十分鐘 / 剩一小時 / 剩一小時三十分鐘 / 時間到了（0）。
    /// 倒數（中文）：剩三十分鐘／剩一小時／時間到了；有 `purpose` 就接在後面：剩十分鐘要上學。
    static func chineseRemainingPhrase(_ minutes: Int, purpose: String? = nil) -> String {
        let total = max(0, minutes)
        let what = purpose ?? ""
        if total == 0 { return what.isEmpty ? "時間到了" : "時間到了，" + what }  // i18n-ignore: 中文語音要念的句子（只在中文語系用），不是介面字串
        let h = total / 60, m = total % 60
        var s = "剩"
        if h > 0 { s += (h == 2 ? "兩" : cnNumber(h)) + "小時" }
        if m > 0 { s += cnNumber(m) + "分鐘" }
        return s + what
    }

    /// 倒數（英文）：30 minutes left / 1 hour left / 1 hour 30 minutes left / Time's up.
    /// 有 `purpose`（例：school）：Ten minutes until school. / Time for school.
    static func englishRemainingPhrase(_ minutes: Int, purpose: String? = nil) -> String {
        let total = max(0, minutes)
        let what = purpose ?? ""
        if total == 0 { return what.isEmpty ? "Time's up." : "Time for \(what)." }
        let h = total / 60, m = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(spellOut(h)) \(h == 1 ? "hour" : "hours")") }
        if m > 0 { parts.append("\(spellOut(m)) \(m == 1 ? "minute" : "minutes")") }
        // 句首大寫：這句同時是通知橫幅的文字。
        let s = parts.joined(separator: " ") + (what.isEmpty ? " left." : " until \(what).")
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// 0...59 的中文數字（時用 1...12，分用 0...59）。
    private static func cnNumber(_ n: Int) -> String {
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        if n < 10 { return digits[n] }
        if n == 10 { return "十" }
        if n < 20 { return "十" + digits[n % 10] }
        let tens = n / 10, ones = n % 10
        return digits[tens] + "十" + (ones == 0 ? "" : digits[ones])
    }

    /// 英文：It's seven o'clock in the morning. / It's seven oh five in the morning.
    static func englishPhrase(hour: Int, minute: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let hourWord = spellOut(h12)
        let base: String
        if minute == 0 {
            base = "It's \(hourWord) o'clock"
        } else if minute < 10 {
            base = "It's \(hourWord) oh \(spellOut(minute))"
        } else {
            base = "It's \(hourWord) \(spellOut(minute))"
        }
        let period: String
        switch hour {
        case 5...11:  period = "in the morning"
        case 12...17: period = "in the afternoon"
        case 18...21: period = "in the evening"
        default:      period = "at night"
        }
        return "\(base) \(period)."
    }

    private static func spellOut(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .spellOut
        f.locale = Locale(identifier: "en-US")
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
