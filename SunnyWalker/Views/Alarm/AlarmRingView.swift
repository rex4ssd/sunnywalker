// SunnyWalker — AlarmRingView.swift  |  Day 27  |  Accessibility + reduceMotion

import SwiftUI
import SwiftData
import UIKit

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
    @State private var ringTimeoutTask: Task<Void, Never>?
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
        L("attempt_counter %lld", min(recognitionFailureCount + 1, 3))
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

                MascotView()
                    .rotationEffect(.degrees(reduceMotion ? 0 : (wiggle ? 10 : -10)), anchor: .bottom)
                    .animation(
                        reduceMotion ? .none : .easeInOut(duration: 0.35).repeatForever(autoreverses: true),
                        value: wiggle
                    )
                    .padding(.bottom, 32)

                Text("該起床囉！☀️")
                    .font(SunnyFonts.title(28))
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
                                    .foregroundStyle(SunnyColors.lanternOrange)
                                    .scaleEffect(reduceMotion ? 1.0 : (micPulse ? 1.25 : 0.85))
                                    .animation(
                                        reduceMotion ? .none : .easeInOut(duration: 0.65).repeatForever(autoreverses: true),
                                        value: micPulse
                                    )
                                    .accessibilityLabel("正在聆聽")

                                // Attempt counter
                                Text(attemptLabel)
                                    .font(SunnyFonts.body())
                                    .foregroundStyle(scene.clockTextColor)
                            }
                            .transition(.opacity)
                        } else if showRetryMessage {
                            Text("沒關係，再試一次！")
                                .font(SunnyFonts.body())
                                .foregroundStyle(SunnyColors.leafFresh)
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
                            .font(SunnyFonts.caption())
                            .foregroundStyle(scene.clockTextColor.opacity(0.75))
                            .padding(.bottom, 8)
                            .transition(.opacity)
                    }

                    let isButtonMode = alarm?.effectiveTaskType == .button
                    SunnyButton(
                        isButtonMode ? "我起床了！" : "按這裡起床 🌟",
                        color: isButtonMode ? SunnyColors.lanternOrange : SunnyColors.leafFresh
                    ) {
                        handleWakeUp(dismissMethod: isButtonMode ? "button" : "fallback")
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 16)
                    .disabled(!fallbackButtonEnabled)
                    .transition(.scale.combined(with: .opacity))
                }

                SunnyButton("我起床了！", color: SunnyColors.lanternOrange) {
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
            // App is now open for this alarm → stop the strict-mode "貪睡模式" nag notifications.
            if let alarm { AlarmScheduler.shared.cancelNags(alarm.id) }
            // Keep the screen awake while the alarm is actively ringing.
            UIApplication.shared.isIdleTimerDisabled = true
            startAudio()
            startRingTimeout()
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
            ringTimeoutTask?.cancel()
            audioPlayer.stop()
            speechRecognizer.stop()
            // Let the device auto-lock / sleep again once the alarm screen is gone.
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .fullScreenCover(isPresented: $showingReward, onDismiss: { dismiss() }) {
            RewardView()
        }
    }

    // MARK: - Speech cycle

    private func startSpeechCycle() {
        guard !showingReward, !showFallbackButton else { return }
        print("🎤 AlarmRingView.startSpeechCycle: attempt #\(recognitionFailureCount + 1) — ducking + start listening")
        isListening = true
        micPulse = true
        // Duck the recording so the child can speak without shouting over it.
        audioPlayer.duck(to: 0.12)
        do {
            try speechRecognizer.startListening(onMatch: { keyword in
                print("🎤 AlarmRingView: MATCHED '\(keyword)' — waking up")
                self.isListening = false
                self.micPulse = false
                self.audioPlayer.unduck()
                self.handleWakeUp(dismissMethod: "voice")
            }, onFailure: {
                print("🎤 AlarmRingView: speech onFailure (no match / timeout)")
                self.isListening = false
                self.micPulse = false
                self.audioPlayer.unduck()
                self.handleRecognitionFailure()
            })
        } catch {
            print("🎤 AlarmRingView.startSpeechCycle: startListening THREW — \(error.localizedDescription)")
            isListening = false
            micPulse = false
            audioPlayer.unduck()
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

    // MARK: - Ring duration auto-stop

    /// After the parent-configured ring duration, give up waking the child, silence everything,
    /// and let the screen sleep — so the battery doesn't drain if nobody's there.
    private func startRingTimeout() {
        let minutes = max(1, min(10, AppSettings.shared.alarmRingDurationMinutes))
        print("⏰ AlarmRingView: ring auto-stop in \(minutes) min")
        ringTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(Double(minutes * 60)))
            guard !Task.isCancelled else { return }
            handleAutoStop()
        }
    }

    private func handleAutoStop() {
        print("⏰ AlarmRingView: ring duration reached — gentle 'aww' then close")
        speechTask?.cancel()
        ringTimeoutTask?.cancel()
        speechRecognizer.stop()
        // 😞 Didn't manage to wake in time → play the gentle sad chime (replaces the alarm loop),
        // let it ring out, then release the screen and close.
        playEffectOnce("timeout_sad.wav")
        ringTimeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            audioPlayer.stop()
            UIApplication.shared.isIdleTimerDisabled = false
            dismiss()
        }
    }

    private func handleWakeUp(dismissMethod: String = "voice") {
        speechTask?.cancel()
        ringTimeoutTask?.cancel()
        speechRecognizer.stop()
        // 🎉 Success! Celebrate with the cheer chime (this also stops the looping alarm audio).
        playEffectOnce("success_cheer.wav")
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

    /// Play a one-shot sound effect (cheer / aww) through the alarm's AudioPlayer. Reusing the same
    /// player automatically stops the looping alarm audio first. If the file is somehow missing we
    /// still silence the alarm so it can't keep ringing after a success/timeout.
    private func playEffectOnce(_ resource: String) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: nil) else {
            print("🔊 AlarmRingView: effect \(resource) NOT FOUND in bundle — silencing alarm instead")
            audioPlayer.stop()
            return
        }
        print("🔊 AlarmRingView: playing effect \(resource)")
        audioPlayer.play(url: url, loop: false, gapSeconds: 0)
    }

    private func startAudio() {
        // Read gap from AppSettings here so AudioPlayer stays dependency-free.
        let gap = AppSettings.shared.recordingGapSeconds

        let recordingName = alarm?.recordingName ?? ""
        if !recordingName.isEmpty {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = docs.appendingPathComponent("Recordings/\(recordingName).m4a")
            if FileManager.default.fileExists(atPath: url.path) {
                print("🎬 AlarmRingView.startAudio: playing CUSTOM recording \(recordingName).m4a")
                audioPlayer.play(url: url, loop: true, gapSeconds: gap)
                return
            }
            print("🎬 AlarmRingView.startAudio: recording \(recordingName).m4a MISSING — falling back")
        }

        // The alarm's chosen sound CAF. Exported custom alarm sounds live in Library/Sounds
        // (that's where AlarmSoundExporter writes them for the notification path) — NOT the bundle.
        // startAudio used to only check the bundle, so a custom CAF was never found and the ring
        // screen fell through to "skipping playback" → SILENT wake screen (the child has no idea
        // the alarm went off). Check Library/Sounds first, then the bundle.
        let soundName = alarm?.soundFileName ?? ""
        if !soundName.isEmpty {
            let soundsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Sounds", isDirectory: true)
            let cafURL = soundsDir.appendingPathComponent(soundName)
            if FileManager.default.fileExists(atPath: cafURL.path) {
                print("🎬 AlarmRingView.startAudio: playing Library/Sounds \(soundName)")
                audioPlayer.play(url: cafURL, loop: true, gapSeconds: gap)
                return
            }
            if let bundleURL = Bundle.main.url(forResource: soundName, withExtension: nil) {
                print("🎬 AlarmRingView.startAudio: playing bundled \(soundName)")
                audioPlayer.play(url: bundleURL, loop: true, gapSeconds: gap)
                return
            }
            print("🎬 AlarmRingView.startAudio: \(soundName) not in Library/Sounds or bundle — using default tone")
        }

        // Guaranteed fallback: the bundled default alarm tone. NEVER leave the wake screen silent —
        // the child must hear the alarm. It loops with `gap` seconds of silence between plays, and
        // the speech cycle ducks it to 0.12 while listening, so "我起床了" recognition still works.
        if let defaultURL = Bundle.main.url(forResource: "sunny_wake.caf", withExtension: nil) {
            print("🎬 AlarmRingView.startAudio: playing DEFAULT sunny_wake.caf")
            audioPlayer.play(url: defaultURL, loop: true, gapSeconds: gap)
        } else {
            print("🎬 AlarmRingView.startAudio: ⚠️ default sunny_wake.caf missing from bundle — no audio")
        }
    }
}

#Preview {
    AlarmRingView()
}
