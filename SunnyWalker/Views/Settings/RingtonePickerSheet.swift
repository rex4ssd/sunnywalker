// SunnyWalker — RingtonePickerSheet.swift
// Lets the parent choose a ringtone for an alarm.
// mode .bundled  → only built-in sounds
// mode .custom   → only self-recorded VoiceClips
// mode .all      → both sections (legacy / preview)
//
// On selection the sheet calls onSelect(soundFileName, SelectedRecordingInfo?) where
// soundFileName is a CAF / WAV file name that AlarmScheduler / AlarmKit can reference.

import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Bundled sound descriptors

struct BundledSound: Identifiable {
    let id = UUID()
    let fileName: String   // e.g. "sunny_wake.caf"
    let displayName: String
    let emoji: String
}

struct SelectedRecordingInfo {
    let baseName: String
    let displayName: String
}

// MARK: - Picker mode

enum RingtonePickerMode {
    /// Show only bundled app sounds.
    case bundled
    /// Show only self-recorded VoiceClips.
    case custom
    /// Show both sections (for backwards compatibility / previews).
    case all
}

private let bundledSounds: [BundledSound] = [
    BundledSound(fileName: "sunny_wake.caf",  displayName: "陽光起床", emoji: "☀️"),
    BundledSound(fileName: "leaf_rustle.caf", displayName: "樹葉沙沙", emoji: "🍃"),
]

// MARK: - RingtonePickerSheet

struct RingtonePickerSheet: View {
    /// Current selection passed in so the picker can show a checkmark.
    let currentFileName: String
    /// Which section(s) to show.
    var mode: RingtonePickerMode = .all
    /// Called with the chosen sound file name, plus the recording base name when using a custom clip.
    let onSelect: (String, SelectedRecordingInfo?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VoiceClip.createdAt, order: .reverse) private var clips: [VoiceClip]
    @StateObject private var player = AudioPlayer()
    @State private var previewingFile: String?
    @State private var renamingClip: VoiceClip?
    @State private var renameDraft = ""
    @State private var showingRecorder = false   // 自定鈴聲頁直接新增錄音（復用 VoiceClipRecorderSheet）

    var body: some View {
        NavigationStack {
            ZStack {
                SunnyColors.cloudWhite.ignoresSafeArea()
                List {
                    if mode == .bundled || mode == .all {
                        bundledSection
                    }
                    if (mode == .custom || mode == .all), !clips.isEmpty {
                        recordingSection
                    }
                    if mode == .custom && clips.isEmpty {
                        emptyCustomSection
                    }
                    // 「新增錄音」— 自定鈴聲頁直接錄，錄完 @Query 自動刷新顯示在上面清單
                    if mode == .custom || mode == .all {
                        addRecordingSection
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { player.stop(); dismiss() }
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.sunnyGray)
                }
            }
        }
        .onReceive(player.$isPlaying) { playing in
            if !playing { previewingFile = nil }
        }
        .sheet(isPresented: $showingRecorder) {
            // 復用 settings「錄音管理」的錄音 sheet；存好的 clip insert 進 context 後
            // @Query(clips) 立即更新 → 新錄音馬上出現在自定鈴聲清單。
            VoiceClipRecorderSheet { clip in
                modelContext.insert(clip)
            }
        }
        .alert("重新命名自錄鈴聲", isPresented: renameAlertBinding) {
            TextField("自錄鈴聲名稱", text: $renameDraft)
            Button("取消", role: .cancel) {
                renamingClip = nil
                renameDraft = ""
            }
            Button("儲存") {
                saveRename()
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("改成你比較容易辨認的名字")
        }
    }

    // MARK: - Helpers

    // LocalizedStringKey（非 String）：.navigationTitle(String) 是 verbatim 不會翻譯，
    // 必須回 LocalizedStringKey 才會查 xcstrings 在英文版顯示英文。
    private var navigationTitle: LocalizedStringKey {
        switch mode {
        case .bundled: return "內建鈴聲 🎵"
        case .custom:  return "自定鈴聲(錄音) 🎤"
        case .all:     return "選擇鈴聲 🎵"
        }
    }

    // MARK: - Sections

    private var emptyCustomSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "mic.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(SunnyColors.sunnyGray.opacity(0.5))
                    Text("還沒有自錄鈴聲")
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.sunnyGray)
                    Text("點下方「新增錄音」錄一段給孩子的鈴聲")
                        .font(SunnyFonts.caption(13))
                        .foregroundStyle(SunnyColors.sunnyGray.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(.vertical, 24)
            .listRowBackground(Color.clear)
        }
    }

    private var bundledSection: some View {
        Section(header: Text("內建音效").font(SunnyFonts.caption(13))) {
            ForEach(bundledSounds) { sound in
                RingtoneBundledRow(
                    sound: sound,
                    isSelected: currentFileName == sound.fileName,
                    isPreviewing: previewingFile == sound.fileName,
                    onPreview: { toggleBundledPreview(sound) },
                    onSelect: {
                        player.stop()
                        onSelect(sound.fileName, nil)
                        dismiss()
                    }
                )
                .listRowBackground(Color.white.opacity(0.75))
            }
        }
    }

    private var canAddMoreClips: Bool { clips.count < VoiceClipLimits.maxCount }

    private var addRecordingSection: some View {
        Section {
            Button {
                showingRecorder = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: canAddMoreClips ? "mic.badge.plus" : "lock.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(canAddMoreClips ? SunnyColors.lanternOrange : SunnyColors.sunnyGray)
                    if canAddMoreClips {
                        Text("新增錄音")
                            .font(SunnyFonts.title(16))
                            .foregroundStyle(SunnyColors.nightIndigo)
                    } else {
                        Text("clips_limit_reached \(VoiceClipLimits.maxCount)")
                            .font(SunnyFonts.caption())
                            .foregroundStyle(SunnyColors.sunnyGray)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canAddMoreClips)
            .listRowBackground(Color.white.opacity(0.75))
        }
    }

    private var recordingSection: some View {
        Section(header: Text("自錄鈴聲").font(SunnyFonts.caption(13))) {
            ForEach(clips) { clip in
                RingtoneClipRow(
                    clip: clip,
                    isSelected: isClipSelected(clip),
                    isPreviewing: previewingFile == clip.fileName,
                    onPreview: { toggleClipPreview(clip) },
                    onRename: { beginRename(clip) },
                    onSelect: { selectClip(clip) }
                )
                .listRowBackground(Color.white.opacity(0.75))
            }
        }
    }

    // MARK: - Logic

    private func isClipSelected(_ clip: VoiceClip) -> Bool {
        // The alarm stores a CAF filename derived from the clip's base name.
        // Check whether current sound was exported from this clip.
        let base = String(clip.fileName.dropLast(4))  // strip ".m4a"
        return currentFileName.hasPrefix("alarm_\(base)_")
    }

    private func toggleBundledPreview(_ sound: BundledSound) {
        if previewingFile == sound.fileName {
            player.stop(); previewingFile = nil; return
        }
        player.stop()
        guard let url = Bundle.main.url(forResource: sound.fileName, withExtension: nil) else { return }
        previewingFile = sound.fileName
        player.play(url: url, loop: false)
    }

    private func toggleClipPreview(_ clip: VoiceClip) {
        if previewingFile == clip.fileName {
            player.stop(); previewingFile = nil; return
        }
        player.stop()
        let url = clip.recordingsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        previewingFile = clip.fileName
        player.play(url: url, loop: false)
    }

    private func selectClip(_ clip: VoiceClip) {
        player.stop()
        // Export m4a → CAF for AlarmKit / UNNotification lock-screen sound.
        let base = String(clip.fileName.dropLast(4))
        if let cafName = AlarmSoundExporter.exportLockScreenCAF(fromRecordingNamed: base) {
            onSelect(cafName, SelectedRecordingInfo(baseName: base, displayName: clip.name))
        }
        dismiss()
    }

    private func beginRename(_ clip: VoiceClip) {
        renamingClip = clip
        renameDraft = clip.name
    }

    private func saveRename() {
        guard let clip = renamingClip else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        clip.name = trimmed
        try? modelContext.save()
        if isClipSelected(clip) {
            let base = String(clip.fileName.dropLast(4))
            onSelect(currentFileName, SelectedRecordingInfo(baseName: base, displayName: trimmed))
        }
        renamingClip = nil
        renameDraft = ""
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingClip != nil },
            set: { if !$0 { renamingClip = nil; renameDraft = "" } }
        )
    }
}

// MARK: - Row: bundled sound

private struct RingtoneBundledRow: View {
    let sound: BundledSound
    let isSelected: Bool
    let isPreviewing: Bool
    let onPreview: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Preview toggle
            Button(action: onPreview) {
                Image(systemName: isPreviewing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(isPreviewing ? SunnyColors.lanternOrange : SunnyColors.skyBlue)
                    .symbolEffect(.pulse, isActive: isPreviewing)
            }
            .buttonStyle(.plain)

            // Text concatenation preserves localization for each segment
            (Text(sound.emoji + " ") + Text(LocalizedStringKey(sound.displayName)))
                .font(SunnyFonts.title(16))
                .foregroundStyle(SunnyColors.nightIndigo)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SunnyColors.leafFresh)
                    .font(.system(size: 22))
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

// MARK: - Row: voice clip

private struct RingtoneClipRow: View {
    let clip: VoiceClip
    let isSelected: Bool
    let isPreviewing: Bool
    let onPreview: () -> Void
    let onRename: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onPreview) {
                Image(systemName: isPreviewing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(isPreviewing ? SunnyColors.lanternOrange : SunnyColors.leafFresh)
                    .symbolEffect(.pulse, isActive: isPreviewing)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text("🎤 " + clip.name)
                    .font(SunnyFonts.title(16))
                    .foregroundStyle(SunnyColors.nightIndigo)
                    .lineLimit(1)
                Text(clip.formattedDuration)
                    .font(SunnyFonts.caption(12))
                    .foregroundStyle(SunnyColors.sunnyGray)
            }

            Spacer()

            Button(action: onRename) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(SunnyColors.skyBlue)
            }
            .buttonStyle(.plain)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SunnyColors.leafFresh)
                    .font(.system(size: 22))
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

#Preview {
    RingtonePickerSheet(currentFileName: "sunny_wake.caf") { _, _ in }
        .modelContainer(for: VoiceClip.self, inMemory: true)
}
