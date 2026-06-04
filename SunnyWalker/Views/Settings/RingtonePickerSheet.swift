// SunnyWalker — RingtonePickerSheet.swift
// Lets the parent choose a ringtone for an alarm:
//   • Section 1: bundled app sounds
//   • Section 2: VoiceClip recordings from the library
//
// On selection the sheet calls onSelect(soundFileName) where soundFileName is a
// CAF / WAV file name that AlarmScheduler / AlarmKit can reference directly.

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

private let bundledSounds: [BundledSound] = [
    BundledSound(fileName: "sunny_wake.caf",  displayName: "陽光起床", emoji: "☀️"),
    BundledSound(fileName: "leaf_rustle.caf", displayName: "樹葉沙沙", emoji: "🍃"),
]

// MARK: - RingtonePickerSheet

struct RingtonePickerSheet: View {
    /// Current selection passed in so the picker can show a checkmark.
    let currentFileName: String
    /// Called with the chosen sound file name when the user taps an item.
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \VoiceClip.createdAt, order: .reverse) private var clips: [VoiceClip]
    @StateObject private var player = AudioPlayer()
    @State private var previewingFile: String?

    var body: some View {
        NavigationStack {
            ZStack {
                SunnyColors.cloudWhite.ignoresSafeArea()
                List {
                    bundledSection
                    if !clips.isEmpty { recordingSection }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("選擇鈴聲 🎵")
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
    }

    // MARK: - Sections

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
                        onSelect(sound.fileName)
                        dismiss()
                    }
                )
                .listRowBackground(Color.white.opacity(0.75))
            }
        }
    }

    private var recordingSection: some View {
        Section(header: Text("我的錄音").font(SunnyFonts.caption(13))) {
            ForEach(clips) { clip in
                RingtoneClipRow(
                    clip: clip,
                    isSelected: isClipSelected(clip),
                    isPreviewing: previewingFile == clip.fileName,
                    onPreview: { toggleClipPreview(clip) },
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
            onSelect(cafName)
        }
        dismiss()
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
    RingtonePickerSheet(currentFileName: "sunny_wake.caf") { _ in }
        .modelContainer(for: VoiceClip.self, inMemory: true)
}
