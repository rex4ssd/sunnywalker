// SunnyWalker — AudioPlayer.swift  |  Day 4  |  AVAudioPlayer wrapper

import AVFoundation
import Foundation

@MainActor
final class AudioPlayer: NSObject, ObservableObject {
    private var player: AVAudioPlayer?
    @Published var isPlaying = false

    func play(url: URL, loop: Bool = true) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = loop ? -1 : 0
            player?.prepareToPlay()
            player?.play()
            isPlaying = true
        } catch {
            print("AudioPlayer: failed to play \(url.lastPathComponent) — \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }
}
