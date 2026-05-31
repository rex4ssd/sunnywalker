// SunnyWalker — AudioRecorder.swift  |  Day 5  |  AVAudioRecorder wrapper (spec §4 stage 2)

import AVFoundation
import Foundation

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
