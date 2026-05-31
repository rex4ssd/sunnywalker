// SunnyWalker — RecordingView.swift  |  Day 5  |  parent voice recording UI

import SwiftUI
import SwiftData

struct RecordingView: View {
    @Bindable var alarm: Alarm
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var recordingError: String?

    private var hasRecording: Bool {
        audioRecorder.currentURL != nil || !alarm.recordingName.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GhibliColors.cloudWhite.ignoresSafeArea()
                VStack(spacing: 40) {
                    Spacer()
                    totoroSection
                    statusSection
                    controlSection
                    Spacer()
                }
                .padding(.horizontal, 32)
            }
            .navigationTitle("錄製起床音")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .font(GhibliFonts.caption())
                        .foregroundStyle(GhibliColors.forestDeep)
                }
            }
        }
    }

    // MARK: - Subviews

    private var totoroSection: some View {
        TotoroAvatar()
    }

    private var statusSection: some View {
        VStack(spacing: 8) {
            if audioRecorder.isRecording {
                Text("錄音中…")
                    .font(GhibliFonts.title(24))
                    .foregroundStyle(GhibliColors.lanternOrange)
            } else if hasRecording {
                Text("錄音完成 ✅")
                    .font(GhibliFonts.title(24))
                    .foregroundStyle(GhibliColors.forestDeep)
            } else {
                Text("請說一段起床的話給孩子聽")
                    .font(GhibliFonts.title(22))
                    .foregroundStyle(GhibliColors.nightIndigo)
                    .multilineTextAlignment(.center)
            }
            if let error = recordingError {
                Text(error)
                    .font(GhibliFonts.caption())
                    .foregroundStyle(GhibliColors.lanternOrange)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var controlSection: some View {
        VStack(spacing: 16) {
            if audioRecorder.isRecording {
                GhibliButton("停止錄音 ⏹", color: GhibliColors.forestDeep) {
                    stopRecording()
                }
            } else {
                GhibliButton(hasRecording ? "重新錄音 🎙️" : "開始錄音 🎙️",
                             color: GhibliColors.lanternOrange) {
                    startRecording()
                }
                if hasRecording {
                    GhibliButton("試聽 ▶️", color: GhibliColors.skyBlue) {
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
            try audioRecorder.start(named: alarm.id.uuidString)
        } catch {
            recordingError = "無法開始錄音：\(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        audioRecorder.stop()
        alarm.recordingName = alarm.id.uuidString
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
    RecordingView(alarm: Alarm(label: "上學囉", hour: 7, minute: 30))
        .modelContainer(for: Alarm.self, inMemory: true)
}
