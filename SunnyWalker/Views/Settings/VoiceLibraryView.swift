// SunnyWalker — VoiceLibraryView.swift
// Standalone voice-clip library: browse / play / delete / record new clips.
// Max 5 clips × 5 seconds each (free tier). Raise the constants below for paid upgrades.

import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Upgrade-path limits

/// Thin redirect to the central FeatureLimits so all paid-gated caps live in one place
/// (AppSettings.swift). Pro unlock flips FeatureLimits.isPro and these follow automatically.
enum VoiceClipLimits {
    static var maxCount: Int { FeatureLimits.maxVoiceClips }
    static var maxDurationSeconds: Double { FeatureLimits.maxVoiceClipSeconds }
}

// MARK: - VoiceLibraryView

struct VoiceLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VoiceClip.createdAt, order: .reverse) private var clips: [VoiceClip]

    @StateObject private var player = AudioPlayer()
    @State private var playingID: UUID?
    @State private var showingRecorder = false
    @State private var selectedClip: VoiceClip?
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
        .sheet(item: $selectedClip) { clip in
            VoiceClipDetailSheet(clip: clip) {
                deleteClip(clip)
                selectedClip = nil
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
                    onSelect: {
                        player.stop()
                        playingID = nil
                        selectedClip = clip
                    },
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
    let onSelect: () -> Void
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
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(clip.name)
                        .font(SunnyFonts.title(16))
                        .foregroundStyle(SunnyColors.nightIndigo)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Label(clip.formattedDuration, systemImage: "clock")
                            .font(SunnyFonts.caption(12))
                            .foregroundStyle(SunnyColors.sunnyGray)
                        Label(clip.formattedFileSize, systemImage: "externaldrive")
                            .font(SunnyFonts.caption(12))
                            .foregroundStyle(SunnyColors.sunnyGray.opacity(0.78))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            // 編輯 + 刪除 兩顆 icon，中間留 22pt 間隔避免按錯（小孩 / 大拇指誤觸）。
            HStack(spacing: 22) {
                Button(action: onSelect) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 24))
                        .foregroundStyle(SunnyColors.forestDeep.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("編輯"))

                Button(action: onDelete) {
                    Image(systemName: "trash.circle")
                        .font(.system(size: 26))
                        .foregroundStyle(SunnyColors.lanternOrange.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("刪除"))
            }
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

// MARK: - VoiceClipDetailSheet

private struct VoiceClipDetailSheet: View {
    @Bindable var clip: VoiceClip
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var player = AudioPlayer()
    @State private var draftName = ""
    @State private var showingTrimEditor = false
    @State private var showingDeleteConfirm = false

    private var trimmedName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var clipExists: Bool {
        FileManager.default.fileExists(atPath: clip.recordingsURL.path)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SunnyColors.cloudWhite.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        WatercolorCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("錄音名稱", systemImage: "pencil.line")
                                    .font(SunnyFonts.caption(14))
                                    .foregroundStyle(SunnyColors.sunnyGray)

                                TextField("幫這段錄音取個名字", text: $draftName)
                                    .font(SunnyFonts.title(18))
                                    .foregroundStyle(SunnyColors.nightIndigo)
                                    .padding(14)
                                    .background(Color.white.opacity(0.92))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .colorScheme(.light)   // iOS 26 深色模式輸入文字看不到字的修法

                                Button("儲存名稱") {
                                    clip.name = trimmedName
                                    try? modelContext.save()
                                }
                                .font(SunnyFonts.caption())
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(trimmedName.isEmpty || trimmedName == clip.name
                                              ? SunnyColors.sunnyGray
                                              : SunnyColors.forestDeep)
                                )
                                .disabled(trimmedName.isEmpty || trimmedName == clip.name)
                            }
                            .padding(18)
                        }

                        WatercolorCard {
                            VStack(alignment: .leading, spacing: 12) {
                                detailRow("長度", value: clip.formattedDuration, icon: "clock")
                                detailRow("大小", value: clip.formattedFileSize, icon: "externaldrive")
                                detailRow(
                                    "建立時間",
                                    value: clip.createdAt.formatted(date: .abbreviated, time: .shortened),
                                    icon: "calendar"
                                )
                                if !clipExists {
                                    Label("找不到原始音檔", systemImage: "exclamationmark.triangle.fill")
                                        .font(SunnyFonts.caption(13))
                                        .foregroundStyle(SunnyColors.lanternOrange)
                                }
                            }
                            .padding(18)
                        }

                        WatercolorCard {
                            VStack(spacing: 12) {
                                Button {
                                    if player.isPlaying {
                                        player.stop()
                                    } else if clipExists {
                                        player.play(url: clip.recordingsURL, loop: false)
                                    }
                                } label: {
                                    Label(player.isPlaying ? "停止試聽" : "播放錄音", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                                        .font(SunnyFonts.caption())
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(RoundedRectangle(cornerRadius: 16).fill(SunnyColors.skyBlue))
                                }
                                .disabled(!clipExists)

                                ShareLink(item: clip.recordingsURL, preview: SharePreview(clip.name)) {
                                    Label("分享到其他應用程式", systemImage: "square.and.arrow.up")
                                        .font(SunnyFonts.caption())
                                        .foregroundStyle(SunnyColors.nightIndigo)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.84)))
                                }
                                .disabled(!clipExists)

                                Button {
                                    showingTrimEditor = true
                                } label: {
                                    Label("裁左 / 裁右", systemImage: "timeline.selection")
                                        .font(SunnyFonts.caption())
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(RoundedRectangle(cornerRadius: 16).fill(SunnyColors.lanternOrange))
                                }
                                .disabled(!clipExists)
                            }
                            .padding(18)
                        }

                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("刪除這段錄音", systemImage: "trash")
                                .font(SunnyFonts.caption())
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(RoundedRectangle(cornerRadius: 16).fill(SunnyColors.lanternOrange))
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("錄音詳情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .font(SunnyFonts.caption())
                }
            }
        }
        .onAppear { draftName = clip.name }
        .onDisappear { player.stop() }
        .sheet(isPresented: $showingTrimEditor) {
            VoiceClipTrimSheet(clip: clip)
        }
        .confirmationDialog("刪除這段錄音？", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("刪除", role: .destructive) {
                player.stop()
                onDelete()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func detailRow(_ title: String, value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(SunnyFonts.caption(14))
                .foregroundStyle(SunnyColors.sunnyGray)
            Spacer()
            Text(value)
                .font(SunnyFonts.caption(14))
                .foregroundStyle(SunnyColors.nightIndigo)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - VoiceClipTrimSheet

private struct VoiceClipTrimSheet: View {
    @Bindable var clip: VoiceClip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var startTime = 0.0
    @State private var endTime = 0.0
    @State private var sourceDuration = 0.0
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var previewPlayer: AVAudioPlayer?
    @State private var previewDebounceTask: Task<Void, Never>?
    @State private var previewStopTask: Task<Void, Never>?
    @State private var isPreviewingSelection = false

    private let minimumDuration = 0.5

    private var preservedDuration: Double {
        max(0, endTime - startTime)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SunnyColors.cloudWhite.ignoresSafeArea()

                VStack(spacing: 18) {
                    WatercolorCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("保留片段", systemImage: "scissors")
                                .font(SunnyFonts.caption(14))
                                .foregroundStyle(SunnyColors.sunnyGray)

                            Text("\(formatSeconds(startTime)) - \(formatSeconds(endTime))")
                                .font(SunnyFonts.title(22))
                                .foregroundStyle(SunnyColors.nightIndigo)

                            Text("保留長度 \(formatSeconds(preservedDuration))")
                                .font(SunnyFonts.caption(14))
                                .foregroundStyle(SunnyColors.sunnyGray)

                            Text("調整左右時會自動播放目前保留片段")
                                .font(SunnyFonts.caption(13))
                                .foregroundStyle(SunnyColors.sunnyGray.opacity(0.85))
                        }
                        .padding(18)
                    }

                    WatercolorCard {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("左側裁掉")
                                        .font(SunnyFonts.caption(14))
                                    Spacer()
                                    Text(formatSeconds(startTime))
                                        .font(SunnyFonts.caption(14))
                                        .foregroundStyle(SunnyColors.sunnyGray)
                                }
                                Slider(
                                    value: Binding(
                                        get: { startTime },
                                        set: { newValue in
                                            startTime = min(newValue, endTime - minimumDuration)
                                        }
                                    ),
                                    in: 0...max(0, sourceDuration - minimumDuration)
                                )
                                .tint(SunnyColors.lanternOrange)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("右側保留到")
                                        .font(SunnyFonts.caption(14))
                                    Spacer()
                                    Text(formatSeconds(endTime))
                                        .font(SunnyFonts.caption(14))
                                        .foregroundStyle(SunnyColors.sunnyGray)
                                }
                                Slider(
                                    value: Binding(
                                        get: { endTime },
                                        set: { newValue in
                                            endTime = max(newValue, startTime + minimumDuration)
                                        }
                                    ),
                                    in: minimumDuration...max(minimumDuration, sourceDuration)
                                )
                                .tint(SunnyColors.forestDeep)
                            }
                        }
                        .padding(18)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(SunnyFonts.caption(13))
                            .foregroundStyle(SunnyColors.lanternOrange)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        if isPreviewingSelection {
                            stopPreviewPlayback()
                        } else {
                            playSelectionPreview()
                        }
                    } label: {
                        Label(isPreviewingSelection ? "停止預聽" : "重播保留片段", systemImage: isPreviewingSelection ? "stop.fill" : "play.fill")
                            .font(SunnyFonts.caption())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(SunnyColors.skyBlue)
                            )
                    }

                    Button {
                        Task { await saveTrim() }
                    } label: {
                        HStack {
                            if isSaving { ProgressView() }
                            Text(isSaving ? "存檔中…" : "儲存裁剪結果")
                        }
                        .font(SunnyFonts.caption())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(SunnyColors.lanternOrange)
                        )
                    }
                    .disabled(isSaving || sourceDuration <= minimumDuration)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("裁剪錄音")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .font(SunnyFonts.caption())
                }
            }
        }
        .task { loadDuration() }
        .onChange(of: startTime) { _, _ in
            scheduleSelectionPreview()
        }
        .onChange(of: endTime) { _, _ in
            scheduleSelectionPreview()
        }
        .onDisappear {
            previewDebounceTask?.cancel()
            previewDebounceTask = nil
            stopPreviewPlayback()
        }
    }

    private func loadDuration() {
        let measured = VoiceClipAudioEditor.measuredDuration(at: clip.recordingsURL)
        sourceDuration = max(measured, clip.duration, minimumDuration)
        startTime = 0
        endTime = sourceDuration
    }

    @MainActor
    private func saveTrim() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        previewDebounceTask?.cancel()
        previewDebounceTask = nil
        stopPreviewPlayback()
        do {
            let newDuration = try await VoiceClipAudioEditor.trim(
                url: clip.recordingsURL,
                startTime: startTime,
                endTime: endTime
            )
            clip.duration = newDuration
            try? modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func scheduleSelectionPreview() {
        previewDebounceTask?.cancel()
        previewDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            playSelectionPreview()
        }
    }

    @MainActor
    private func playSelectionPreview() {
        guard FileManager.default.fileExists(atPath: clip.recordingsURL.path) else { return }
        stopPreviewPlayback()
        errorMessage = nil

        do {
            let player = try AVAudioPlayer(contentsOf: clip.recordingsURL)
            player.prepareToPlay()
            player.currentTime = min(max(0, startTime), max(0, player.duration - minimumDuration))
            player.play()
            previewPlayer = player
            isPreviewingSelection = true

            let duration = min(max(preservedDuration, minimumDuration), max(minimumDuration, player.duration - player.currentTime))
            previewStopTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                stopPreviewPlayback()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func stopPreviewPlayback() {
        previewStopTask?.cancel()
        previewStopTask = nil
        previewPlayer?.stop()
        previewPlayer = nil
        isPreviewingSelection = false
    }
}

// MARK: - Helpers

private enum VoiceClipAudioEditor {
    static func measuredDuration(at url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return 0 }
        return Double(file.length) / sampleRate
    }

    static func trim(url: URL, startTime: TimeInterval, endTime: TimeInterval) async throws -> TimeInterval {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VoiceClipAudioEditorError.fileMissing
        }

        let asset = AVURLAsset(url: url)
        let sourceDuration = measuredDuration(at: url)
        let safeStart = max(0, min(startTime, max(0, sourceDuration - 0.5)))
        let safeEnd = min(max(endTime, safeStart + 0.5), sourceDuration)
        guard safeEnd - safeStart >= 0.5 else {
            throw VoiceClipAudioEditorError.invalidRange
        }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw VoiceClipAudioEditorError.exportUnavailable
        }

        let tempURL = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".m4a")
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: safeStart, preferredTimescale: 600),
            end: CMTime(seconds: safeEnd, preferredTimescale: 600)
        )

        // iOS 18+ async export — replaces the deprecated exportAsynchronously / .status / .error
        // trio and removes the "non-Sendable AVAssetExportSession captured in @Sendable closure"
        // warning (there's no completion closure anymore). timeRange is still honoured; outputURL /
        // outputFileType are now passed as the to:/as: arguments.
        do {
            try await exporter.export(to: tempURL, as: .m4a)
        } catch is CancellationError {
            throw VoiceClipAudioEditorError.cancelled
        } catch {
            throw VoiceClipAudioEditorError.exportFailed
        }

        let fm = FileManager.default
        do {
            _ = try fm.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            try? fm.removeItem(at: tempURL)
            throw error
        }
        return measuredDuration(at: url)
    }
}

private enum VoiceClipAudioEditorError: LocalizedError {
    case fileMissing
    case invalidRange
    case exportUnavailable
    case exportFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            return "找不到要裁剪的錄音檔。"
        case .invalidRange:
            return "裁剪範圍太短，請至少保留 0.5 秒。"
        case .exportUnavailable:
            return "這台裝置目前無法裁剪這個錄音。"
        case .exportFailed:
            return "裁剪失敗，請再試一次。"
        case .cancelled:
            return "裁剪已取消。"
        }
    }
}

private func formatSeconds(_ seconds: Double) -> String {
    let clamped = max(0, seconds)
    let total = Int(clamped.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
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
