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
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings")
            .appendingPathComponent(fileName)
    }

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
        let s = Int(duration)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
