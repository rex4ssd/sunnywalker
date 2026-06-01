// SunnyWalker — AlarmRingView.swift  |  Day 12  |  listening feedback UI + fallback button polish

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

    // Day 12: listening feedback state
    @State private var isListening = false
    @State private var showRetryMessage = false
    @State private var micPulse = false
    @State private var fallbackButtonEnabled = false

    private var scene: DaytimeScene {
        DaytimeScene.current(hour: Calendar.current.component(.hour, from: Date()))
    }

    /// Attempt label (1-indexed): shows which cycle the child is on while listening.
    var attemptLabel: String {
        "第 \(min(recognitionFailureCount + 1, 3))/3 次，說「我起床了」！"
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
                    .padding(.bottom, 24)

                // Listening feedback zone — hidden once fallback button appears
                if !showFallbackButton {
                    ZStack {
                        if isListening {
                            VStack(spacing: 10) {
                                // Pulsing mic
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(GhibliColors.lanternOrange)
                                    .scaleEffect(micPulse ? 1.25 : 0.85)
                                    .animation(
                                        .easeInOut(duration: 0.65).repeatForever(autoreverses: true),
                                        value: micPulse
                                    )

                                // Attempt counter
                                Text(attemptLabel)
                                    .font(GhibliFonts.body())
                                    .foregroundStyle(scene.clockTextColor)
                            }
                            .transition(.opacity)
                        } else if showRetryMessage {
                            Text("沒關係，再試一次！")
                                .font(GhibliFonts.body())
                                .foregroundStyle(GhibliColors.leafFresh)
                                .transition(.opacity)
                        }
                    }
                    .frame(height: 88)
                    .animation(.easeInOut(duration: 0.3), value: isListening)
                    .animation(.easeInOut(duration: 0.3), value: showRetryMessage)
                }

                Spacer()

                if showFallbackButton {
                    // Explanation caption above fallback button
                    Text("說不出來嗎？")
                        .font(GhibliFonts.caption())
                        .foregroundStyle(scene.clockTextColor.opacity(0.75))
                        .padding(.bottom, 8)
                        .transition(.opacity)

                    GhibliButton("按這裡起床 🌟", color: GhibliColors.leafFresh) {
                        handleWakeUp()
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 16)
                    .disabled(!fallbackButtonEnabled)   // 0.5s tap-through guard
                    .transition(.scale.combined(with: .opacity))
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

    // MARK: - Speech cycle

    private func startSpeechCycle() {
        guard !showingReward, !showFallbackButton else { return }
        isListening = true
        micPulse = true
        do {
            try speechRecognizer.startListening(onMatch: { keyword in
                print("SpeechRecognizer: matched '\(keyword)' — triggering wake-up")
                isListening = false
                micPulse = false
                handleWakeUp()
            }, onFailure: {
                isListening = false
                micPulse = false
                handleRecognitionFailure()
            })
        } catch {
            print("SpeechRecognizer: failed to start — \(error.localizedDescription)")
            isListening = false
            micPulse = false
            handleRecognitionFailure()
        }
    }

    private func handleRecognitionFailure() {
        recognitionFailureCount += 1
        if recognitionFailureCount >= 3 {
            withAnimation {
                showFallbackButton = true
            }
            // Enable button after 0.5s — prevents accidental tap-through on appearance
            speechTask = Task {
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
                fallbackButtonEnabled = true
            }
        } else {
            // Show "沒關係，再試一次！" for 1.5s, then restart
            showRetryMessage = true
            speechTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                showRetryMessage = false
                try? await Task.sleep(for: .seconds(0.3))
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

    // MARK: - Audio

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
