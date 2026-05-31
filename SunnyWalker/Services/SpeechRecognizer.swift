// SunnyWalker — SpeechRecognizer.swift  |  Day 4  |  stub (Day 5 wires full on-device recognition)
// Real implementation: SFSpeechRecognizer + AVAudioEngine, requiresOnDeviceRecognition = true.

import Speech
import Foundation

@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var recognizedText = ""
    @Published var matchedKeyword: String?

    func startListening(onMatch: @escaping (String) -> Void) {
        recognizedText = ""
        matchedKeyword = nil
        print("SpeechRecognizer: listening... (stub — full on-device recognition wired in Day 5)")
    }

    func stop() {
        print("SpeechRecognizer: stopped")
    }
}
