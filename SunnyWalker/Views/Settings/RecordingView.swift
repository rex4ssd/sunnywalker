// SunnyWalker — RecordingView.swift  |  Day 5  |  parent voice recording UI

import SwiftUI
import SwiftData
import AVFAudio  // 量最終錄音檔長度（AVAudioFile length / sampleRate）

struct RecordingView: View {
    @Bindable var alarm: Alarm
    let title: LocalizedStringKey
    let prompt: LocalizedStringKey
    let suggestedDisplayName: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var recordingError: String?
    @State private var draftDisplayName: String
    // 3 分鐘到自動收尾（與 AudioRecorder 的硬上限同步）。手動按停止會先 cancel 它。
    @State private var autoStopWork: DispatchWorkItem?
    // 最終錄音長度（秒）——stop 後量實際檔案（AVAudioFile），或進頁時量既有錄音檔。
    @State private var recordedSeconds: Double?

    init(
        alarm: Alarm,
        title: LocalizedStringKey = "錄製自錄鈴聲",
        prompt: LocalizedStringKey = "請錄一段要播放給孩子聽的鈴聲",
        suggestedDisplayName: String = "起床囉"
    ) {
        self.alarm = alarm
        self.title = title
        self.prompt = prompt
        self.suggestedDisplayName = suggestedDisplayName
        _draftDisplayName = State(initialValue: alarm.recordingDisplayName ?? suggestedDisplayName)
    }

    private var hasRecording: Bool {
        audioRecorder.currentURL != nil || !alarm.recordingName.isEmpty
    }

    private var recordingStorageName: String {
        if !alarm.recordingName.isEmpty { return alarm.recordingName }
        let cleaned = displayNameForStorage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .map { char -> Character in
                if char.isLetter || char.isNumber { return char }
                return "-"
            }
        let collapsed = String(cleaned)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let fallback = collapsed.isEmpty ? "alarm" : collapsed
        return "\(fallback)-\(alarm.id.uuidString.prefix(8))"
    }

    private var displayNameForStorage: String {
        let trimmed = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? suggestedDisplayName : trimmed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SunnyColors.cloudWhite.ignoresSafeArea()
                VStack(spacing: 40) {
                    Spacer()
                    totoroSection
                    statusSection
                    controlSection
                    Spacer()
                }
                .padding(.horizontal, 32)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.forestDeep)
                }
            }
            // 視窗關掉就取消尚未觸發的 3 分鐘自動停止計時器，避免它在 view 消失後才 fire。
            // 錄到一半直接按「完成」關頁：顯式停止（原 AVAudioRecorder 靠 dealloc 隱式停；
            // 共用件要顯式 stop 才會停引擎、還原 AVAudioSession）。
            // 無條件 stop（不 guard isRecording）：start 還懸在 await（權限窗/session 啟用）時
            // 離頁，isRecording 尚為 false — 這個 stop 讓那筆 start 落敗，麥克風不會在離頁後才開錄。
            // idle 時 stop 是安全 no-op。
            .onDisappear {
                autoStopWork?.cancel(); autoStopWork = nil
                Task { await audioRecorder.stop() }
            }
            // 進頁時若已有錄音（重錄情境），量既有檔案長度讓「錄音完成」也看得到 分:秒。
            .onAppear {
                if recordedSeconds == nil, !alarm.recordingName.isEmpty {
                    recordedSeconds = Self.measureSeconds(recordingNamed: alarm.recordingName)
                }
            }
        }
    }

    // MARK: - Duration helpers

    /// 量 `Recordings/<name>.m4a` 的實際長度（與 VoiceLibraryView 同一套 length/sampleRate 量法）。
    static func measureSeconds(recordingNamed name: String) -> Double? {
        let url = AppPaths.recordingURL(named: name)
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sr = file.processingFormat.sampleRate
        return sr > 0 ? Double(file.length) / sr : nil
    }

    // MARK: - Subviews

    private var totoroSection: some View {
        MascotView()
    }

    private var statusSection: some View {
        VStack(spacing: 8) {
            if audioRecorder.isRecording {
                // 共用件的即時音量（tap RMS）→ 現成的「錄音中…」文字隨聲音明暗呼吸，
                // 家長講話時看得到「有收到音」的回饋。
                Text("錄音中…")
                    .font(SunnyFonts.title(24))
                    .foregroundStyle(SunnyColors.lanternOrange)
                    .opacity(0.55 + 0.45 * Double(min(audioRecorder.level * 2, 1)))
                    .animation(.linear(duration: 0.1), value: audioRecorder.level)
                // 精準已錄時長 分:秒（純數字免翻譯）；有上限（免費 3 分鐘）時併顯示上限。
                Text(AudioRecorder.maxRecordingSeconds.isFinite
                     ? "\(audioRecorder.elapsed.minSecString) / \(AudioRecorder.maxRecordingSeconds.minSecString)"
                     : audioRecorder.elapsed.minSecString)
                    .font(SunnyFonts.title(30).monospacedDigit())
                    .foregroundStyle(SunnyColors.nightIndigo)
            } else if hasRecording {
                Text("錄音完成 ✅")
                    .font(SunnyFonts.title(24))
                    .foregroundStyle(SunnyColors.forestDeep)
                if let secs = recordedSeconds, secs > 0 {
                    // 錄完的實際檔案長度（量測 m4a，不是 UI 計時器）——分:秒。
                    Label(secs.minSecString, systemImage: "clock")
                        .font(SunnyFonts.title(20).monospacedDigit())
                        .foregroundStyle(SunnyColors.nightIndigo.opacity(0.9))
                }
            } else {
                Text(prompt)
                    .font(SunnyFonts.title(22))
                    .foregroundStyle(SunnyColors.nightIndigo)
                    .multilineTextAlignment(.center)
            }
            Text(L("預設檔名：%@", suggestedDisplayName))
                .font(SunnyFonts.caption(13))
                .foregroundStyle(SunnyColors.sunnyGray.opacity(0.82))
                .multilineTextAlignment(.center)
            if AudioRecorder.maxRecordingSeconds.isFinite {
                Text(L("錄音最長 %lld 分鐘，超過會自動停止",
                       Int(AudioRecorder.maxRecordingSeconds / 60)))
                    .font(SunnyFonts.caption(12))
                    .foregroundStyle(SunnyColors.sunnyGray.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            TextField("自錄鈴聲名稱", text: $draftDisplayName)
                .font(SunnyFonts.caption(15))
                .foregroundStyle(SunnyColors.nightIndigo)
                .tint(SunnyColors.leafFresh)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.82))
                )
                .colorScheme(.light)   // iOS 26 深色模式輸入文字看不到字的修法
            if let error = recordingError {
                Text(error)
                    .font(SunnyFonts.caption())
                    .foregroundStyle(SunnyColors.lanternOrange)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var controlSection: some View {
        VStack(spacing: 16) {
            if audioRecorder.isRecording {
                SunnyButton("停止錄音 ⏹", color: SunnyColors.forestDeep) {
                    stopRecording()
                }
            } else {
                SunnyButton(hasRecording ? "重新錄音 🎙️" : "開始錄音 🎙️",  // i18n-ignore: SunnyButton 單一 LocalizedStringKey overload，三元正確查表
                             color: SunnyColors.lanternOrange) {
                    startRecording()
                }
                if hasRecording {
                    SunnyButton("試聽 ▶️", color: SunnyColors.skyBlue) {
                        playRecording()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func startRecording() {
        recordingError = nil
        audioPlayer.stop()
        Task {
            do {
                try await audioRecorder.start(named: recordingStorageName)
                // start 可能被 await 期間的 stop 靜默取消（onDisappear 離頁）— 沒真的開錄
                // 就不要排自動停止計時器。
                guard audioRecorder.isRecording else { return }
                scheduleAutoStop()
            } catch {
                recordingError = L("recording_failed %@", error.localizedDescription)
            }
        }
    }

    /// 錄音上限到 → 自動跑跟手動「停止錄音」一樣的收尾流程（存檔名、匯出 CAF）。
    /// Pro（無上限）時不排計時器。
    private func scheduleAutoStop() {
        autoStopWork?.cancel(); autoStopWork = nil
        let cap = AudioRecorder.maxRecordingSeconds
        guard cap.isFinite else { return }
        // 不 guard isRecording：AudioRecorder 內建的 elapsed 上限備援可能已先停了錄音
        // （此時 isRecording 已 false），收尾流程（存檔名、匯出 CAF）仍然要跑；
        // stopRecording → audioRecorder.stop() 冪等，重複呼叫拿到同一個結果。
        let work = DispatchWorkItem { stopRecording() }
        autoStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + cap, execute: work)
    }

    private func stopRecording() {
        autoStopWork?.cancel(); autoStopWork = nil
        Task {
            // 共用件 stop 後要 finalize（縫合分段）＋改名，Recordings/<name>.m4a 才存在 —
            // CAF 匯出必須等它完成。
            _ = await audioRecorder.stop()
            // 量實際檔案長度（不是 UI 計時器值）——顯示在「錄音完成」下方。
            recordedSeconds = Self.measureSeconds(recordingNamed: recordingStorageName)
            alarm.recordingName = recordingStorageName
            alarm.recordingDisplayName = displayNameForStorage
            // Export a lock-screen-playable CAF and point the alarm's sound at it, so AlarmKit
            // rings the parent's custom recording immediately — instead of the bundled default
            // tone that only switched to the recording after the app was opened.
            // (Re-scheduling happens in AlarmEditorView.saveAlarm, which reads soundFileName.)
            // 匯出走背景執行緒：3 分鐘的錄音要整段讀進記憶體再寫 CAF，放 main 會讓畫面卡一下。
            let name = recordingStorageName
            if let caf = await Task.detached(priority: .userInitiated, operation: {
                AlarmSoundExporter.exportLockScreenCAF(fromRecordingNamed: name)
            }).value {
                alarm.soundFileName = caf
            }
        }
    }

    private func playRecording() {
        let name = alarm.recordingName.isEmpty
            ? (audioRecorder.currentURL?.deletingPathExtension().lastPathComponent ?? "")
            : alarm.recordingName
        guard AppPaths.recordingExists(named: name) else { return }
        audioPlayer.play(url: AppPaths.recordingURL(named: name), loop: false)
    }
}

#Preview {
    RecordingView(alarm: Alarm(label: "上學囉", hour: 7, minute: 30), suggestedDisplayName: "上學囉")
        .modelContainer(for: Alarm.self, inMemory: true)
}
