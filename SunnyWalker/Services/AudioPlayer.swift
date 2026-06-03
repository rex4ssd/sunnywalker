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

        // ⚠️ Configure the shared audio session ONCE here — never in the per-loop restart.
        // The old code re-set .playback + setActive(true) inside startOnce on EVERY loop, which
        // clobbered the .playAndRecord session SpeechRecognizer installs → the mic was silently
        // torn down the instant the recording looped, so voice-stop stopped working a few seconds
        // in. The loop now only re-creates the AVAudioPlayer and never touches the session, so the
        // .playback → .playAndRecord transition (when speech starts) happens once and sticks.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            print("🔊 AudioPlayer.play: session=.playback active, url=\(url.lastPathComponent) loop=\(loop) gap=\(gapSeconds)s")
        } catch {
            print("🔊 AudioPlayer.play: session setup FAILED — \(error.localizedDescription)")
        }
        startOnce(url: url)
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
