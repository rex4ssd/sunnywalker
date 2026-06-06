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
                SunnyButton(hasRecording ? "重新錄音 🎙️" : "開始錄音 🎙️",
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
        } catch {
            recordingError = L("recording_failed %@", error.localizedDescription)
        }
    }

    private func stopRecording() {
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
