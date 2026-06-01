// SunnyWalker — AlarmRingView.swift  |  Day 10  |  voice fallback button after 3 failed recognition cycles

import SwiftUI

struct AlarmRingView: View {
    var alarm: Alarm? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioPlayer = AudioPlayer()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var wiggle = false
    @State private var showingReward = false
    @State private var speechTask: Task<Void, Never>?
    @State private var recognitionFailureCount = 0
    @State private var showFallbackButton = false

    private var scene: DaytimeScene {
        DaytimeScene.current(hour: Calendar.current.component(.hour, from: Date()))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scene.gradientColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            CloudBackground()

            VStack(spacing: 0) {
                Spacer()

                TotoroAvatar()
                    .rotationEffect(.degrees(wiggle ? 10 : -10), anchor: .bottom)
                    .animation(
                        .easeInOut(duration: 0.35).repeatForever(autoreverses: true),
                        value: wiggle
                    )
                    .padding(.bottom, 32)

                Text("該起床囉！☀️")
                    .font(GhibliFonts.title(28))
                    .foregroundStyle(scene.clockTextColor)
                    .padding(.bottom, 56)

                Spacer()

                if showFallbackButton {
                    GhibliButton("按這裡起床 🌟", color: GhibliColors.leafFresh) {
                        handleWakeUp()
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .scale))
                }

                GhibliButton("我起床了！", color: GhibliColors.lanternOrange) {
                    handleWakeUp()
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 56)
            }
            .animation(.easeInOut(duration: 0.4), value: showFallbackButton)
        }
        .onAppear {
            wiggle = true
            startAudio()
            speechTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                startSpeechCycle()
            }
        }
        .onDisappear {
            speechTask?.cancel()
            audioPlayer.stop()
            speechRecognizer.stop()
        }
        .fullScreenCover(isPresented: $showingReward, onDismiss: { dismiss() }) {
            RewardView()
        }
    }

    private func startSpeechCycle() {
        guard !showingReward, !showFallbackButton else { return }
        do {
            try speechRecognizer.startListening(onMatch: { keyword in
                print("SpeechRecognizer: matched '\(keyword)' — triggering wake-up")
                handleWakeUp()
            }, onFailure: {
                handleRecognitionFailure()
            })
        } catch {
            print("SpeechRecognizer: failed to start — \(error.localizedDescription)")
            handleRecognitionFailure()
        }
    }

    private func handleRecognitionFailure() {
        recognitionFailureCount += 1
        if recognitionFailureCount >= 3 {
            showFallbackButton = true
        } else {
            speechTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                startSpeechCycle()
            }
        }
    }

    private func handleWakeUp() {
        speechTask?.cancel()
        audioPlayer.stop()
        speechRecognizer.stop()
        showingReward = true
    }

    private func startAudio() {
        let recordingName = alarm?.recordingName ?? ""
        if !recordingName.isEmpty {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = docs.appendingPathComponent("Recordings/\(recordingName).m4a")
            if FileManager.default.fileExists(atPath: url.path) {
                audioPlayer.play(url: url)
                return
            }
        }

        let soundName = alarm?.soundFileName ?? "totoro_breath.caf"
        if let bundleURL = Bundle.main.url(forResource: soundName, withExtension: nil) {
            audioPlayer.play(url: bundleURL)
        } else {
            print("AudioPlayer: no recording — skipping playback")
        }
    }
}

#Preview {
    AlarmRingView()
}
