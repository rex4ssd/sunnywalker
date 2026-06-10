// SunnyWalker — AlarmRingView.swift  |  Day 27  |  Accessibility + reduceMotion

import SwiftUI
import SwiftData
import UIKit

struct AlarmRingView: View {
    var alarm: Alarm? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var audioPlayer = AudioPlayer()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var wiggle = false
    @State private var showingReward = false
    @State private var speechTask: Task<Void, Never>?
    @State private var ringTimeoutTask: Task<Void, Never>?
    @State private var recognitionFailureCount = 0
    @State private var showFallbackButton = false
    // True once we've begun closing the ring (wake success or ring-timeout). Guards the
    // foreground audio-resume in scenePhase → .active so it can't resurrect a stopped alarm
    // during the brief success/timeout chime → dismiss() window.
    @State private var isFinishing = false

    // Wake timestamp — set when view appears, used for WakeRecord response time
    @State private var firedAt = Date()

    // Day 12: listening feedback state
    @State private var isListening = false
    @State private var showRetryMessage = false
    @State private var micPulse = false
    @State private var fallbackButtonEnabled = false

    // Time-multiplex 響鈴/聆聽：鈴聲響一段 → 靜音開聆聽窗（提示穿插在間隔）→ 沒中就再響。
    // 「間隔不夠就自動拉長」= 聆聽窗本身就是被拉長的間隔，長度 = listenWindowSeconds。
    private let ringWindowSeconds: Double = 4      // 每輪先響多久讓孩子聽到（首輪用 warmup 5s）
    private let listenWindowSeconds: Double = 7    // 聆聽窗長度（鈴聲此時靜音）

    private var scene: DaytimeScene {
        DaytimeScene.current(hour: Calendar.current.component(.hour, from: Date()))
    }

    /// 聆聽時顯示「要喊什麼」的提示。
    /// 有自定口令 → 「說：太陽公公、我起床了」（自定口令 + 預設代表詞「我起床了」，都能辨識）；
    /// 沒有 → 維持預設「說『我起床了』」。
    var attemptLabel: String {
        let custom = alarm?.effectiveCustomPhrases ?? []
        if !custom.isEmpty {
            let all = custom + [L("我起床了")]   // 自定口令 + 預設代表詞
            return L("say_phrase_hint %@", all.joined(separator: L("、")))
        }
        return L("attempt_counter %lld", min(recognitionFailureCount + 1, 3))
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
            let appearTime = Date()
            firedAt = appearTime   // record alarm fire time for WakeRecord
            print("🔔 AlarmRingView.onAppear [\(ts(appearTime))] alarm=\(alarm?.id.uuidString.prefix(8) ?? "nil") taskType=\(alarm?.effectiveTaskType.rawValue ?? "?") requireAppToStop=\(alarm?.effectiveRequireAppToStop ?? false) ringDuration=\(AppSettings.shared.alarmRingDurationMinutes)min")
            wiggle = true
            // App is now open for this alarm → stop the strict-mode "貪睡模式" nag notifications.
            if let alarm { AlarmScheduler.shared.cancelNags(alarm.id) }
            handoffSystemAlarmIfNeeded()
            // Keep the screen awake while the alarm is actively ringing.
            UIApplication.shared.isIdleTimerDisabled = true
            startAudio()
            startRingTimeout()
            // .button taskType: skip speech — child taps to dismiss immediately
            if alarm?.effectiveTaskType == .button {
                showFallbackButton = true
                fallbackButtonEnabled = true
            } else {
                // .voice (default): 先響一段 warm-up，再開第一個聆聽窗（time-multiplex）。
                speechTask = Task {
                    try? await Task.sleep(for: .seconds(5))   // 首輪響鈴 = warm-up
                    guard !Task.isCancelled else { return }
                    startListenWindow()
                }
            }
        }
        .onDisappear {
            print("🔔 AlarmRingView.onDisappear [\(ts())] — cancelling ringTimeoutTask + speechTask")
            speechTask?.cancel()
            ringTimeoutTask?.cancel()
            audioPlayer.stop()
            speechRecognizer.stop()
            // Let the device auto-lock / sleep again once the alarm screen is gone.
            UIApplication.shared.isIdleTimerDisabled = false
        }
        // 切到別的 app（背景）時聲控必定失效（mic 被中斷）。原本沒處理 → 切回前景
        // speechRecognizer 卡死、UI 還顯示「聆聽中」但喊話無效（圖3：切回來一直說話不停）。
        // 修法：切背景→停聲控並重置狀態；切回前景→若還在響鈴(voice 模式、未進 fallback/reward)就重啟聆聽。
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background, .inactive:
                // 背景無法辨識：停聲控。⚠️ 若此刻正在「聆聽窗」(鈴聲被 stop 靜音)就進背景，會變永久
                // 靜音（issue#2）。所以停聲控後，若沒有東西在響，立刻把鈴聲交回外部 AudioPlayer
                // （.playback + 背景音訊模式 + 中斷復活）繼續響。
                print("🎤 AlarmRingView.scenePhase → \(phase): 停止聲控（背景無法辨識），確保鈴聲續響 isPlaying=\(audioPlayer.isPlaying)")
                speechTask?.cancel()
                speechTask = nil
                speechRecognizer.stop()
                isListening = false
                micPulse = false
                if !showingReward && !isFinishing && !audioPlayer.isPlaying {
                    startAudio()
                }
            case .active:
                // ★ Issue #2：回前景時，無論哪種 taskType，只要還在響鈴階段（未進 reward / timeout），
                // 先確保鈴聲還活著——背景被 suspend 可能讓 loop chain 斷掉 → 永久靜音。死了就重啟。
                if !showingReward && !isFinishing && audioPlayer.isPlaying == false {
                    print("🎤 AlarmRingView.scenePhase → active: 偵測到鈴聲已停 → 重新 startAudio()")
                    startAudio()
                }
                // 回前景：仍在響鈴、voice 模式、還沒按 fallback / 還沒成功 → 先讓鈴聲響一小段
                // （session 也順便從背景恢復），再開聆聽窗。
                guard !showingReward, !showFallbackButton,
                      alarm?.effectiveTaskType != .button else { return }
                print("🎤 AlarmRingView.scenePhase → active: 重啟響鈴/聆聽循環")
                speechTask?.cancel()
                speechTask = Task {
                    try? await Task.sleep(for: .seconds(2))   // 等 session 恢復 + 響一下再聽
                    guard !Task.isCancelled else { return }
                    startListenWindow()
                }
            @unknown default:
                break
            }
        }
        .fullScreenCover(isPresented: $showingReward, onDismiss: { dismiss() }) {
            RewardView()
        }
    }

    // MARK: - Speech cycle

    /// 開一個「聆聽窗」：先把鈴聲靜音（time-multiplex 的核心——聆聽時沒有並存播放，mic 才乾淨、
    /// 也不會 self-match），再用 plain mic 聽 listenWindowSeconds 秒。鈴聲會在沒中時由
    /// handleRecognitionFailure 重新響起（提示詞就穿插在這段靜音間隔裡）。
    private func startListenWindow() {
        guard !showingReward, !showFallbackButton, !isFinishing else { return }
        print("🎤 AlarmRingView.startListenWindow: attempt #\(recognitionFailureCount + 1) — 鈴聲靜音 + 開聆聽窗 \(listenWindowSeconds)s")
        isListening = true
        micPulse = true
        audioPlayer.stop()   // ⭐ 聆聽期間鈴聲靜音；不傳 alarmReferenceURL → plain mic、不開 VPIO
        do {
            try speechRecognizer.startListening(onMatch: { keyword in
                print("🎤 AlarmRingView: MATCHED '\(keyword)' — waking up")
                self.isListening = false
                self.micPulse = false
                self.handleWakeUp(dismissMethod: "voice")
            }, onFailure: {
                print("🎤 AlarmRingView: listen window onFailure (no match / timeout)")
                self.isListening = false
                self.micPulse = false
                self.handleRecognitionFailure()
            }, listeningTimeout: listenWindowSeconds,
               extraKeywords: alarm?.effectiveCustomPhrases ?? [])   // 這個鬧鐘的自定口令
        } catch {
            print("🎤 AlarmRingView.startListenWindow: startListening THREW — \(error.localizedDescription)")
            isListening = false
            micPulse = false
            handleRecognitionFailure()
        }
    }

    private func handleRecognitionFailure() {
        recognitionFailureCount += 1
        if recognitionFailureCount >= 3 {
            // 放棄聲控：保持響鈴 + 顯示 fallback 按鈕。
            startAudio()
            withAnimation { showFallbackButton = true }
            // Enable button after 0.5s — prevents accidental tap-through on appearance
            speechTask = Task {
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
                fallbackButtonEnabled = true
            }
        } else {
            // ⭐ RING phase：把鈴聲放回來再響一段（孩子重新聽到），同時顯示「再試一次」提示，
            // 響滿 ringWindowSeconds 後才開下一個聆聽窗 → 提示/聆聽穿插在響鈴間隔、間隔自動拉長。
            startAudio()
            showRetryMessage = true
            speechTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                showRetryMessage = false
                let remain = max(0, ringWindowSeconds - 1.5)   // 湊滿 ring window 再聆聽
                try? await Task.sleep(for: .seconds(remain))
                guard !Task.isCancelled else { return }
                startListenWindow()
            }
        }
    }

    // MARK: - Ring duration auto-stop

    /// After the parent-configured ring duration, give up waking the child, silence everything,
    /// and let the screen sleep — so the battery doesn't drain if nobody's there.
    private func startRingTimeout() {
        let minutes = max(1, min(10, AppSettings.shared.alarmRingDurationMinutes))
        let fireAt = Date().addingTimeInterval(Double(minutes * 60))
        print("⏰ AlarmRingView.startRingTimeout [\(ts())] duration=\(minutes)min fireAt=\(ts(fireAt))")
        ringTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(Double(minutes * 60)))
            if Task.isCancelled {
                print("⏰ AlarmRingView.ringTimeoutTask CANCELLED before firing — auto-stop will NOT run")
                return
            }
            print("⏰ AlarmRingView.ringTimeoutTask FIRED [\(ts())]")
            handleAutoStop()
        }
    }

    private func handleAutoStop() {
        print("⏰ AlarmRingView.handleAutoStop [\(ts())] — playing timeout_sad.wav then dismiss()")
        isFinishing = true
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
            print("⏰ AlarmRingView.handleAutoStop: calling dismiss() [\(ts())]")
            dismiss()
        }
    }

    private func handoffSystemAlarmIfNeeded() {
        guard let alarm else {
            print("🔔 AlarmRingView.handoffSystemAlarmIfNeeded: alarm=nil — skip")
            return
        }
        let alarmID = alarm.id
        print("🔔 AlarmRingView.handoffSystemAlarmIfNeeded: calling AlarmKitService.stop(\(alarmID.uuidString.prefix(8)))")
        Task { @MainActor in
            do {
                try await AlarmKitService.shared.stop(id: alarmID)
                print("🔔 AlarmRingView.handoffSystemAlarmIfNeeded: stop() OK [\(ts())]")
            } catch {
                print("🔔 AlarmRingView.handoffSystemAlarmIfNeeded: stop() FAILED — \(error) [\(ts())]")
            }
        }
    }

    // MARK: - Log helpers

    private func ts(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }

    private func handleWakeUp(dismissMethod: String = "voice") {
        isFinishing = true
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

    /// Resolve which audio file the alarm should play, and the inter-loop gap. Single source of
    /// truth shared by the external AudioPlayer (warm-up / background / fallback) AND the speech
    /// engine (which plays the same file as the AEC reference while listening), so both always
    /// ring with the identical sound.
    /// Priority: parent recording → custom CAF in Library/Sounds → bundled CAF → default tone.
    private func resolveAlarmAudio() -> (url: URL, gap: Int)? {
        let gap = AppSettings.shared.recordingGapSeconds

        let recordingName = alarm?.recordingName ?? ""
        if !recordingName.isEmpty {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = docs.appendingPathComponent("Recordings/\(recordingName).m4a")
            if FileManager.default.fileExists(atPath: url.path) { return (url, gap) }
            print("🎬 AlarmRingView.resolveAlarmAudio: recording \(recordingName).m4a MISSING — falling back")
        }

        // Exported custom alarm sounds live in Library/Sounds (AlarmSoundExporter writes them there
        // for the notification path) — NOT the bundle. Check Library/Sounds first, then the bundle.
        let soundName = alarm?.soundFileName ?? ""
        if !soundName.isEmpty {
            let soundsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Sounds", isDirectory: true)
            let cafURL = soundsDir.appendingPathComponent(soundName)
            if FileManager.default.fileExists(atPath: cafURL.path) { return (cafURL, gap) }
            if let bundleURL = Bundle.main.url(forResource: soundName, withExtension: nil) { return (bundleURL, gap) }
            print("🎬 AlarmRingView.resolveAlarmAudio: \(soundName) not in Library/Sounds or bundle — using default tone")
        }

        // Guaranteed fallback: the bundled default alarm tone. NEVER leave the wake screen silent.
        if let defaultURL = Bundle.main.url(forResource: "sunny_wake.caf", withExtension: nil) {
            return (defaultURL, gap)
        }
        print("🎬 AlarmRingView.resolveAlarmAudio: ⚠️ default sunny_wake.caf missing from bundle — no audio")
        return nil
    }

    /// Play the alarm loop through the external AudioPlayer (.playback). Used outside the active
    /// listening window: warm-up, retry gaps, fallback-button wait, and background ringing. During
    /// listening the alarm is silenced (time-multiplex — see startListenWindow).
    private func startAudio() {
        guard let (url, gap) = resolveAlarmAudio() else { return }
        print("🎬 AlarmRingView.startAudio: playing \(url.lastPathComponent) (loop, gap=\(gap)s)")
        audioPlayer.play(url: url, loop: true, gapSeconds: gap)
    }
}

#Preview {
    AlarmRingView()
}
