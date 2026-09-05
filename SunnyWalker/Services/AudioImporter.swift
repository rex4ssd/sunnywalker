// SunnyWalker — AudioImporter.swift  |  Import an external audio file (mp3/wav/…) → m4a VoiceClip source
//
// Lets a parent pick an audio file from Files / iCloud Drive and use it as an alarm ringtone.
// The picked file is converted + trimmed to a short `.m4a` in `Documents/Recordings/<base>.m4a` —
// exactly the shape `AudioRecorder` produces — so the ENTIRE downstream pipeline is reused unchanged:
// VoiceClip list → preview → selectClip → `AlarmSoundExporter.exportLockScreenCAF` → notification /
// AlarmKit / gentle-repeat burst. No new model, no new export path.
//
// ⚠️ DRM-protected audio (Apple Music / iTunes purchases) is NOT importable: `AVAssetExportSession`
//    fails on it, and such items don't surface in the Files picker anyway. We map any failure to a
//    friendly error rather than crashing or writing a half file.

import AVFoundation
import Foundation

/// Result of a successful import. `base` is the UUID stem; the file lives at
/// `Documents/Recordings/<base>.m4a`, mirroring `AudioRecorder`. Caller builds the `VoiceClip`.
struct ImportedClip: Sendable {
    let base: String
    let duration: TimeInterval
    let suggestedName: String   // derived from the source filename, capped per language
}

enum AudioImporter {

    /// Convert + trim a picked audio file into `Documents/Recordings/<base>.m4a` (AAC), capped to the
    /// FIRST `maxSeconds` of the source. Trimming from the start keeps it predictable (v1 — no in-app
    /// trimmer); the lock-screen CAF is further shortened downstream by `exportBundledShortCAF`-style
    /// logic in `AlarmSoundExporter`.
    /// - Parameters:
    ///   - url: a (possibly security-scoped) URL from SwiftUI `.fileImporter`.
    ///   - maxSeconds: hard length cap (`FeatureLimits.maxVoiceClipSeconds`: 5 free / 30 Pro).
    static func importAudioFile(from url: URL, maxSeconds: Double) async throws -> ImportedClip {
        let fm = FileManager.default

        // 1. Security-scoped access. `.fileImporter` URLs need start/stop, and the grant can lapse
        //    quickly — so copy the bytes into our tmp dir up front and work from the local copy.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.isEmpty ? "audio" : url.pathExtension
        let srcCopy = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try? fm.removeItem(at: srcCopy)
        do {
            try fm.copyItem(at: url, to: srcCopy)
        } catch {
            throw AudioImportError.copyFailed
        }
        defer { try? fm.removeItem(at: srcCopy) }

        // 2. Validate it's a usable audio asset and measure its length.
        let asset = AVURLAsset(url: srcCopy)
        let sourceDuration: TimeInterval
        do {
            sourceDuration = CMTimeGetSeconds(try await asset.load(.duration))
        } catch {
            throw AudioImportError.unsupported
        }
        guard sourceDuration.isFinite, sourceDuration > 0 else {
            throw AudioImportError.unsupported
        }

        // 3. Convert + trim to m4a in Documents/Recordings/<base>.m4a (same dir/format as recordings).
        try? fm.createDirectory(at: AppPaths.recordingsDirectory, withIntermediateDirectories: true)
        let base = UUID().uuidString
        let outURL = AppPaths.recordingURL(named: base)

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioImportError.unsupported
        }
        let end = min(sourceDuration, max(0.5, maxSeconds))
        exporter.timeRange = CMTimeRange(
            start: .zero,
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        // iOS 18+ async export — same API `VoiceClipAudioEditor.trim` uses (no deprecated
        // exportAsynchronously, no "non-Sendable AVAssetExportSession in @Sendable closure" warning).
        do {
            try await exporter.export(to: outURL, as: .m4a)
        } catch {
            try? fm.removeItem(at: outURL)
            throw AudioImportError.unsupported   // most commonly DRM-protected or an unsupported codec
        }

        // 4. Measure the actual written duration + derive a default name from the source filename.
        let duration: TimeInterval = {
            guard let af = try? AVAudioFile(forReading: outURL) else { return end }
            let sr = af.processingFormat.sampleRate
            return sr > 0 ? Double(af.length) / sr : end
        }()
        let rawName = url.deletingPathExtension().lastPathComponent
        let maxChars = VoiceClipLimits.maxAutoNameChars
        let suggested = String(rawName.trimmingCharacters(in: .whitespaces).prefix(maxChars))
            .trimmingCharacters(in: .whitespaces)

        return ImportedClip(
            base: base,
            duration: duration,
            suggestedName: suggested.isEmpty ? L("匯入的鈴聲") : suggested
        )
    }
}

enum AudioImportError: LocalizedError {
    case copyFailed
    case unsupported

    // Shown via Text(errorMessage) i.e. Text(String) which is verbatim (non-localized),
    // so localize here with L() against the String Catalog — same pattern as VoiceClipAudioEditorError.
    var errorDescription: String? {
        switch self {
        case .copyFailed:
            return L("無法讀取這個檔案，請再試一次。")
        case .unsupported:
            return L("這個音檔無法匯入（可能受版權保護，或格式不支援）。請改用未受保護的 mp3 / wav 等音檔。")
        }
    }
}
