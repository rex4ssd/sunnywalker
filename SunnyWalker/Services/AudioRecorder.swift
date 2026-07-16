// SunnyWalker — AudioRecorder.swift  |  Day 5  |  recording via shared AudioCoreKit (spec §4 stage 2)

import AVFoundation
import Speech
import Foundation
import UIKit
import Combine
import AudioCoreKit

/// 家長錄音薄包裝 — 引擎換裝共用庫 AudioCoreKit `VoiceRecordController`
/// （AVAudioEngine + Apple voice processing、30s 分段防 crash、中斷/路由自動恢復、
///  AVAudioSession 統一走 AudioSessionCoordinator）。
///
/// 對外保留原 AVAudioRecorder 版的行為契約：
///   • 檔案落點/命名不變：`Documents/Recordings/<name>.m4a` — VoiceClip（SwiftData）
///     與 AlarmSoundExporter 都依賴此路徑，既有用戶錄音檔完全不受影響。
///     共用件自產 baseName（Voice-Memos 風格），所以 finalize 縫合後改名成 <name>.m4a。
///   • FeatureLimits 長度上限不變：免費 3 分鐘 / Pro 無限。共用件沒有
///     record(forDuration:) 硬上限參數，改為觀察 `elapsed` 到點自動 stop（備援；
///     UI 層計時器照舊負責收尾流程 — 存檔名、匯出 CAF）。
@MainActor
final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var currentURL: URL?
    /// 即時音量（0…1，共用件 tap RMS）— 錄音畫面的音量回饋。
    @Published private(set) var level: Float = 0

    /// 每段自定錄音的長度上限（秒）。免費版 3 分鐘、Pro 無限——統一從 FeatureLimits 取。
    static var maxRecordingSeconds: TimeInterval { FeatureLimits.maxAlarmRecordingSeconds }

    /// 錄音落點 — 沿用 AVAudioRecorder 時代的目錄，不得改（既有用戶檔案都在這）。
    nonisolated static var recordingsDirectory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    /// 純函式：已錄秒數是否達上限（Pro 的 .infinity 永遠 false）。拆出來可測。
    nonisolated static func shouldAutoStop(elapsed: TimeInterval, cap: TimeInterval) -> Bool {
        cap.isFinite && elapsed >= cap
    }

    private let controller: VoiceRecordController
    private var cancellables = Set<AnyCancellable>()
    /// start(named:) 傳入的目標檔名；finalize 後把共用件縫合檔改名成 <name>.m4a。
    private var pendingName: String?
    /// 進行中的 stop→finalize→改名流程。手動停止與 elapsed 上限備援撞在一起時
    /// 共用同一個 task — 不會 double-finalize。
    private var stopTask: Task<URL?, Never>?

    init(directory: URL = AudioRecorder.recordingsDirectory) {
        controller = VoiceRecordController(directory: directory, profile: .voiceMemo)
        bindController()
    }

    private func bindController() {
        controller.$isRecording
            .sink { [weak self] in self?.isRecording = $0 }
            .store(in: &cancellables)
        controller.$level
            .sink { [weak self] in self?.level = $0 }
            .store(in: &cancellables)
        // FeatureLimits 硬上限備援：即使 UI 計時器沒跑到（切背景等），錄音也一定停。
        controller.$elapsed
            .sink { [weak self] elapsed in
                guard let self,
                      Self.shouldAutoStop(elapsed: elapsed, cap: Self.maxRecordingSeconds),
                      self.controller.isRecording, self.stopTask == nil else { return }
                self.stopTask = self.makeStopTask()
            }
            .store(in: &cancellables)
    }

    /// 開始錄音，最終檔為 `Recordings/<name>.m4a`。失敗丟型別化 AudioCoreKit.RecordError。
    func start(named name: String) async throws {
        // 錄音中重入 no-op：不得中途換掉 pendingName（rename 目標）。UI 按鈕狀態通常擋住這條路。
        guard !controller.isRecording else { return }
        stopTask = nil
        pendingName = name
        try await controller.start()
        // start 可能被 await 期間落地的 stop() 靜默取消（共用件 startGeneration：不丟錯、也沒開錄）。
        // 此時保持 inert — 不設 currentURL，否則 hasRecording 會誤判「已有錄音」。
        guard controller.isRecording else { return }
        // 與 AVAudioRecorder 版一致：start 當下 currentURL 即指向目標檔（hasRecording 判斷用）。
        currentURL = controller.directory.appendingPathComponent("\(name).m4a")
    }

    /// 停止並完成錄音檔：stop → finalize（縫合分段）→ 改名成 <name>.m4a。
    /// 回傳最終檔 URL；idle 時為 no-op 回 nil。冪等 — 與上限備援重複呼叫回同一結果。
    @discardableResult
    func stop() async -> URL? {
        if let task = stopTask { return await task.value }
        guard controller.isRecording else {
            // start() 可能還懸在 await（權限窗/session 啟用中）— 共用件的
            // startGeneration 機制：此刻落地的 stop 獲勝，那筆 start 會自行中止。
            controller.stop()
            return nil
        }
        let task = makeStopTask()
        stopTask = task
        return await task.value
    }

    private func makeStopTask() -> Task<URL?, Never> {
        let name = pendingName
        let controller = self.controller
        return Task { @MainActor [weak self] in
            controller.stop()
            guard let stitched = await controller.finalize() else { return nil }
            guard let name else { return stitched }
            let dest = controller.directory.appendingPathComponent("\(name).m4a")
            if stitched != dest {
                // 覆蓋同名舊檔 = 原 AVAudioRecorder(url:) 的重錄行為。
                try? FileManager.default.removeItem(at: dest)
                do {
                    try FileManager.default.moveItem(at: stitched, to: dest)
                } catch {
                    self?.currentURL = stitched
                    return stitched
                }
            }
            self?.currentURL = dest
            return dest
        }
    }
}

// MARK: - Background listening (Tier 2, experimental, OFF by default)

/// Plain snapshot of an alarm so the manager can read times off the main run loop without
/// touching SwiftData @Model objects (which can be invalidated).
struct AlarmSnapshot {
    let id: UUID
    let hour: Int
    let minute: Int
    let weekdays: [Int]      // 1=Sun … 7=Sat
    let isEnabled: Bool
    let recordingName: String
    let soundFileName: String
    let requireAppToStop: Bool   // 貪睡模式: strict alarms must be completed in-app, not voice-stopped from background
}

/// Keeps a microphone session alive — started in the foreground — so the alarm can ring AND be
/// voice-stopped while the screen is off / app is backgrounded, the way a voice-recorder app keeps
/// recording in the background. iOS only lets you *continue* a foreground-started audio session in
/// the background (never *start* one from a suspended app), so this must be kicked off while active.
///
/// ⚠️ EXPERIMENTAL / OFF BY DEFAULT. Trade-offs (see docs/design_background_voice_stop.md):
///   • The orange mic indicator stays lit the whole time, and the mic is used continuously.
///   • Battery cost; App Review will scrutinise an always-on mic in a kids app.
///   • While the app is in the FOREGROUND, the normal AlarmRingView path handles the alarm — this
///     manager only fires its own ring when the app is backgrounded (avoids two engines clashing).
@MainActor
final class BackgroundListeningManager: ObservableObject {

    static let shared = BackgroundListeningManager()
    private init() {}

    @Published private(set) var isActive = false   // keep-alive session running
    @Published private(set) var isFiring = false   // an alarm is currently ringing in background

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(
        locale: Locale(identifier: SunnyLocalization.code == "en" ? "en-US" : "zh-TW")
    )
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recogTask: SFSpeechRecognitionTask?
    private var alarmPlayer: AVAudioPlayer?
    private var tickTimer: Timer?
    private var autoStopTask: Task<Void, Never>?

    private var alarms: [AlarmSnapshot] = []
    private var lastFiredKey: String?
    private var firingAlarmID: UUID?     // which alarm is currently ringing in the background
    private var firingStrict = false     // is that alarm 貪睡(strict)? strict can't be voice-stopped here
    private var interruptionObserver: NSObjectProtocol?   // diagnostic: catches AlarmKit seizing the audio session

    private var keywords: [String] {
        SunnyLocalization.code == "en"
            ? ["i'm awake", "i am awake", "i'm up", "i am up", "wake up", "awake"]
            : ["我起床了", "好的", "知道了", "起床囉"]
    }

    /// Latest alarm list, pushed from HomeView whenever @Query changes.
    func updateAlarms(_ snaps: [AlarmSnapshot]) {
        alarms = snaps
    }

    // MARK: - Lifecycle

    /// Start the keep-alive mic session. MUST be called while the app is in the foreground.
    func start() {
        guard AppSettings.shared.backgroundListeningEnabled else { return }
        guard !isActive else { return }
        // Confirmed on-device: while an AlarmKit alarm rings it SEIZES the audio session
        // (AVAudioSession interruption BEGAN), so background speech recognition gets no audio — and
        // in the foreground we defer to AlarmRingView anyway. Keeping an always-on mic here would
        // just drain battery (and keep the orange dot lit) for something that can never work.
        // So only run on the UNNotification fallback path, where the app owns the session and CAN
        // listen while ringing (AlarmKit unauthorized).
        guard !AlarmKitService.shared.isAuthorized else {
            print("🟠 BGListen: AlarmKit authorized — it owns the mic while ringing, so background voice-stop can't work; NOT starting (saves battery). Voice 'I'm awake' is foreground-only, inside AlarmRingView.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true)

            let input = engine.inputNode
            let fmt = input.outputFormat(forBus: 0)
            guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
                print("🟠 BGListen: input node not ready (sampleRate=\(fmt.sampleRate)) — abort start")
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, _ in
                // Feed recognition only while firing; otherwise the buffer is simply discarded,
                // which is enough to keep the session (and the app) alive in the background.
                self?.request?.append(buffer)
            }
            engine.prepare()
            try engine.start()
            isActive = true
            startTimer()

            // DIAGNOSTIC: when an AlarmKit alarm rings it plays high-priority audio that typically
            // interrupts our session — which would explain why background voice-stop never matches.
            // Log began/ended so a real-device test can confirm; best-effort resume on .ended.
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 99
                let type = AVAudioSession.InterruptionType(rawValue: raw)
                if type == .began {
                    print("🟠 BGListen: ⚠️ AVAudioSession interruption BEGAN — mic seized (likely AlarmKit alarm). Recognition gets NO audio until it ENDS.")
                } else if type == .ended {
                    print("🟠 BGListen: AVAudioSession interruption ENDED — attempting to resume mic")
                    Task { @MainActor in self?.resumeAfterInterruption() }
                } else {
                    print("🟠 BGListen: AVAudioSession interruption (raw=\(raw))")
                }
            }

            print("🟠 BGListen: started — mic session kept alive (orange dot on)")
        } catch {
            print("🟠 BGListen: start FAILED — \(error.localizedDescription)")
        }
    }

    /// Tear down the session and release the mic.
    func stop() {
        guard isActive else { return }
        stopFiring(reason: "manager stop")
        tickTimer?.invalidate(); tickTimer = nil
        if let obs = interruptionObserver {
            NotificationCenter.default.removeObserver(obs)
            interruptionObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isActive = false
        print("🟠 BGListen: stopped — mic released")
    }

    /// Best-effort recovery after an audio-session interruption (e.g. an AlarmKit alarm finishing).
    /// Also diagnostic: the log tells us whether we ever get the session back while still firing.
    private func resumeAfterInterruption() {
        guard isActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { engine.prepare(); try engine.start() }
            if isFiring { restartRecognition() }
            print("🟠 BGListen: resumed after interruption (engineRunning=\(engine.isRunning), firing=\(isFiring))")
        } catch {
            print("🟠 BGListen: resume after interruption FAILED — \(error.localizedDescription)")
        }
    }

    // MARK: - Timer / due-alarm detection

    private func startTimer() {
        tickTimer?.invalidate()
        // 5s cadence: fine enough to catch the minute boundary. Fires on the main run loop, which
        // keeps running because the audio session prevents the app from being suspended.
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    private func tick() {
        guard isActive, !isFiring else { return }
        let cal = Calendar.current
        let now = Date()
        let c = cal.dateComponents([.hour, .minute, .weekday, .day], from: now)
        guard let h = c.hour, let m = c.minute, let wd = c.weekday, let day = c.day else { return }
        for a in alarms where a.isEnabled && a.hour == h && a.minute == m {
            let firesToday = a.weekdays.isEmpty || a.weekdays.contains(wd)
            guard firesToday else { continue }
            let key = "\(a.id.uuidString)-\(day)-\(h)-\(m)"
            guard key != lastFiredKey else { continue }  // already handled this minute
            lastFiredKey = key
            beginFiring(a)
            break
        }
    }

    // MARK: - Fire / stop one alarm in the background

    private func beginFiring(_ a: AlarmSnapshot) {
        // Foreground? Let the normal full-screen AlarmRingView own the alarm + mic — running two
        // AVAudioEngines on the input node at once would clash. We only self-fire in background.
        guard UIApplication.shared.applicationState != .active else {
            print("🟠 BGListen: alarm \(a.id.uuidString.prefix(8)) due but app ACTIVE — deferring to AlarmRingView")
            return
        }
        guard !isFiring else { return }
        isFiring = true
        firingAlarmID = a.id
        firingStrict = a.requireAppToStop
        // When AlarmKit is authorized it is ALREADY ringing this alarm (the black banner sound).
        // Playing our own AVAudioPlayer on top would double the sound — so in that case we only
        // LISTEN, and on a wake-word match we stop the AlarmKit alarm itself. We only play our own
        // sound on the UNNotification fallback path (AlarmKit unauthorized).
        let alarmKitRinging = AlarmKitService.shared.isAuthorized
        print("🟠 BGListen: FIRING \(a.id.uuidString.prefix(8)) in background — strict=\(firingStrict) alarmKitRinging=\(alarmKitRinging) engineRunning=\(engine.isRunning) → \(alarmKitRinging ? "listen-only" : "play+listen")")
        if !alarmKitRinging { playAlarmSound(a) }
        startRecognition()
        let minutes = max(1, min(10, AppSettings.shared.alarmRingDurationMinutes))
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(minutes * 60)))
            guard !Task.isCancelled else { return }
            self?.stopFiring(reason: "ring-duration timeout", stopSystemAlarm: true)
        }
    }

    /// Stop the background ring.
    /// - Parameter stopSystemAlarm: when true, ALSO stop the underlying AlarmKit alarm (and suppress
    ///   the wake-screen route). Used when the child voice-stops or the ring times out. It is FALSE
    ///   for the "manager stop" handoff, where AlarmRingView is taking over and owns the alarm.
    private func stopFiring(reason: String, stopSystemAlarm: Bool = false) {
        guard isFiring else { return }
        print("🟠 BGListen: stop firing (\(reason)) stopSystemAlarm=\(stopSystemAlarm)")
        isFiring = false
        autoStopTask?.cancel(); autoStopTask = nil
        alarmPlayer?.stop(); alarmPlayer = nil
        recogTask?.cancel(); recogTask = nil
        request?.endAudio(); request = nil

        if stopSystemAlarm, let id = firingAlarmID {
            // ⚠️ This is the bridge that was missing: a wake-word match only silenced our own player
            // and left the AlarmKit alarm (the black banner) ringing — so the child had to open the
            // app for AlarmRingView to stop it. Now we stop the system alarm directly and stamp the
            // same suppression HomeView honours, so opening the app later doesn't re-pop the ring.
            Task { try? await AlarmKitService.shared.stop(id: id) }
            let d = UserDefaults.standard
            d.removeObject(forKey: "pendingAlarmKitAlarmID")
            d.set(id.uuidString, forKey: "dismissedAlarmID")
            d.set(Date().timeIntervalSince1970, forKey: "dismissedAlarmAt")
            print("🟠 BGListen: stopped AlarmKit alarm \(id.uuidString.prefix(8)) + suppressed routing")
        }
        firingAlarmID = nil
        firingStrict = false
        // Engine + session stay alive for the next alarm.
    }

    private func playAlarmSound(_ a: AlarmSnapshot) {
        let fm = FileManager.default
        var url: URL?
        if !a.recordingName.isEmpty {
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let m4a = docs.appendingPathComponent("Recordings/\(a.recordingName).m4a")
            if fm.fileExists(atPath: m4a.path) { url = m4a }
        }
        if url == nil {
            let name = a.soundFileName.isEmpty ? "sunny_wake.caf" : a.soundFileName
            url = Bundle.main.url(forResource: name, withExtension: nil)
                ?? Bundle.main.url(forResource: "sunny_wake.caf", withExtension: nil)
        }
        guard let u = url else { print("🟠 BGListen: no sound file to play"); return }
        do {
            let p = try AVAudioPlayer(contentsOf: u)
            p.numberOfLoops = -1   // loop until stopped (background, no gap needed)
            p.prepareToPlay()
            p.play()
            alarmPlayer = p
            print("🟠 BGListen: playing \(u.lastPathComponent)")
        } catch {
            print("🟠 BGListen: alarm player failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Wake-word recognition

    private func startRecognition() {
        guard let recognizer, recognizer.isAvailable else {
            print("🟠 BGListen: recognizer unavailable")
            return
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true   // 100% offline
        req.shouldReportPartialResults = true
        request = req
        recogTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.isFiring else { return }
                if let error {
                    // On-device recognition tops out around a minute — just restart while ringing.
                    print("🟠 BGListen: recognition error — \(error.localizedDescription) → restart")
                    self.restartRecognition()
                    return
                }
                guard let text = result?.bestTranscription.formattedString, !text.isEmpty else { return }
                // DIAGNOSTIC: proves the mic is actually delivering audio while firing. If this NEVER
                // prints during an AlarmKit black banner but DOES print in-app, the session is seized.
                print("🟠 BGListen: heard → \"\(text)\"")
                if self.keywords.contains(where: { text.contains($0) }) {
                    if self.firingStrict {
                        // 貪睡(strict): child must complete the task in-app — don't voice-stop here.
                        print("🟠 BGListen: MATCHED but alarm is STRICT(貪睡) — ignoring; child must open app")
                    } else {
                        print("🟠 BGListen: MATCHED wake word in background → stopping AlarmKit alarm")
                        self.stopFiring(reason: "voice match", stopSystemAlarm: true)
                    }
                }
            }
        }
    }

    private func restartRecognition() {
        guard isFiring else { return }
        recogTask?.cancel(); recogTask = nil
        request?.endAudio(); request = nil
        startRecognition()
    }
}

// MARK: - Lock-screen sound export

/// Converts a recorded `.m4a` into a `Library/Sounds/*.caf` so AlarmKit (and the
/// UNNotification fallback) can ring the parent's custom recording on the **lock screen**.
///
/// Why this is needed: AlarmKit `sound: .named(_)` and `UNNotificationSound(named:)` only
/// read `.caf/.aiff/.wav` from the app bundle or `Library/Sounds/` — never an `.m4a` in
/// `Documents/Recordings/`. Without this export the device rings the bundled default tone
/// until the user opens the app; only then does AVAudioPlayer play the custom recording.
enum AlarmSoundExporter {

    /// Export `Recordings/<name>.m4a` → `Library/Sounds/alarm_<name>_<epoch>.caf`.
    /// - Returns: the CAF filename to store in `Alarm.soundFileName`, or nil on failure.
    static func exportLockScreenCAF(fromRecordingNamed name: String) -> String? {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let m4a = docs.appendingPathComponent("Recordings/\(name).m4a")
        guard fm.fileExists(atPath: m4a.path) else {
            print("🎚️ Exporter: SOURCE m4a MISSING at \(m4a.path) — abort")
            return nil
        }
        let m4aSize = (try? fm.attributesOfItem(atPath: m4a.path)[.size] as? Int) ?? nil
        print("🎚️ Exporter: source m4a ok (\(m4aSize ?? -1) bytes) name=\(name)")

        // Library/Sounds is the ONLY container directory iOS reads custom alarm/notification
        // sounds from. Create it if this is the first custom recording.
        let soundsDir = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
        try? fm.createDirectory(at: soundsDir, withIntermediateDirectories: true)

        // Unique filename per export: the system sound server caches CAF by name for the app's
        // lifetime, so reusing one name would replay the OLD recording after a re-record.
        let cafName = "alarm_\(name)_\(Int(Date().timeIntervalSince1970)).caf"
        let cafURL = soundsDir.appendingPathComponent(cafName)

        do {
            let inFile = try AVAudioFile(forReading: m4a)
            let format = inFile.processingFormat
            print("🎚️ Exporter: read m4a — sampleRate=\(format.sampleRate) ch=\(format.channelCount) length=\(inFile.length) frames")

            // Cap at 30s — iOS REJECTS notification sounds longer than 30s (silently falls back to
            // the default tone). This is the #1 reason a custom banner sound "doesn't work".
            let maxFrames = AVAudioFramePosition(format.sampleRate * 30)
            let frames = min(inFile.length, maxFrames)
            guard frames > 0,
                  let buffer = AVAudioPCMBuffer(
                      pcmFormat: format,
                      frameCapacity: AVAudioFrameCount(frames)
                  ) else {
                print("🎚️ Exporter: buffer alloc failed (frames=\(frames)) — abort")
                return nil
            }
            try inFile.read(into: buffer, frameCount: AVAudioFrameCount(frames))

            // 16-bit linear PCM CAF — the format AlarmKit/UNNotification reliably accept.
            let outSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let outFile = try AVAudioFile(forWriting: cafURL, settings: outSettings)
            // 2026-06-13：不再 loop 成 29s。真機證實 iOS 會把「長的」自訂通知音整顆退成 ~2s 預設音，
            //   但「短的」（如 4.6s 原始錄音）照播完整。提醒模式改走「短 CAF＋堆疊多顆通知」鋪滿 ~30s
            //   （見 AlarmScheduler.scheduleGentleRepeatBurst），所以這裡只寫一輪原始錄音（已 cap ≤30s）。
            //   AlarmKit 模式系統本來就會自己無限 loop，短 CAF 同樣 OK。
            //   ⚠️ 家長若錄超長（超過 iOS 的自訂音截斷點），單顆通知音仍可能被 iOS 截短；多數叫醒語很短，
            //      且「響滿 30s」交給堆疊負責，故此處不再人工補長（補長只會重蹈 29s→2s 之雷）。
            try outFile.write(from: buffer)
            print("🎚️ Exporter: wrote \(String(format: "%.1f", Double(buffer.frameLength) / format.sampleRate))s recording (no loop) → short CAF")
        } catch {
            print("🎚️ Exporter: m4a→caf export FAILED — \(error.localizedDescription)")
            return nil
        }

        let cafSize = (try? fm.attributesOfItem(atPath: cafURL.path)[.size] as? Int) ?? nil
        print("🎚️ Exporter: wrote caf \(cafName) (\(cafSize ?? -1) bytes)")

        // Prune older CAFs for this same alarm so Library/Sounds doesn't accumulate.
        if let existing = try? fm.contentsOfDirectory(at: soundsDir, includingPropertiesForKeys: nil) {
            for f in existing
            where f.lastPathComponent.hasPrefix("alarm_\(name)_") && f.lastPathComponent != cafName {
                try? fm.removeItem(at: f)
            }
        }
        return cafName
    }

    /// iOS 對「長的」自訂通知音會在鎖屏/被殺時整顆悄悄退成 ~2s 預設音（真機實證：4.6s 播完整、~29s 掛）。
    /// 內建鈴聲（sunny_wake.caf 18s、leaf_rustle.caf 20s）若直接餵 UNNotificationSound 就會中這條雷。
    /// 安全長度上限（秒）— 取在已驗證安全的 4.6s 之下留 margin。改這裡前先用 scheduleCutoffProbe 量測真機上限。
    static let bundledSafeSeconds: Double = 4.5

    /// Export a bundled CAF (e.g. "sunny_wake.caf") → a SHORT `Library/Sounds/*.caf` safe for
    /// `UNNotificationSound`. Mirrors the recording path: trim to `bundledSafeSeconds`, then let
    /// `AlarmScheduler.scheduleGentleRepeatBurst` stack it to ~30s. The bundle assets never change at
    /// runtime, so the short export is content-stable → cached (reused if it already exists).
    /// - Returns: the short CAF filename in Library/Sounds, or nil on failure.
    static func exportBundledShortCAF(bundledName: String) -> String? {
        let fm = FileManager.default
        guard let src = Bundle.main.url(forResource: bundledName, withExtension: nil) else {
            print("🎚️ Exporter: bundled sound \(bundledName) NOT in bundle — abort")
            return nil
        }
        let soundsDir = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
        try? fm.createDirectory(at: soundsDir, withIntermediateDirectories: true)

        // Name encodes the bundle base + safe-length so a future bundledSafeSeconds change re-exports
        // (old length stays cached but unused). e.g. bundled_sunny_wake_45.caf
        let base = (bundledName as NSString).deletingPathExtension
        let shortName = "bundled_\(base)_\(Int(bundledSafeSeconds * 10)).caf"
        let shortURL = soundsDir.appendingPathComponent(shortName)
        if fm.fileExists(atPath: shortURL.path) {
            print("🎚️ Exporter: bundled short cache hit → \(shortName)")
            return shortName
        }

        do {
            let inFile = try AVAudioFile(forReading: src)
            let format = inFile.processingFormat
            let maxFrames = AVAudioFramePosition(format.sampleRate * bundledSafeSeconds)
            let frames = min(inFile.length, maxFrames)
            guard frames > 0,
                  let buffer = AVAudioPCMBuffer(
                      pcmFormat: format,
                      frameCapacity: AVAudioFrameCount(frames)
                  ) else {
                print("🎚️ Exporter: bundled buffer alloc failed (frames=\(frames)) — abort")
                return nil
            }
            try inFile.read(into: buffer, frameCount: AVAudioFrameCount(frames))

            // 16-bit linear PCM CAF — the format UNNotificationSound reliably accepts (same as recordings).
            let outSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let outFile = try AVAudioFile(forWriting: shortURL, settings: outSettings)
            try outFile.write(from: buffer)
            print("🎚️ Exporter: bundled \(bundledName) → short \(shortName) (\(String(format: "%.1f", Double(buffer.frameLength) / format.sampleRate))s)")
        } catch {
            print("🎚️ Exporter: bundled short export FAILED — \(error.localizedDescription)")
            return nil
        }
        return shortName
    }

    #if DEBUG
    /// 🔬 暫時：合成「每秒一聲嗶」的尺規音（mono 16-bit PCM 44100，與正式通知音同格式），
    /// 長度 = seconds（cap ≤29，因 >30 會被 iOS 整顆退預設）。5 的倍數那聲用高音、較長，方便數。
    /// 用途：殺 App+關屏下逐顆聽，找出 iOS「完整播放自訂通知音」的真實上限。測完整個 #if DEBUG 可刪。
    static func makeProbeBeepCAF(seconds: Int) -> String? {
        let fm = FileManager.default
        let soundsDir = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
        try? fm.createDirectory(at: soundsDir, withIntermediateDirectories: true)

        let sr = 44100.0
        let dur = min(max(seconds, 1), 29)
        let totalFrames = AVAudioFrameCount(sr * Double(dur) + sr * 0.3)   // +margin 給最後一聲
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sr, channels: 1, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: totalFrames),
              let ch = buf.floatChannelData else { return nil }
        buf.frameLength = totalFrames
        let p = ch[0]
        memset(p, 0, Int(totalFrames) * MemoryLayout<Float>.size)
        for k in 1...dur {
            let emph = (k % 5 == 0)
            let freq = emph ? 1568.0 : 784.0
            let beepLen = Int(sr * (emph ? 0.22 : 0.10))
            let start = Int(Double(k) * sr)
            for i in 0..<beepLen {
                let idx = start + i
                if idx >= Int(totalFrames) { break }
                let env = sin(Double.pi * Double(i) / Double(beepLen))   // 0→1→0 包絡避免爆音
                p[idx] = Float(0.5 * env * sin(2.0 * Double.pi * freq * Double(i) / sr))
            }
        }

        let outSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sr,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let cafName = "debug_probe_\(dur)s_\(Int(Date().timeIntervalSince1970)).caf"
        let cafURL = soundsDir.appendingPathComponent(cafName)
        do {
            let outFile = try AVAudioFile(forWriting: cafURL, settings: outSettings)
            try outFile.write(from: buf)
        } catch {
            print("🔬 Probe: make \(dur)s CAF failed — \(error.localizedDescription)")
            return nil
        }
        print("🔬 Probe: wrote \(dur)s beep ruler → \(cafName)")
        return cafName
    }
    #endif
}
