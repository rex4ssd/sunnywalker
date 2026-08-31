// SunnyWalker — VoiceLibraryView.swift
// Voice-clip library: browse / play / rename / trim / delete / record new clips.
// Also used as the custom-ringtone picker in AlarmEditorView (pass onSelect to enter
// selection mode — checkmark circle on each row picks the clip and dismisses the sheet).
// Max 5 clips × 5 seconds each (free tier). Raise the constants below for paid upgrades.

import SwiftUI
import SwiftData
import AVFoundation
import Speech
import UniformTypeIdentifiers

// MARK: - Upgrade-path limits

/// Thin redirect to the central FeatureLimits so all paid-gated caps live in one place
/// (AppSettings.swift). Pro unlock flips FeatureLimits.isPro and these follow automatically.
enum VoiceClipLimits {
    static var maxCount: Int { FeatureLimits.maxVoiceClips }
    static var maxDurationSeconds: Double { FeatureLimits.maxVoiceClipSeconds }

    /// Max characters kept from a speech-recognised auto-name, per script.
    /// CJK characters carry more meaning each, so the cap is lower than for Latin.
    /// 基準值（家長設定「自動命名加長」關閉時）：中文 8 字／英文 16 字母；開啟＝加倍。
    static let maxAutoNameCharsCJK = 8     // 中文
    static let maxAutoNameCharsLatin = 16  // English

    /// 目前語言的自動命名上限，含家長設定的加長（預設開）。直接讀 UserDefaults——
    /// AudioImporter 在非 MainActor context 也要用，不能經過 @MainActor 的 AppSettings。
    static var maxAutoNameChars: Int {
        let doubled = UserDefaults.standard.object(forKey: "longAutoNames") as? Bool ?? true
        let base = SunnyLocalization.code == "en" ? maxAutoNameCharsLatin : maxAutoNameCharsCJK
        return doubled ? base * 2 : base
    }
}

// MARK: - VoiceLibraryView

struct VoiceLibraryView: View {
    // MARK: - Selection-mode support (optional — default = management-only)
    /// Pass the alarm's current soundFileName so the matching clip shows a checkmark.
    var currentFileName: String = ""
    /// When set, the view acts as a clip picker: tapping the circle button calls this closure
    /// with the exported CAF name + clip info, then dismisses the sheet.
    var onSelect: ((String, SelectedRecordingInfo?) -> Void)? = nil

    private var isSelectionMode: Bool { onSelect != nil }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VoiceClip.createdAt, order: .reverse) private var clips: [VoiceClip]

    @StateObject private var player = AudioPlayer()
    @State private var playingID: UUID?
    @State private var showingRecorder = false
    @State private var showingImporter = false   // 從「檔案」匯入手機內音檔當鈴聲
    @State private var importError: String?       // 匯入失敗（DRM / 格式不支援）→ alert
    @State private var selectedClip: VoiceClip?
    @State private var deleteTarget: VoiceClip?
    @State private var showDeleteConfirm = false

    private var canAddMore: Bool { clips.count < VoiceClipLimits.maxCount }

    // LocalizedStringKey return type — ensures the xcstrings lookup fires instead of verbatim
    // String rendering (same pattern as RingtonePickerSheet.navigationTitle).
    private var navigationTitle: LocalizedStringKey {
        isSelectionMode ? "自定鈴聲(錄音) 🎤" : "錄音管理 🎙️"  // i18n-ignore: var 已明確標 LocalizedStringKey，三元正確查表
    }

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
                        .padding(.bottom, 10)

                    importButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Stop player before dismissing — prevents audio tail when sheet closes.
                    Button(isSelectionMode ? String(localized: "取消") : String(localized: "完成")) { player.stop(); dismiss() }
                        .font(SunnyFonts.caption())
                        .foregroundStyle(isSelectionMode ? SunnyColors.sunnyGray : SunnyColors.forestDeep)
                }
            }
        }
        // Clear the row highlight when playback truly ends — but NOT on pause (isPaused keeps the
        // clip "loaded" so the same row can resume).
        .onReceive(player.$isPlaying) { playing in
            if !playing && !player.isPaused { playingID = nil }
        }
        .sheet(isPresented: $showingRecorder) {
            VoiceClipRecorderSheet { clip in
                modelContext.insert(clip)
                // 從編輯器進來挑鈴聲（selection mode）＝「就是要新鈴聲才進來錄」——
                // 錄完直接設成這顆鬧鐘的鈴聲並關頁，不要再逼家長回清單找剛錄的那條點一次。
                if isSelectionMode { selectClip(clip) }
            }
        }
        // 從「檔案」App / iCloud Drive 匯入音檔（mp3/wav/m4a…）。DRM 保護的歌匯不進來 → 友善錯誤。
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.audio, .mp3, .wav, .aiff, .mpeg4Audio],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("匯入失敗", isPresented: importErrorBinding) {
            Button("好", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
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
                    isPlaying: playingID == clip.id && player.isPlaying,
                    onPlayPause: { playOrPause(clip) },
                    onStop: { stopPlayback() },
                    onSelect: {
                        player.stop()
                        playingID = nil
                        selectedClip = clip
                    },
                    onDelete: { deleteTarget = clip; showDeleteConfirm = true },
                    isSelected: isSelectionMode && isClipSelected(clip),
                    onPickToUse: isSelectionMode ? { selectClip(clip) } : nil
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

    /// Secondary entry: import an audio file from Files instead of recording. Same clip-count pool.
    private var importButton: some View {
        Button {
            showingImporter = true
        } label: {
            Label {
                Text("匯入音檔")
            } icon: {
                Image(systemName: canAddMore ? "square.and.arrow.down" : "lock.circle.fill")
            }
            .font(SunnyFonts.title(16))
            .foregroundStyle(canAddMore ? SunnyColors.skyBlue : SunnyColors.sunnyGray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke((canAddMore ? SunnyColors.skyBlue : SunnyColors.sunnyGray).opacity(0.4), lineWidth: 1)
            )
        }
        .disabled(!canAddMore)
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    let imported = try await AudioImporter.importAudioFile(
                        from: url, maxSeconds: VoiceClipLimits.maxDurationSeconds
                    )
                    let clip = VoiceClip(
                        name: imported.suggestedName,
                        fileName: imported.base + ".m4a",
                        duration: imported.duration
                    )
                    modelContext.insert(clip)
                    try? modelContext.save()
                } catch {
                    importError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Actions

    /// Tap behaviour: ▶ starts this clip; ‖ (already playing this clip) pauses; tapping a paused
    /// clip resumes. Tapping a different clip switches to it. (Long-press → stopPlayback.)
    private func playOrPause(_ clip: VoiceClip) {
        if playingID == clip.id {
            if player.isPlaying { player.pause() }
            else { player.resume() }
        } else {
            player.stop()
            let url = clip.recordingsURL
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            playingID = clip.id
            player.play(url: url, loop: false)
        }
    }

    /// Long-press behaviour: fully stop and clear the row.
    private func stopPlayback() {
        player.stop()
        playingID = nil
    }

    private func deleteClip(_ clip: VoiceClip) {
        if playingID == clip.id { player.stop(); playingID = nil }
        try? FileManager.default.removeItem(at: clip.recordingsURL)
        modelContext.delete(clip)
    }

    // MARK: - Selection-mode helpers

    private func isClipSelected(_ clip: VoiceClip) -> Bool {
        // The alarm stores a CAF filename derived from the clip's base name.
        let base = String(clip.fileName.dropLast(4))  // strip ".m4a"
        return currentFileName.hasPrefix("alarm_\(base)_")
    }

    private func selectClip(_ clip: VoiceClip) {
        player.stop()
        playingID = nil
        let base = String(clip.fileName.dropLast(4))
        if let cafName = AlarmSoundExporter.exportLockScreenCAF(fromRecordingNamed: base) {
            onSelect?(cafName, SelectedRecordingInfo(baseName: base, displayName: clip.name))
        }
        dismiss()
    }
}

// MARK: - VoiceClipRow

private struct VoiceClipRow: View {
    let clip: VoiceClip
    let isPlaying: Bool                 // true = actively playing this clip (not paused/stopped)
    let onPlayPause: () -> Void         // tap: ▶ play · ‖ pause · resume if paused
    let onStop: () -> Void             // long-press: stop
    let onSelect: () -> Void           // opens VoiceClipDetailSheet
    let onDelete: () -> Void
    var isSelected: Bool = false       // true = this clip is the alarm's current ringtone
    var onPickToUse: (() -> Void)? = nil  // non-nil → selection mode; tap to choose & dismiss

    var body: some View {
        HStack(spacing: 14) {
            // Tap = play / pause (resume); long-press = stop. Plain Image + gestures (not a Button)
            // so the tap and the long-press can coexist without the Button swallowing the press.
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(isPlaying ? SunnyColors.lanternOrange : SunnyColors.leafFresh)
                .symbolEffect(.pulse, isActive: isPlaying)
                .contentShape(Circle())
                .onTapGesture { onPlayPause() }
                .onLongPressGesture(minimumDuration: 0.45) { onStop() }
                .accessibilityLabel(Text(isPlaying ? String(localized: "暫停") : String(localized: "播放")))
                .accessibilityHint(Text("長按停止"))

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

            if let onPickToUse {
                // Selection mode: delete + pick-circle
                // 編輯詳情仍可透過點擊 name 區進入；右側保留刪除 + 選取圓圈。
                HStack(spacing: 18) {
                    Button(action: onDelete) {
                        Image(systemName: "trash.circle")
                            .font(.title)
                            .foregroundStyle(SunnyColors.lanternOrange.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("刪除"))

                    Button(action: onPickToUse) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title)
                            .foregroundStyle(isSelected ? SunnyColors.leafFresh : SunnyColors.sunnyGray.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSelected ? Text("已選取") : Text("選取"))
                }
            } else {
                // Management mode: edit + delete（原有行為，兩顆 icon 留 22pt 間隔）
                HStack(spacing: 22) {
                    Button(action: onSelect) {
                        Image(systemName: "square.and.pencil")
                            .font(.title2)
                            .foregroundStyle(SunnyColors.forestDeep.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("編輯"))

                    Button(action: onDelete) {
                        Image(systemName: "trash.circle")
                            .font(.title)
                            .foregroundStyle(SunnyColors.lanternOrange.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("刪除"))
                }
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
    @State private var isTranscribing = false
    @State private var speechTask: SFSpeechRecognitionTask?

    enum RecorderPhase { case ready, recording, done }

    private var maxSeconds: Int { Int(VoiceClipLimits.maxDurationSeconds) }

    var body: some View {
        NavigationStack {
            ZStack {
                SunnyColors.cloudWhite.ignoresSafeArea()

                VStack(spacing: 22) {
                    Spacer(minLength: 8)
                    MascotView()
                    headline
                    recordControl
                    if phase == .recording { countdownLabel }
                    if phase == .done {
                        nameCard
                        actionRow
                    }
                    if let msg = errorMessage {
                        Text(msg)
                            .font(SunnyFonts.caption(13))
                            .foregroundStyle(SunnyColors.lanternOrange)
                            .multilineTextAlignment(.center)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 32)
                .animation(.easeInOut(duration: 0.25), value: phase)
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
    //
    // One unified page: a single stable column (mascot → headline → record control →
    // inline name/preview/save). The record button stays put across phases; the countdown
    // ring wraps the button instead of being a separate element; after recording the big
    // mic becomes a small "重新錄音 / Record again" pill so the recording step never feels
    // like a different screen.

    @ViewBuilder
    private var headline: some View {
        switch phase {
        case .ready:
            Text("準備好了嗎？")
                .font(SunnyFonts.title(22))
                .foregroundStyle(SunnyColors.nightIndigo)
        case .recording:
            Text("錄音中…")
                .font(SunnyFonts.title(22))
                .foregroundStyle(SunnyColors.lanternOrange)
        case .done:
            Text("錄好了！✅")
                .font(SunnyFonts.title(22))
                .foregroundStyle(SunnyColors.forestDeep)
        }
    }

    /// Primary record/stop control. The countdown ring is drawn around the button while
    /// recording; once done the control collapses into a compact "record again" pill.
    @ViewBuilder
    private var recordControl: some View {
        if phase == .done {
            Button { reRecord() } label: {
                Label("重新錄音", systemImage: "arrow.counterclockwise")
                    .font(SunnyFonts.caption())
                    .foregroundStyle(SunnyColors.sunnyGray)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(SunnyColors.sunnyGray.opacity(0.12)))
            }
            .buttonStyle(.plain)
        } else {
            Button { handleRecordTap() } label: {
                ZStack {
                    if phase == .recording {
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
                    }

                    Circle()
                        .fill(
                            phase == .recording
                                ? SunnyColors.lanternOrange
                                : SunnyColors.lanternOrange.opacity(0.12)
                        )
                        .frame(width: 92, height: 92)
                        // 共用件的即時音量（tap RMS）→ 現成錄音圓鈕隨聲音微縮放。
                        .scaleEffect(phase == .recording ? 1 + CGFloat(min(recorder.level, 1)) * 0.12 : 1)
                        .animation(.linear(duration: 0.1), value: recorder.level)
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
                .frame(width: 108, height: 108)
            }
            .animation(.easeInOut(duration: 0.2), value: phase == .recording)
        }
    }

    /// Big remaining-seconds readout shown under the ring while recording (number only —
    /// language-neutral, so no extra localized string needed).
    private var countdownLabel: some View {
        Text("\(countdown)")
            .font(SunnyFonts.clock(30))
            .foregroundStyle(SunnyColors.lanternOrange)
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.3), value: countdown)
    }

    /// Name field + manual auto-name (speech) button, revealed inline after recording.
    private var nameCard: some View {
        VStack(spacing: 12) {
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

            Group {
                if isTranscribing {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.75)
                        Text("辨識中…")
                            .font(.caption)
                            .foregroundStyle(SunnyColors.sunnyGray)
                    }
                } else {
                    Button {
                        let url = recordingURL(base: recordedBase)
                        let current = clipName.trimmingCharacters(in: .whitespaces)
                        let fallback = current.isEmpty ? L("我的錄音") : current
                        transcribeForName(url: url, fallback: fallback)
                    } label: {
                        // "辨識錄音內容" / en "Name from voice" — both localized in the
                        // String Catalog so the English UI never shows Chinese (App Review).
                        Label("辨識錄音內容", systemImage: "sparkles")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(SunnyColors.leafFresh)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(SunnyColors.leafFresh.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(recordedBase.isEmpty)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isTranscribing)
        }
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
                    player.isPlaying ? String(localized: "停止") : String(localized: "試聽"),
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

    /// Discard the just-recorded take and return to the ready state so the user can record
    /// again in place (keeps the whole flow on one page). Deletes the orphaned audio file.
    private func reRecord() {
        player.stop()
        speechTask?.cancel(); speechTask = nil
        isTranscribing = false
        // 剛按完「停止」馬上按「重新錄音」時，stop→finalize→改名可能還沒落地 —
        // helper 會等它完成再刪，否則刪到還不存在的檔、縫合完成後孤兒檔又冒回來。
        stopAndDiscardTake(base: recordedBase)
        recordedBase = ""
        recordedDuration = 0
        clipName = ""
        errorMessage = nil
        countdown = maxSeconds
        phase = .ready
    }

    private func startRecording() {
        errorMessage = nil
        let base = UUID().uuidString
        Task {
            do {
                try await recorder.start(named: base)  // saves to Documents/Recordings/<base>.m4a
                // start 可能被 await 期間的 stop 靜默取消（✕ 取消關頁）— 沒真的開錄就不進
                // .recording，也不啟動倒數（否則倒數到 0 會自動存下一筆沒有檔案的幽靈 clip）。
                guard recorder.isRecording else { return }
                recordedBase = base
                phase = .recording
                countdown = maxSeconds
                beginCountdown()
            } catch {
                errorMessage = L("recording_launch_failed %@", error.localizedDescription)
            }
        }
    }

    /// - Parameter autoSaved: true when the time cap fired (not a manual stop). In that case the
    ///   take is persisted immediately so it can never be lost just because the parent didn't reach
    ///   the 「儲存」button — the recording is saved with the default name and can be renamed later.
    private func stopRecording(autoSaved: Bool = false) {
        countdownTimer?.invalidate(); countdownTimer = nil
        phase = .done
        Task {
            // 共用件 stop 後要 finalize（縫合分段）＋改名，<base>.m4a 才落地 —
            // 時長量測與自動存檔都等它完成。
            let url = await recorder.stop() ?? recordingURL(base: recordedBase)

            // Measure actual duration from the written file
            if let audioFile = try? AVAudioFile(forReading: url) {
                let sampleRate = audioFile.processingFormat.sampleRate
                recordedDuration = sampleRate > 0 ? Double(audioFile.length) / sampleRate : 0
            }

            // Set default name; user can tap ✨ to auto-name from voice content.
            if clipName.trimmingCharacters(in: .whitespaces).isEmpty { clipName = L("我的錄音") }

            if autoSaved { saveClip() }   // cap reached → save by itself, never drop the take
        }
    }

    /// Transcribe `url` using SFSpeechURLRecognitionRequest (on-device, no network).
    /// Sets `clipName` to the first 7 characters of the result, or keeps `fallback`.
    private func transcribeForName(url: URL, fallback: String) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let localeId = SunnyLocalization.code == "en" ? "en-US" : "zh-TW"
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId)),
              recognizer.isAvailable else { return }

        isTranscribing = true
        speechTask?.cancel()

        let request = SFSpeechURLRecognitionRequest(url: url)
        // On-device only when supported — preserves privacy.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.shouldReportPartialResults = false

        // Safety timeout: give up after 5 s if Speech never fires final result.
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                guard self.isTranscribing else { return }
                self.speechTask?.cancel(); self.speechTask = nil
                self.isTranscribing = false
                if self.clipName.isEmpty { self.clipName = fallback }
            }
        }

        speechTask = recognizer.recognitionTask(with: request) { result, error in
            guard let result, result.isFinal else {
                if error != nil {
                    Task { @MainActor in
                        timeoutTask.cancel()
                        self.speechTask = nil
                        self.isTranscribing = false
                        if self.clipName.isEmpty { self.clipName = fallback }
                    }
                }
                return
            }
            let text = result.bestTranscription.formattedString
            // Cap the auto-name length per language（家長設定可加長，見 VoiceClipLimits）。
            let maxChars = VoiceClipLimits.maxAutoNameChars
            let name = String(
                text.trimmingCharacters(in: .whitespaces).prefix(maxChars)
            ).trimmingCharacters(in: .whitespaces)
            Task { @MainActor in
                timeoutTask.cancel()
                self.speechTask = nil
                self.isTranscribing = false
                self.clipName = name.isEmpty ? fallback : name
            }
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
                    self.stopRecording(autoSaved: true)   // 時間到 → 自動存檔，不遺失
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
        player.stop()
        speechTask?.cancel(); speechTask = nil
        stopAndDiscardTake(base: recordedBase)
        dismiss()
    }

    private func recordingURL(base: String) -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings/\(base).m4a")
    }
}

private extension VoiceClipRecorderSheet {
    /// 停止錄音並丟棄這次的 take 檔（✕ 取消、重新錄音共用）。
    /// stop 無條件呼叫：即使 base 還沒設（start 仍懸在 await），也要讓那筆 start 落敗。
    /// 刪檔要等共用件 stop→finalize→改名落地之後（recorder.stop() 冪等，回進行中同一筆）——
    /// 否則刪了個還不存在的檔、縫合完成後又冒回來。
    func stopAndDiscardTake(base: String) {
        Task {
            _ = await recorder.stop()
            guard !base.isEmpty else { return }
            try? FileManager.default.removeItem(at: recordingURL(base: base))
        }
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
                                    Label(player.isPlaying ? String(localized: "停止試聽") : String(localized: "播放錄音"), systemImage: player.isPlaying ? "pause.fill" : "play.fill")
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
            // `title` is a String variable, so it would hit Label's verbatim (non-localized)
            // overload — wrap in LocalizedStringKey so the catalog translation is used.
            Label {
                Text(LocalizedStringKey(title))
            } icon: {
                Image(systemName: icon)
            }
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
                        Label(isPreviewingSelection ? String(localized: "停止預聽") : String(localized: "重播保留片段"), systemImage: isPreviewingSelection ? "stop.fill" : "play.fill")
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
                            Text(isSaving ? String(localized: "存檔中…") : String(localized: "儲存裁剪結果"))
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
        // These are shown via Text(errorMessage), i.e. Text(String) which is verbatim
        // (non-localized), so localize here with L() against the String Catalog.
        switch self {
        case .fileMissing:
            return L("找不到要裁剪的錄音檔。")
        case .invalidRange:
            return L("裁剪範圍太短，請至少保留 0.5 秒。")
        case .exportUnavailable:
            return L("這台裝置目前無法裁剪這個錄音。")
        case .exportFailed:
            return L("裁剪失敗，請再試一次。")
        case .cancelled:
            return L("裁剪已取消。")
        }
    }
}

private func formatSeconds(_ seconds: Double) -> String { seconds.minSecString }

// MARK: - Previews

#Preview("Library — management (empty)") {
    VoiceLibraryView()
        .modelContainer(for: VoiceClip.self, inMemory: true)
}

#Preview("Library — picker (selection mode)") {
    VoiceLibraryView(currentFileName: "alarm_my-recording_12345678.caf") { _, _ in }
        .modelContainer(for: VoiceClip.self, inMemory: true)
}

#Preview("Recorder") {
    VoiceClipRecorderSheet { _ in }
        .modelContainer(for: VoiceClip.self, inMemory: true)
}
