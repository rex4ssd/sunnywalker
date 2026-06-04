// SunnyWalker — VoiceLibraryView.swift
// Standalone voice-clip library: browse / play / delete / record new clips.
// Max 5 clips × 5 seconds each (free tier). Raise the constants below for paid upgrades.

import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Upgrade-path limits

enum VoiceClipLimits {
    /// Maximum number of clips (free tier). Paid tier can raise this.
    static let maxCount: Int = 5
    /// Maximum recording duration in seconds (free tier). Paid tier can raise this.
    static let maxDurationSeconds: Double = 5.0
}

// MARK: - VoiceLibraryView

struct VoiceLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VoiceClip.createdAt, order: .reverse) private var clips: [VoiceClip]

    @StateObject private var player = AudioPlayer()
    @State private var playingID: UUID?
    @State private var showingRecorder = false
    @State private var deleteTarget: VoiceClip?
    @State private var showDeleteConfirm = false

    private var canAddMore: Bool { clips.count < VoiceClipLimits.maxCount }

    var body: some View {
        NavigationStack {
            ZStack {
                SunnyColors.cloudWhite.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Slot counter — xcstrings key "clips_counter %lld %lld"
                    HStack {
                        Label {
                            Text("clips_counter \(clips.count) \(VoiceClipLimits.maxCount)")
                                .font(SunnyFonts.caption(13))
                                .foregroundStyle(SunnyColors.sunnyGray)
                        } icon: {
                            Image(systemName: "waveform")
                                .foregroundStyle(SunnyColors.sunnyGray)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    if clips.isEmpty {
                        emptyState
                    } else {
                        clipList
                    }

                    Spacer(minLength: 16)

                    addButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle("錄音管理 🎙️")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.forestDeep)
                }
            }
        }
        // Stop player when a clip finishes
        .onReceive(player.$isPlaying) { playing in
            if !playing { playingID = nil }
        }
        .sheet(isPresented: $showingRecorder) {
            VoiceClipRecorderSheet { clip in
                modelContext.insert(clip)
            }
        }
        .confirmationDialog(
            "刪除這段錄音？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("刪除", role: .destructive) {
                if let clip = deleteTarget { deleteClip(clip) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("🎵")
                .font(.system(size: 64))
            Text("還沒有錄音\n點下面的按鈕錄一段吧！")
                .font(SunnyFonts.title(18))
                .foregroundStyle(SunnyColors.nightIndigo.opacity(0.5))
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var clipList: some View {
        List {
            ForEach(clips) { clip in
                VoiceClipRow(
                    clip: clip,
                    isPlaying: playingID == clip.id,
                    onPlay: { togglePlay(clip) },
                    onDelete: { deleteTarget = clip; showDeleteConfirm = true }
                )
                .listRowBackground(Color.white.opacity(0.75))
                .listRowSeparatorTint(SunnyColors.leafFresh.opacity(0.3))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var addButton: some View {
        Button {
            showingRecorder = true
        } label: {
            Label {
                // xcstrings keys: "新增錄音" / "clips_limit_reached %lld"
                if canAddMore {
                    Text("新增錄音")
                } else {
                    Text("clips_limit_reached \(VoiceClipLimits.maxCount)")
                }
            } icon: {
                Image(systemName: canAddMore ? "mic.circle.fill" : "lock.circle.fill")
            }
            .font(SunnyFonts.title(17))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(canAddMore ? SunnyColors.lanternOrange : SunnyColors.sunnyGray)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(
                color: (canAddMore ? SunnyColors.lanternOrange : SunnyColors.sunnyGray).opacity(0.35),
                radius: 8, y: 4
            )
        }
        .disabled(!canAddMore)
    }

    // MARK: - Actions

    private func togglePlay(_ clip: VoiceClip) {
        if playingID == clip.id {
            player.stop()
            playingID = nil
        } else {
            player.stop()
            playingID = clip.id
            let url = clip.recordingsURL
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            player.play(url: url, loop: false)
        }
    }

    private func deleteClip(_ clip: VoiceClip) {
        if playingID == clip.id { player.stop(); playingID = nil }
        try? FileManager.default.removeItem(at: clip.recordingsURL)
        modelContext.delete(clip)
    }
}

// MARK: - VoiceClipRow

private struct VoiceClipRow: View {
    let clip: VoiceClip
    let isPlaying: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Play / pause toggle
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(isPlaying ? SunnyColors.lanternOrange : SunnyColors.leafFresh)
                    .symbolEffect(.pulse, isActive: isPlaying)
            }
            .buttonStyle(.plain)

            // Name + meta
            VStack(alignment: .leading, spacing: 5) {
                Text(clip.name)
                    .font(SunnyFonts.title(16))
                    .foregroundStyle(SunnyColors.nightIndigo)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(clip.formattedDuration, systemImage: "clock")
                        .font(SunnyFonts.caption(12))
                        .foregroundStyle(SunnyColors.sunnyGray)
                    Text(clip.createdAt, style: .date)
                        .font(SunnyFonts.caption(12))
                        .foregroundStyle(SunnyColors.sunnyGray.opacity(0.7))
                }
            }

            Spacer()

            // Delete
            Button(action: onDelete) {
                Image(systemName: "trash.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(SunnyColors.lanternOrange.opacity(0.75))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - VoiceClipRecorderSheet

struct VoiceClipRecorderSheet: View {
    /// Called with the finished VoiceClip so the caller can insert it into the model context.
    let onSave: (VoiceClip) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var player   = AudioPlayer()

    @State private var clipName       = ""
    @State private var phase          = RecorderPhase.ready
    @State private var countdown      = Int(VoiceClipLimits.maxDurationSeconds)
    @State private var countdownTimer: Timer?
    @State private var recordedBase   = ""    // UUID string — AudioRecorder stores as <base>.m4a
    @State private var recordedDuration: TimeInterval = 0
    @State private var errorMessage: String?

    enum RecorderPhase { case ready, recording, done }

    private var maxSeconds: Int { Int(VoiceClipLimits.maxDurationSeconds) }

    var body: some View {
        NavigationStack {
            ZStack {
                SunnyColors.cloudWhite.ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()
                    MascotView()
                    statusArea
                    recordButton
                    if phase == .done { actionRow }
                    if let msg = errorMessage {
                        Text(msg)
                            .font(SunnyFonts.caption(13))
                            .foregroundStyle(SunnyColors.lanternOrange)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                }
                .padding(.horizontal, 32)
            }
            .navigationTitle("新增錄音 🎙️")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        cancelAndDismiss()
                    }
                    .font(SunnyFonts.caption())
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusArea: some View {
        switch phase {
        case .ready:
            Text("準備好了嗎？")
                .font(SunnyFonts.title(22))
                .foregroundStyle(SunnyColors.nightIndigo)

        case .recording:
            VStack(spacing: 12) {
                Text("錄音中…")
                    .font(SunnyFonts.title(22))
                    .foregroundStyle(SunnyColors.lanternOrange)

                // Circular countdown
                ZStack {
                    Circle()
                        .stroke(SunnyColors.lanternOrange.opacity(0.15), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: CGFloat(countdown) / CGFloat(maxSeconds))
                        .stroke(
                            SunnyColors.lanternOrange,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: countdown)
                    Text("\(countdown)")
                        .font(SunnyFonts.clock(32))
                        .foregroundStyle(SunnyColors.lanternOrange)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: countdown)
                }
                .frame(width: 88, height: 88)
            }

        case .done:
            VStack(spacing: 12) {
                Text("錄好了！✅")
                    .font(SunnyFonts.title(22))
                    .foregroundStyle(SunnyColors.forestDeep)

                TextField("幫這段錄音取個名字", text: $clipName)
                    .font(SunnyFonts.title(16))
                    .foregroundStyle(SunnyColors.nightIndigo)
                    .tint(SunnyColors.leafFresh)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(SunnyColors.leafFresh.opacity(0.45), lineWidth: 1.5)
                    )
                    .colorScheme(.light)
            }
        }
    }

    private var recordButton: some View {
        Button { handleRecordTap() } label: {
            ZStack {
                Circle()
                    .fill(
                        phase == .recording
                            ? SunnyColors.lanternOrange
                            : SunnyColors.lanternOrange.opacity(0.12)
                    )
                    .frame(width: 92, height: 92)
                    .shadow(
                        color: SunnyColors.lanternOrange.opacity(phase == .recording ? 0.4 : 0.1),
                        radius: 12, y: 6
                    )

                Image(systemName: phase == .recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        phase == .recording ? .white : SunnyColors.lanternOrange
                    )
            }
        }
        .disabled(phase == .done)
        .opacity(phase == .done ? 0.25 : 1)
        .animation(.easeInOut(duration: 0.2), value: phase == .recording)
    }

    private var actionRow: some View {
        HStack(spacing: 20) {
            // Preview
            Button {
                if player.isPlaying {
                    player.stop()
                } else if !recordedBase.isEmpty {
                    let url = recordingURL(base: recordedBase)
                    guard FileManager.default.fileExists(atPath: url.path) else { return }
                    player.play(url: url, loop: false)
                }
            } label: {
                Label(
                    player.isPlaying ? "停止" : "試聽",
                    systemImage: player.isPlaying ? "pause.fill" : "play.fill"
                )
                .font(SunnyFonts.caption())
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(SunnyColors.skyBlue)
                .clipShape(Capsule())
            }

            // Save
            Button { saveClip() } label: {
                Label("儲存", systemImage: "checkmark.circle.fill")
                    .font(SunnyFonts.caption())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(
                        clipName.trimmingCharacters(in: .whitespaces).isEmpty
                            ? SunnyColors.sunnyGray
                            : SunnyColors.forestDeep
                    )
                    .clipShape(Capsule())
            }
            .disabled(clipName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Logic

    private func handleRecordTap() {
        switch phase {
        case .ready:    startRecording()
        case .recording: stopRecording()
        case .done:      break
        }
    }

    private func startRecording() {
        errorMessage = nil
        let base = UUID().uuidString
        do {
            try recorder.start(named: base)  // saves to Documents/Recordings/<base>.m4a
            recordedBase = base
            phase = .recording
            countdown = maxSeconds
            beginCountdown()
        } catch {
            errorMessage = L("recording_launch_failed %@", error.localizedDescription)
        }
    }

    private func stopRecording() {
        countdownTimer?.invalidate(); countdownTimer = nil
        recorder.stop()
        phase = .done
        if clipName.isEmpty { clipName = "我的錄音" }

        // Measure actual duration from the written file
        let url = recordingURL(base: recordedBase)
        if let af = try? AVAudioFile(forReading: url) {
            let sr = af.processingFormat.sampleRate
            recordedDuration = sr > 0 ? Double(af.length) / sr : 0
        }
    }

    private func beginCountdown() {
        countdownTimer?.invalidate()
        // Use a stored local reference so the closure can invalidate it without capturing self
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            Task { @MainActor in
                self.countdown -= 1
                if self.countdown <= 0 {
                    t.invalidate()
                    self.countdownTimer = nil
                    self.stopRecording()
                }
            }
        }
        countdownTimer = timer
    }

    private func saveClip() {
        player.stop()
        let trimmed = clipName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !recordedBase.isEmpty else { return }
        let clip = VoiceClip(
            name: trimmed,
            fileName: recordedBase + ".m4a",
            duration: recordedDuration
        )
        onSave(clip)
        dismiss()
    }

    private func cancelAndDismiss() {
        countdownTimer?.invalidate(); countdownTimer = nil
        recorder.stop()
        player.stop()
        // Clean up any partially-written file
        if !recordedBase.isEmpty {
            try? FileManager.default.removeItem(at: recordingURL(base: recordedBase))
        }
        dismiss()
    }

    private func recordingURL(base: String) -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings/\(base).m4a")
    }
}

// MARK: - Previews

#Preview("Library — empty") {
    VoiceLibraryView()
        .modelContainer(for: VoiceClip.self, inMemory: true)
}

#Preview("Recorder") {
    VoiceClipRecorderSheet { _ in }
        .modelContainer(for: VoiceClip.self, inMemory: true)
}
