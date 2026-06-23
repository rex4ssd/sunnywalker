// SunnyWalker — ChimeSoundComposer.swift  |  多人鬧鐘「報時」語音合成
//
// 把「報時鬧鐘」要念的時刻（例：早上七點整 / It's seven o'clock）用 iOS 內建語音合成
// (AVSpeechSynthesizer) 離線 render 成 PCM，連報 N 次（中間留靜音間隔），寫成一個 16-bit
// linear PCM 的 CAF 放到 Library/Sounds —— 這是 iOS 唯一會讀「自訂鬧鐘/通知音」的容器目錄。
//
// 為什麼產生實體檔（而不是鬧鐘響時即時 TTS）：
//   • 背景 / 鎖屏 / App 被殺時是 AlarmKit 用 `sound: .named(soundFileName)` 直接從系統層放音，
//     第三方 App 沒有執行機會去跑 AVSpeechSynthesizer。先 render 成 CAF 設成 soundFileName，
//     AlarmKit 與前景 AlarmRingView（resolveAlarmAudio 會找 Library/Sounds）就都能放同一份報時音。
//   • 與既有的 AlarmSoundExporter（錄音 m4a→CAF）走完全相同的格式 / 目錄慣例，下游無需特例。
//
// 語言：跟著 App 的語言設定（預設＝系統），只分中文 / 英文（其餘一律走英文）。
//
// ⚠️ compose(...) 內部用 semaphore 等 render 完成 —— 嚴禁在 main thread 呼叫（會與
//    AVSpeechSynthesizer 的 callback 互鎖）。呼叫端請用 Task.detached { ChimeSoundComposer.compose(...) }。

import AVFoundation
import Foundation

enum ChimeSoundComposer {

    /// 合成「一次」報時音檔（單句，例：早上七點整）。
    /// - Parameters:
    ///   - hour:   24 小時制時 (0...23)
    ///   - minute: 分 (0...59)
    ///   - locale: 決定語言（zh* → 中文，其餘 → 英文）
    /// - Returns: 寫進 Library/Sounds 的 CAF 檔名（存進 `Alarm.soundFileName`），失敗回 nil。
    /// - Important: **不可在 main thread 呼叫**（見檔頭）。
    ///
    /// ⚠️ 為什麼只合成「一次」：報時走通知模式，iOS 對「過長」的自訂通知音會悄悄退成預設音
    ///    （真機只驗到 ~4.6s 安全）。連報 N 次塞進同一個檔會超過上限 → 報時整個不出聲（使用者回報
    ///    「報時開不起來」，實測 count=2 已 5.4s）。所以單句檔保持短（~2-3s），「連報 N 次」改由
    ///    AlarmScheduler 排 N 顆秒級錯開的通知達成（見 scheduleChimeRepeats）。
    static func compose(hour: Int, minute: Int, locale: Locale) -> String? {
        let h = min(max(hour, 0), 23)
        let m = min(max(minute, 0), 59)
        let isChinese = locale.identifier.lowercased().hasPrefix("zh")

        let phrase = isChinese ? chinesePhrase(hour: h, minute: m)
                               : englishPhrase(hour: h, minute: m)
        let voiceLang = isChinese ? "zh-TW" : "en-US"

        // 1. render 一句報時成連續的 float PCM。
        guard let speech = renderPhrase(phrase, voiceLanguage: voiceLang),
              speech.frameLength > 0 else {
            print("🔔 ChimeSoundComposer: render FAILED for phrase=\(phrase)")
            return nil
        }

        // 2. 前後各留一點靜音（避免開頭/結尾被截）。
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

        // 3. 寫成 16-bit linear PCM CAF（AlarmKit / UNNotification 最穩定接受的格式）到 Library/Sounds。
        let fm = FileManager.default
        let soundsDir = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
        try? fm.createDirectory(at: soundsDir, withIntermediateDirectories: true)

        // 檔名帶內容指紋（時刻+語言）＋ epoch：系統音伺服器會用「檔名」快取 CAF，重用同名會放到舊內容；
        // 改時間 / 語言都會換檔名，確保放到最新報時。前綴 chime_ ＝ Alarm.isChimeAlarm 判斷依據。
        let cafName = "\(Alarm.chimeFilePrefix)\(String(format: "%02d%02d", h, m))_\(isChinese ? "zh" : "en")_\(Int(Date().timeIntervalSince1970)).caf"
        let cafURL = soundsDir.appendingPathComponent(cafName)

        let outSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sr,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        do {
            // forWriting 的 processingFormat = 標準 float32 deinterleaved @ 同 sr/channels，
            // 與 sequence（render 出來的 float buffer）格式一致；AVAudioFile 在寫檔時自動轉成 16-bit。
            let outFile = try AVAudioFile(forWriting: cafURL, settings: outSettings)
            try outFile.write(from: sequence)
        } catch {
            print("🔔 ChimeSoundComposer: write CAF FAILED — \(error.localizedDescription)")
            return nil
        }

        let secs = Double(total) / sr
        print("🔔 ChimeSoundComposer: wrote \(cafName) — \"\(phrase)\" (\(String(format: "%.1f", secs))s, single)")
        return cafName
    }

    /// 刪掉某個舊報時檔（呼叫端在「換掉某顆鬧鐘的報時檔」時用，避免 Library/Sounds 累積）。
    /// 只刪指定檔名，不會誤砍其他報時鬧鐘的檔（每顆鬧鐘的報時檔名各自獨立）。
    static func removeChimeFile(named name: String) {
        guard name.hasPrefix(Alarm.chimeFilePrefix) else { return }
        let fm = FileManager.default
        let url = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
            .appendingPathComponent(name)
        try? fm.removeItem(at: url)
    }

    // MARK: - Render

    /// 用 AVSpeechSynthesizer 離線把一句話 render 成連續 float PCM buffer。
    /// 收集 write callback 吐出的每一塊 buffer（最後一塊 frameLength==0 代表結束），再串成一顆。
    private static func renderPhrase(_ phrase: String, voiceLanguage: String) -> AVAudioPCMBuffer? {
        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        // 報時念慢一點、咬字清楚（給小朋友聽）。AVSpeechUtteranceDefaultSpeechRate=0.5；
        // 之前 0.92×（≈0.46）使用者反映太快 → 降到 0.7×（≈0.35）放慢。
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.7

        var chunks: [AVAudioPCMBuffer] = []
        let done = DispatchSemaphore(value: 0)
        var finished = false

        synth.write(utterance) { (buffer: AVAudioBuffer) in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 {
                if !finished { finished = true; done.signal() }
                return
            }
            if let copy = copyFloatBuffer(pcm) { chunks.append(copy) }
        }

        // render 是非同步的（callback 在內部 queue），等它吐完最後一塊空 buffer。給 15s 上限防呆。
        _ = done.wait(timeout: .now() + 15)
        guard !chunks.isEmpty else { return nil }
        return concatenate(chunks)
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
    private static func chinesePhrase(hour: Int, minute: Int) -> String {
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
    private static func englishPhrase(hour: Int, minute: Int) -> String {
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
