// SunnyWalker — SpeechRecognizer.swift  |  Day 5  |  on-device SFSpeechRecognizer + AVAudioEngine

import Speech
import AVFoundation
import Foundation

@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var recognizedText = ""
    @Published var matchedKeyword: String?

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isListening = false
    private var timeoutTask: Task<Void, Never>?

    // ★ Issue #1+#2 修法：鈴聲改由「本 engine 內」的 player node 播放，當 AEC 參考訊號。
    // 舊版用外部 AVAudioPlayer 同時在 .playAndRecord session 上輸出，與 VPIO 的 output unit
    // 搶資源 → `auou/vpio/appl render err: -1` 狂洗、mic 不穩。把鈴聲收進同一個 engine 後，
    // voice processing 能正確把它從 mic 扣掉，render -1 消失、self-match 也擋得更乾淨。
    private let alarmPlayerNode = AVAudioPlayerNode()
    private var alarmFile: AVAudioFile?
    private var alarmGap = 0
    private var alarmLoopGeneration = 0   // 防止舊的 loop 排程在 stop/restart 後又重排

    private let keywords: [String]

    init() {
        // Pick recognizer locale and wake keywords to match the app's chosen language.
        // SunnyLocalization.code is read once at init time — the AlarmRingView creates a
        // fresh SpeechRecognizer via @StateObject, so language changes take effect the
        // next time AlarmRingView appears.
        let code = SunnyLocalization.code
        switch code {
        case "en":
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            keywords   = ["I'm awake", "I am awake", "I'm up", "I am up", "wake up"]
        default:
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
            // ⚠️ 只留「起床/醒來」這類明確的起床語句。原本的「好的 / 知道了」太通用——
            // text.contains 子字串比對下，環境音 / 電視 / 家長錄音裡隨便一句都會誤中 →
            // 沒人喊話也辨識成功、鬧鐘自動關掉（issue #1 的「自動辨識成功」根因之一）。
            keywords   = ["我起床了", "我醒了", "我起來了", "起床囉", "起床了"]
        }
    }

    /// - Parameters:
    ///   - extraKeywords: 每個鬧鐘的自定口令，與預設詞一起比對（自定 + 預設都認）。
    ///   - alarmReferenceURL: 響鈴音檔。傳入時，鈴聲改由「本 engine 內」的 AVAudioPlayerNode 播放，
    ///     讓 voice processing(AEC) 能把它當參考訊號從 mic 扣掉。取代舊版「外部 AVAudioPlayer + duck」
    ///     的做法（舊版兩顆 output unit 搶 .playAndRecord session → render err -1、聲控時好時壞）。
    ///   - alarmGapSeconds: 每段鈴聲之間的靜音秒數（給小孩開口的空檔）。
    ///   - duckVolume: 聆聽時鈴聲音量（0–1）。AEC 會把它從 mic 扣掉，所以可放比舊版更大聲也不誤判。
    func startListening(onMatch: @escaping (String) -> Void,
                        onFailure: (() -> Void)? = nil,
                        listeningTimeout: TimeInterval = 8.0,
                        extraKeywords: [String] = [],
                        alarmReferenceURL: URL? = nil,
                        alarmGapSeconds: Int = 0,
                        duckVolume: Float = 0.12) throws {
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "SpeechRecognizer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: L("語音辨識器不可用")])
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw NSError(domain: "SpeechRecognizer", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: L("此裝置不支援離線辨識")])
        }

        recognizedText = ""
        matchedKeyword = nil

        // 預設詞 + 這個鬧鐘的自定口令一起比對。去重、濾空。
        let allKeywords = keywords + extraKeywords.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // The session must be in a recording-capable category BEFORE we read the
        // input node format. AlarmRingView plays the parent's recording first, which
        // leaves the session in `.playback` — in that state the input node reports a
        // 0 Hz format and `installTap` throws an Obj-C exception (hard crash).
        // `.playAndRecord` keeps playback working while enabling the mic.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true, options: [])
        print("🎤 SpeechRecognizer: session → .playAndRecord active (locale=\(recognizer.locale.identifier), onDevice=\(recognizer.supportsOnDeviceRecognition))")

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.requiresOnDeviceRecognition = true  // 100% offline — never remove
        newRequest.shouldReportPartialResults = true
        request = newRequest

        let inputNode = audioEngine.inputNode

        // 兩種模式：
        //  A. alarmReferenceURL != nil → 鈴聲與聆聽「並存」：需要 VPIO/AEC 把鈴聲從 mic 扣掉，
        //     並把鈴聲掛進同一個 engine 當參考訊號（強制走喇叭，否則 VPIO 預設走聽筒會很小聲）。
        //  B. alarmReferenceURL == nil → time-multiplex：聆聽時鈴聲是靜音的（AlarmRingView 已 stop），
        //     沒有並存播放 → 不需要 AEC。關掉 VPIO 用「純 mic」最穩、擷取最乾淨（不會像開了 VPIO +
        //     in-engine 播放時整路 starve 到完全沒 partial）。這是目前 AlarmRingView 走的路徑。
        var alarmReady = false
        if let alarmReferenceURL {
            try? session.overrideOutputAudioPort(.speaker)
            do {
                try inputNode.setVoiceProcessingEnabled(true)   // 改 input 格式，須在讀 format 前
                print("🎤 SpeechRecognizer: voice processing (AEC) ENABLED — 鬧鐘外放不會再被辨識成口令")
            } catch {
                print("🎤 SpeechRecognizer: ⚠️ setVoiceProcessingEnabled FAILED — \(error.localizedDescription)（回退無 AEC）")
            }
            alarmReady = prepareAlarmReference(url: alarmReferenceURL, gap: alarmGapSeconds, volume: duckVolume)
        } else {
            // 確保 VPIO 是關的（plain mic）。engine 此時未 start，是安全的切換時機。
            try? inputNode.setVoiceProcessingEnabled(false)
            print("🎤 SpeechRecognizer: plain mic（聆聽時鈴聲靜音，VPIO off — 乾淨擷取）")
        }

        let format = inputNode.outputFormat(forBus: 0)
        // Defensive: a 0 Hz / 0-channel format means the mic route isn't ready.
        // Installing a tap with it crashes ("required condition is false: format.sampleRate").
        guard format.sampleRate > 0, format.channelCount > 0 else {
            request = nil
            teardownAlarmReference()
            throw NSError(domain: "SpeechRecognizer", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: L("麥克風尚未就緒")])
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            // Roll back the tap + alarm node so a retry starts from a clean state.
            print("🎤 SpeechRecognizer: audioEngine.start() FAILED — \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            teardownAlarmReference()
            request = nil
            throw error
        }
        isListening = true

        // engine 起來後才開始排程鈴聲 loop（completion 內會檢查 isListening + generation）。
        if alarmReady {
            alarmLoopGeneration &+= 1
            scheduleAlarmLoop(generation: alarmLoopGeneration)
            alarmPlayerNode.play()
            print("🎤 SpeechRecognizer: alarm reference playing in-engine (AEC ref, vol=\(duckVolume))")
        }
        print("🎤 SpeechRecognizer: listening (inputFormat sampleRate=\(format.sampleRate) ch=\(format.channelCount))")

        // Fires onFailure after listeningTimeout seconds if the child says random words
        // and no keyword match occurs (the primary spec §8 failure scenario, not just system errors).
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(listeningTimeout))
            guard let self, !Task.isCancelled, self.isListening else { return }
            self.stop()
            onFailure?()
        }

        // The recognition handler is invoked on an arbitrary Speech-framework queue.
        // Hop to the main actor before touching @Published state, the audio engine,
        // or the onMatch/onFailure callbacks (which mutate SwiftUI state + SwiftData).
        task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                // Cancelling the task (via stop(), after a match, or on timeout) re-invokes
                // this handler with a cancellation error. Without this guard that fires a
                // spurious onFailure AFTER a successful match — bumping the failure count and
                // showing the fallback button even though the child woke up. isListening is
                // cleared first thing in stop(), so any post-stop callback exits here.
                guard self.isListening else { return }
                if let error {
                    print("SpeechRecognizer: recognition error — \(error.localizedDescription)")
                    self.stop()
                    onFailure?()
                    return
                }
                guard let text = result?.bestTranscription.formattedString else { return }
                self.recognizedText = text

                let hit = allKeywords.first(where: { text.contains($0) })
                // 把每次 partial transcription 都印出來——裝置上一看就知道辨識器到底「聽到」什麼，
                // 以及是不是把鬧鐘自己的播放當成口令（issue #1 診斷用）。
                print("🎤 SpeechRecognizer: heard='\(text)' matched=\(hit ?? "—") final=\(result?.isFinal ?? false)")
                if let hit {
                    self.matchedKeyword = hit
                    onMatch(hit)
                    self.stop()
                }
            }
        }
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        timeoutTask?.cancel()
        timeoutTask = nil
        teardownAlarmReference()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    // MARK: - Alarm reference (AEC) playback through the recognition engine

    /// 把鈴聲音檔接到本 engine 的 player node → mainMixer。回傳是否成功（失敗就聆聽時靜音，不致命）。
    private func prepareAlarmReference(url: URL, gap: Int, volume: Float) -> Bool {
        do {
            let file = try AVAudioFile(forReading: url)
            alarmFile = file
            alarmGap  = max(0, gap)
            if alarmPlayerNode.engine == nil {
                audioEngine.attach(alarmPlayerNode)
            }
            // engine 此時尚未 start，是安全的 (re)connect 時機。format 用檔案的 processingFormat，
            // mixer/VPIO 會自動做 sample-rate 轉換到輸出。
            audioEngine.connect(alarmPlayerNode, to: audioEngine.mainMixerNode, format: file.processingFormat)
            alarmPlayerNode.volume = volume
            return true
        } catch {
            print("🎤 SpeechRecognizer: ⚠️ alarm reference load FAILED — \(error.localizedDescription)（聆聽時鈴聲將靜音）")
            alarmFile = nil
            return false
        }
    }

    /// 排一段鈴聲；播完（dataPlayedBack）等 gap 秒再排下一段。generation 變了或停止聆聽就不再續排。
    private func scheduleAlarmLoop(generation: Int) {
        guard let file = alarmFile else { return }
        alarmPlayerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isListening, generation == self.alarmLoopGeneration else { return }
                if self.alarmGap > 0 {
                    try? await Task.sleep(for: .seconds(Double(self.alarmGap)))
                }
                guard self.isListening, generation == self.alarmLoopGeneration else { return }
                self.scheduleAlarmLoop(generation: generation)
            }
        }
    }

    private func teardownAlarmReference() {
        alarmLoopGeneration &+= 1   // 讓任何在途的 completion 續排失效
        if alarmPlayerNode.engine != nil, alarmPlayerNode.isPlaying {
            alarmPlayerNode.stop()
        }
        alarmFile = nil
    }
}
