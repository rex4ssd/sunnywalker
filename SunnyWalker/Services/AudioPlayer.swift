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
        activateSessionAndStart(url: url, attempt: 0)
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
