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
        recorder?.record()
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
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isActive = false
        print("🟠 BGListen: stopped — mic released")
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
        print("🟠 BGListen: FIRING \(a.id.uuidString.prefix(8)) in background — play sound + listen")
        playAlarmSound(a)
        startRecognition()
        let minutes = max(1, min(10, AppSettings.shared.alarmRingDurationMinutes))
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(minutes * 60)))
            guard !Task.isCancelled else { return }
            self?.stopFiring(reason: "ring-duration timeout")
        }
    }

    private func stopFiring(reason: String) {
        guard isFiring else { return }
        print("🟠 BGListen: stop firing (\(reason))")
        isFiring = false
        autoStopTask?.cancel(); autoStopTask = nil
        alarmPlayer?.stop(); alarmPlayer = nil
        recogTask?.cancel(); recogTask = nil
        request?.endAudio(); request = nil
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
                if error != nil {
                    // On-device recognition tops out around a minute — just restart while ringing.
                    self.restartRecognition()
                    return
                }
                guard let text = result?.bestTranscription.formattedString else { return }
                if self.keywords.contains(where: { text.contains($0) }) {
                    print("🟠 BGListen: MATCHED wake word in background → stopping alarm")
                    self.stopFiring(reason: "voice match")
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
            try outFile.write(from: buffer)
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
}
