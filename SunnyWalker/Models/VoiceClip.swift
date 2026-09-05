// SunnyWalker — VoiceClip.swift  |  Day 1  |  parent-recorded audio clip metadata

import SwiftData
import Foundation

@Model
final class VoiceClip {
    @Attribute(.unique) var id: UUID
    var name: String         // display name, e.g. "媽媽的早安"
    var fileName: String     // stored in Documents/Recordings/, e.g. "morning_mom.m4a"
    var duration: TimeInterval
    var createdAt: Date

    init(name: String, fileName: String, duration: TimeInterval = 0) {
        self.id = UUID()
        self.name = name
        self.fileName = fileName
        self.duration = duration
        self.createdAt = .now
    }

    var recordingsURL: URL {
        AppPaths.recordingsDirectory.appendingPathComponent(fileName)
    }

    /// `fileName` 去掉副檔名（錄音／匯出流程都以這個 base 為鍵）。
    var baseName: String { (fileName as NSString).deletingPathExtension }

    var fileSizeBytes: Int64 {
        let values = try? recordingsURL.resourceValues(forKeys: [.fileSizeKey])
        let size = values?.fileSize ?? 0
        return Int64(size)
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    var formattedDuration: String {
        guard duration > 0 else { return "--:--" }
        return duration.minSecString
    }
}

// MARK: - 時長格式（全 app 唯一一份）

extension TimeInterval {
    /// 秒數 → `分:秒`（例 87 → "1:27"）。純數字格式，免進字串目錄。
    ///
    /// ⚠️ 全 app 只留這一份：先前錄音頁/語音庫/裁剪各自帶一份，且捨入方式不同
    /// （floor vs round）——同一段 4.7s 錄音在語音庫顯示 0:04、錄音頁顯示 0:05。
    /// 一律四捨五入（負值夾到 0）。
    var minSecString: String {
        let total = Int(Swift.max(0, self).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
