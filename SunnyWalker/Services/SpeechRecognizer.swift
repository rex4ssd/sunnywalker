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

    /// - Parameter extraKeywords: 每個鬧鐘的自定口令，與預設詞一起比對（自定 + 預設都認）。
    func startListening(onMatch: @escaping (String) -> Void, onFailure: (() -> Void)? = nil, listeningTimeout: TimeInterval = 8.0, extraKeywords: [String] = []) throws {
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
        // ★ Issue #1 核心修法：開啟 voice processing（硬體回聲消除 AEC）。
        // 沒有 AEC 時，鬧鐘鈴聲（家長錄音，內容常常就是「起床囉/我起床了」）即使被 duck 到
        // 12% 仍從喇叭外放 → on-device 辨識器把「自己的播放」轉成文字 → 立刻 self-match →
        // 沒人喊話也辨識成功、自動關閉。AEC 會把已知的播放訊號從 mic 輸入扣掉，杜絕 self-match。
        // setVoiceProcessingEnabled 必須在讀 format / installTap 之前呼叫（它會改變 input 格式）。
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            print("🎤 SpeechRecognizer: voice processing (AEC) ENABLED — 鬧鐘外放不會再被辨識成口令")
        } catch {
            // AEC 開不起來不致命（少數裝置/路由會失敗）；退回純 duck，但 log 出來方便追。
            print("🎤 SpeechRecognizer: ⚠️ setVoiceProcessingEnabled FAILED — \(error.localizedDescription)（回退無 AEC，self-match 風險升高）")
        }
        let format = inputNode.outputFormat(forBus: 0)
        // Defensive: a 0 Hz / 0-channel format means the mic route isn't ready.
        // Installing a tap with it crashes ("required condition is false: format.sampleRate").
        guard format.sampleRate > 0, format.channelCount > 0 else {
            request = nil
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
            // Roll back the tap so a retry starts from a clean state.
            print("🎤 SpeechRecognizer: audioEngine.start() FAILED — \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            request = nil
            throw error
        }
        isListening = true
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
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
