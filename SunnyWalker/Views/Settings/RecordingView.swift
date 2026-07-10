// SunnyWalker — RecordingView.swift  |  Day 5  |  parent voice recording UI

import SwiftUI
import SwiftData

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
            .onDisappear { autoStopWork?.cancel(); autoStopWork = nil }
        }
    }

    // MARK: - Subviews

    private var totoroSection: some View {
        MascotView()
    }

    private var statusSection: some View {
        VStack(spacing: 8) {
            if audioRecorder.isRecording {
                Text("錄音中…")
                    .font(SunnyFonts.title(24))
                    .foregroundStyle(SunnyColors.lanternOrange)
            } else if hasRecording {
                Text("錄音完成 ✅")
                    .font(SunnyFonts.title(24))
                    .foregroundStyle(SunnyColors.forestDeep)
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
        do {
            try audioRecorder.start(named: recordingStorageName)
            scheduleAutoStop()
        } catch {
            recordingError = L("recording_failed %@", error.localizedDescription)
        }
    }

    /// 錄音上限到 → 自動跑跟手動「停止錄音」一樣的收尾流程（存檔名、匯出 CAF）。
    /// Pro（無上限）時不排計時器。
    private func scheduleAutoStop() {
        autoStopWork?.cancel(); autoStopWork = nil
        let cap = AudioRecorder.maxRecordingSeconds
        guard cap.isFinite else { return }
        let work = DispatchWorkItem {
            if audioRecorder.isRecording { stopRecording() }
        }
        autoStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + cap, execute: work)
    }

    private func stopRecording() {
        autoStopWork?.cancel(); autoStopWork = nil
        audioRecorder.stop()
        alarm.recordingName = recordingStorageName
        alarm.recordingDisplayName = displayNameForStorage
        // Export a lock-screen-playable CAF and point the alarm's sound at it, so AlarmKit
        // rings the parent's custom recording immediately — instead of the bundled default
        // tone that only switched to the recording after the app was opened.
        // (Re-scheduling happens in AlarmEditorView.saveAlarm, which reads soundFileName.)
        if let caf = AlarmSoundExporter.exportLockScreenCAF(fromRecordingNamed: recordingStorageName) {
            alarm.soundFileName = caf
        }
    }

    private func playRecording() {
        let name = alarm.recordingName.isEmpty
            ? (audioRecorder.currentURL?.deletingPathExtension().lastPathComponent ?? "")
            : alarm.recordingName
        guard !name.isEmpty else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Recordings/\(name).m4a")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        audioPlayer.play(url: url, loop: false)
    }
}

#Preview {
    RecordingView(alarm: Alarm(label: "上學囉", hour: 7, minute: 30), suggestedDisplayName: "上學囉")
        .modelContainer(for: Alarm.self, inMemory: true)
}
