// SunnyWalker — AlarmRingView.swift  |  Day 27  |  Accessibility + reduceMotion

import SwiftUI
import SwiftData

struct AlarmRingView: View {
    var alarm: Alarm? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var audioPlayer = AudioPlayer()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var wiggle = false
    @State private var showingReward = false
    @State private var speechTask: Task<Void, Never>?
    @State private var recognitionFailureCount = 0
    @State private var showFallbackButton = false

    // Wake timestamp — set when view appears, used for WakeRecord response time
    @State private var firedAt = Date()

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
                    .rotationEffect(.degrees(reduceMotion ? 0 : (wiggle ? 10 : -10)), anchor: .bottom)
                    .animation(
                        reduceMotion ? .none : .easeInOut(duration: 0.35).repeatForever(autoreverses: true),
                        value: wiggle
                    )
                    .padding(.bottom, 32)

                Text("該起床囉！☀️")
                    .font(GhibliFonts.title(28))
                    .foregroundStyle(scene.clockTextColor)
                    .padding(.bottom, 24)

                // Listening feedback zone — only for .voice mode, hidden once fallback appears
                if !showFallbackButton && alarm?.effectiveTaskType != .button {
                    ZStack {
                        if isListening {
                            VStack(spacing: 10) {
                                // Pulsing mic
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(GhibliColors.lanternOrange)
                                    .scaleEffect(reduceMotion ? 1.0 : (micPulse ? 1.25 : 0.85))
                                    .animation(
                                        reduceMotion ? .none : .easeInOut(duration: 0.65).repeatForever(autoreverses: true),
                                        value: micPulse
                                    )
                                    .accessibilityLabel("正在聆聽")

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
                    // .voice failure: show "說不出來嗎？" hint + secondary color
                    // .button mode: show primary "我起床了！" directly (no hint needed)
                    if alarm?.effectiveTaskType != .button {
                        Text("說不出來嗎？")
                            .font(GhibliFonts.caption())
                            .foregroundStyle(scene.clockTextColor.opacity(0.75))
                            .padding(.bottom, 8)
                            .transition(.opacity)
                    }

                    let isButtonMode = alarm?.effectiveTaskType == .button
                    GhibliButton(
                        isButtonMode ? "我起床了！" : "按這裡起床 🌟",
                        color: isButtonMode ? GhibliColors.lanternOrange : GhibliColors.leafFresh
                    ) {
                        handleWakeUp(dismissMethod: isButtonMode ? "button" : "fallback")
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 16)
                    .disabled(!fallbackButtonEnabled)
                    .transition(.scale.combined(with: .opacity))
                }

                GhibliButton("我起床了！", color: GhibliColors.lanternOrange) {
                    handleWakeUp(dismissMethod: "voice")
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 56)
            }
            .animation(.easeInOut(duration: 0.4), value: showFallbackButton)
        }
        .onAppear {
            firedAt = Date()   // record alarm fire time for WakeRecord
            wiggle = true
            startAudio()
            // .button taskType: skip speech — child taps to dismiss immediately
            if alarm?.effectiveTaskType == .button {
                showFallbackButton = true
                fallbackButtonEnabled = true
            } else {
                // .voice (default) + future .math: start speech after 5s warm-up
                speechTask = Task {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    startSpeechCycle()
                }
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
                handleWakeUp(dismissMethod: "voice")
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

    private func handleWakeUp(dismissMethod: String = "voice") {
        speechTask?.cancel()
        audioPlayer.stop()
        speechRecognizer.stop()
        // Log wake record for parent history
        if let alarm {
            let record = WakeRecord(
                alarmID: alarm.id,
                alarmLabel: alarm.label,
                firedAt: firedAt,
                wokeAt: Date(),
                dismissMethod: dismissMethod
            )
            modelContext.insert(record)
        }
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
