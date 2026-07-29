// SunnyWalker — AudioRecorder.swift  |  Day 5  |  AVAudioRecorder wrapper (spec §4 stage 2)

import AVFoundation
import Speech
import Foundation
import UIKit

@MainActor
final class AudioRecorder: ObservableObject {
    private var recorder: AVAudioRecorder?
    @Published var isRecording = false
    @Published var currentURL: URL?

    /// 每段自定錄音的長度上限（秒）。免費版 3 分鐘、Pro 無限——統一從 FeatureLimits 取。
    /// 用 record(forDuration:) 當硬上限：即使 App 被切背景、UI 計時器沒跑到，檔案長度也一定被截斷。
    /// RecordingView 另有一個同步 UI 計時器負責收尾（存檔名、匯出）。Pro（.infinity）時不設上限。
    static var maxRecordingSeconds: TimeInterval { FeatureLimits.maxAlarmRecordingSeconds }

    func start(named name: String) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings/\(name).m4a")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        recorder = try AVAudioRecorder(url: url, settings: settings)
        let cap = Self.maxRecordingSeconds
        if cap.isFinite {
            recorder?.record(forDuration: cap)   // 免費版硬上限：到時自動停
        } else {
            recorder?.record()                   // Pro：不設長度上限
        }
        currentURL = url
        isRecording = true
    }

    func stop() {
        recorder?.stop()
        isRecording = false
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
    /// runtime, so the newest existing export is reused; pass `regenerate: true`（升級自癒）to force a
    /// fresh epoch filename — 系統 sound server 以「檔名」快取聲音，且這份快取撐得過 app 更新
    /// （container 換 UUID 路徑後，舊檔名仍映射到舊路徑 → 鎖屏退成預設「咚」聲），換名才繞得過。
    /// - Returns: the short CAF filename in Library/Sounds, or nil on failure.
    static func exportBundledShortCAF(bundledName: String, regenerate: Bool = false) -> String? {
        let fm = FileManager.default
        guard let src = Bundle.main.url(forResource: bundledName, withExtension: nil) else {
            print("🎚️ Exporter: bundled sound \(bundledName) NOT in bundle — abort")
            return nil
        }
        let soundsDir = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
        try? fm.createDirectory(at: soundsDir, withIntermediateDirectories: true)

        // Name encodes bundle base + safe-length（改 bundledSafeSeconds 會自動重匯）+ export epoch。
        // e.g. bundled_sunny_wake_45_1753772400.caf（2026-07 以前的舊檔名無 epoch，不會被當 cache）。
        let base = (bundledName as NSString).deletingPathExtension
        let prefix = "bundled_\(base)_\(Int(bundledSafeSeconds * 10))_"
        if !regenerate,
           let cached = ((try? fm.contentsOfDirectory(atPath: soundsDir.path)) ?? [])
               .filter({ $0.hasPrefix(prefix) }).sorted().last {
            print("🎚️ Exporter: bundled short cache hit → \(cached)")
            return cached
        }
        let shortName = "\(prefix)\(Int(Date().timeIntervalSince1970)).caf"
        let shortURL = soundsDir.appendingPathComponent(shortName)

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
        // Prune older exports of this bundled sound（含無 epoch 的舊格式檔名）so Library/Sounds
        // doesn't accumulate — same policy as the recording exporter above.
        if let existing = try? fm.contentsOfDirectory(at: soundsDir, includingPropertiesForKeys: nil) {
            for f in existing
            where f.lastPathComponent.hasPrefix("bundled_\(base)_") && f.lastPathComponent != shortName {
                try? fm.removeItem(at: f)
            }
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
