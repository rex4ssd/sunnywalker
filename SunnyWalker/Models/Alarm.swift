// SunnyWalker — Alarm.swift  |  Day 17  |  taskType optional (SwiftData migration safe)

import SwiftData
import Foundation

// MARK: - Task type

/// How the child dismisses the alarm after the AlarmKit alert fires.
/// Stored as a raw String in SwiftData — adding new cases is non-breaking.
enum AlarmTaskType: String, Codable {
    /// Child must say a preset phrase that is matched from speech-to-text. Default.
    case voice
    /// Child taps the button only — no speech recognition. Good for young toddlers.
    case button
    /// (Future P5) Child solves a simple math problem.
    case math
}

// MARK: - Alarm model

@Model
final class Alarm {
    @Attribute(.unique) var id: UUID
    var label: String
    var hour: Int
    var minute: Int
    var weekdays: [Int]           // 1 = Sunday … 7 = Saturday
    var isEnabled: Bool
    var recordingName: String
    var recordingDisplayName: String?
    var soundFileName: String
    var createdAt: Date

    /// Optional so SwiftData lightweight migration works on existing rows.
    /// Use `effectiveTaskType` everywhere in the UI — never access this directly.
    var taskType: AlarmTaskType?

    /// "貪睡模式" / strict mode: when true, dismissing the notification (tapping ✕) does NOT stop
    /// the alarm — it keeps nagging (repeated notifications) until the child opens the app and
    /// completes the wake task. Optional for SwiftData lightweight migration on existing rows.
    /// Use `effectiveRequireAppToStop` — never read this directly.
    var requireAppToStop: Bool?

    init(label: String, hour: Int, minute: Int, recordingName: String = "",
         taskType: AlarmTaskType = .voice) {
        self.id = UUID()
        self.label = label
        self.hour = hour
        self.minute = minute
        self.weekdays = [2, 3, 4, 5, 6]  // Mon–Fri by default
        self.isEnabled = true
        self.recordingName = recordingName
        self.recordingDisplayName = nil
        self.soundFileName = "sunny_wake.caf"
        self.createdAt = .now
        self.taskType = taskType
        self.requireAppToStop = false
    }

    /// Always resolves to a concrete value — nil (pre-Day-16 rows) → `.voice`.
    var effectiveTaskType: AlarmTaskType { taskType ?? .voice }

    /// nil (rows created before strict mode existed) → false.
    var effectiveRequireAppToStop: Bool { requireAppToStop ?? false }

    var effectiveRecordingDisplayName: String {
        let trimmed = recordingDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? recordingName : trimmed
    }

    /// Always 24-hour (used internally / for scheduling).
    var timeString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Display string that respects the user's 12h/24h preference.
    func formattedTime(use24h: Bool) -> String {
        if use24h {
            return String(format: "%02d:%02d", hour, minute)
        } else {
            let h12 = hour % 12 == 0 ? 12 : hour % 12
            let period = hour < 12 ? "AM" : "PM"
            return String(format: "%d:%02d %@", h12, minute, period)
        }
    }

    var weekdaySymbols: [String] {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        return weekdays.compactMap { index in
            guard index >= 1, index <= 7 else { return nil }
            return L(symbols[index - 1])   // localized: 日→S, 一→M, … (Localizable.xcstrings)
        }
    }
}
