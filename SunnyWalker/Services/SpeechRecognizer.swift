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

    private let keywords = ["我起床了", "好的", "知道了", "起床囉"]

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
    }

    func startListening(onMatch: @escaping (String) -> Void) throws {
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "SpeechRecognizer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "語音辨識器不可用"])
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw NSError(domain: "SpeechRecognizer", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "此裝置不支援離線辨識"])
        }

        recognizedText = ""
        matchedKeyword = nil

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.requiresOnDeviceRecognition = true  // 100% offline — never remove
        request?.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        task = recognizer.recognitionTask(with: request!) { [weak self] result, error in
            guard let self else { return }
            if let error {
                print("SpeechRecognizer: recognition error — \(error.localizedDescription)")
                self.stop()
                return
            }
            guard let text = result?.bestTranscription.formattedString else { return }
            self.recognizedText = text

            if let hit = self.keywords.first(where: { text.contains($0) }) {
                self.matchedKeyword = hit
                onMatch(hit)
                self.stop()
            }
        }
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
