// SunnyWalker — AudioPlayer.swift  |  Day 9 → Day 30  |  gap loop + volume ducking

import AVFoundation
import Foundation

@MainActor
final class AudioPlayer: NSObject, ObservableObject {
    private var player: AVAudioPlayer?
    private var currentURL: URL?
    private var looping = false
    private var gapSeconds = 0        // injected by caller; no AppSettings dependency
    private var loopTask: Task<Void, Never>?
    private var currentVolume: Float = 1.0   // preserved across loop restarts so a duck survives
    private var interruptionObserver: NSObjectProtocol?
    @Published var isPlaying = false

    // MARK: - Public API

    /// Play audio from `url`.
    /// When `loop` is true the file repeats indefinitely with `gapSeconds` seconds of
    /// silence between each play — giving the child a window to speak.
    /// `gapSeconds` is injected by the caller (AlarmRingView reads AppSettings).
    func play(url: URL, loop: Bool = true, gapSeconds: Int = 0) {
        stop()
        currentURL      = url
        looping         = loop
        self.gapSeconds = gapSeconds
        currentVolume   = 1.0
        registerInterruptionObserver()
        activateSessionAndStart(url: url, attempt: 0)
    }

    // MARK: - Interruption recovery (Issue #2)

    /// ★ Issue #2 根因之二：關屏 / AlarmKit / 其他音訊都會對我們的 session 送出 interruption。
    /// .began 時系統會把 AVAudioPlayer 暫停；若沒人在 .ended 時把它救回來，鬧鐘就「關屏後沒聲、
    /// 之後一直沒聲」。原本 AudioPlayer 完全沒處理中斷 → 一次中斷就永久靜音。
    /// 這裡在 .ended（且系統建議 shouldResume，或我們仍處於 looping 響鈴狀態）時重啟播放。
    private func registerInterruptionObserver() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo,
                  let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor [weak self] in
                self?.handleInterruption(type, info: info)
            }
        }
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType, info: [AnyHashable: Any]) {
        switch type {
        case .began:
            print("🔊 AudioPlayer.interruption BEGAN — player paused by system (looping=\(looping))")
        case .ended:
            // 仍在響鈴（looping 且有 currentURL）就一定要救回來，不只看 shouldResume flag。
            var shouldResume = false
            if let optRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                shouldResume = AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume)
            }
            print("🔊 AudioPlayer.interruption ENDED — shouldResume=\(shouldResume) looping=\(looping)")
            guard looping, let url = currentURL else { return }
            // 先取消可能還在 gap sleep 的 loopTask，避免它稍後又 startOnce 造成雙重播放。
            loopTask?.cancel()
            loopTask = nil
            // 重新拿 session 再重啟一輪播放（startOnce 的 delegate 會接力 loop）。
            activateSessionAndStart(url: url, attempt: 0)
        @unknown default:
            break
        }
    }

    /// Configure the .playback session and start playing — with retry.
    /// ⚠️ Why retry: when the in-app alarm screen opens from a foreground AlarmKit alarm,
    /// HomeView.checkForegroundAlarm stops the AlarmKit alarm and immediately calls play(). AlarmKit
    /// releases its audio session ASYNCHRONOUSLY, so the first setActive(true) loses the race and
    /// throws "Session activation failed" (status 560557684) → the ring would play for ~0 s and go
    /// silent (only the visual prompt remains). Retrying ~every 0.3 s grabs the session the instant
    /// AlarmKit lets go, so the ring keeps sounding.
    /// We configure the session ONCE (not per loop): the per-loop restart in startOnce never touches
    /// the session, so SpeechRecognizer's later switch to .playAndRecord (for "我起床了") sticks.
    private func activateSessionAndStart(url: URL, attempt: Int) {
        guard currentURL == url else { return }   // a newer play()/stop() superseded this request
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            print("🔊 AudioPlayer.play: session=.playback active (attempt \(attempt)), url=\(url.lastPathComponent) loop=\(looping) gap=\(gapSeconds)s")
            startOnce(url: url)
        } catch {
            print("🔊 AudioPlayer.play: session activation FAILED (attempt \(attempt)) — \(error.localizedDescription)")
            if attempt < 8 {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    self?.activateSessionAndStart(url: url, attempt: attempt + 1)
                }
            } else {
                // Last resort: try to play anyway — the session is often usable even when activation
                // reported an error, and a silent alarm is worse than a best-effort one.
                print("🔊 AudioPlayer.play: activation still failing after \(attempt) tries — playing anyway")
                startOnce(url: url)
            }
        }
    }

    /// Duck volume to `fraction` (0–1) while speech recognition listens.
    func duck(to fraction: Float = 0.15) {
        currentVolume = fraction
        player?.volume = fraction
        print("🔊 AudioPlayer.duck → \(fraction)")
    }

    /// Restore full volume after speech recognition ends.
    func unduck() {
        currentVolume = 1.0
        player?.volume = 1.0
        print("🔊 AudioPlayer.unduck → 1.0")
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        player?.stop()
        player = nil
        looping = false
        currentURL = nil
        isPlaying = false
        if let obs = interruptionObserver {
            NotificationCenter.default.removeObserver(obs)
            interruptionObserver = nil
        }
    }

    // MARK: - Internal

    /// Create + start one playthrough. Deliberately does NOT touch AVAudioSession — the session
    /// is owned by play() (first start) and by SpeechRecognizer (which switches to .playAndRecord).
    private func startOnce(url: URL) {
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = 0          // play once; delegate restarts after the gap
            p.volume = currentVolume     // preserve duck state across loop restarts
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            isPlaying = true
        } catch {
            print("🔊 AudioPlayer.startOnce: playback FAILED — \(error.localizedDescription)")
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            guard self.looping, let url = self.currentURL else { return }

            let gap = self.gapSeconds   // read from stored value, no external dependency
            self.loopTask = Task {
                if gap > 0 {
                    try? await Task.sleep(for: .seconds(Double(gap)))
                }
                guard !Task.isCancelled, self.looping else { return }
                self.startOnce(url: url)
            }
        }
    }
}
