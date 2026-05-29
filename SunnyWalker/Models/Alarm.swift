// SunnyWalker — Alarm.swift  |  Day 1  |  SwiftData alarm model

import SwiftData
import Foundation

@Model
final class Alarm {
    @Attribute(.unique) var id: UUID
    var label: String
    var hour: Int
    var minute: Int
    var weekdays: [Int]       // 1 = Sunday … 7 = Saturday
    var isEnabled: Bool
    var recordingName: String
    var createdAt: Date

    init(label: String, hour: Int, minute: Int, recordingName: String = "") {
        self.id = UUID()
        self.label = label
        self.hour = hour
        self.minute = minute
        self.weekdays = [2, 3, 4, 5, 6]  // Mon–Fri by default
        self.isEnabled = true
        self.recordingName = recordingName
        self.createdAt = .now
    }

    var timeString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var weekdaySymbols: [String] {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        return weekdays.compactMap { index in
            guard index >= 1, index <= 7 else { return nil }
            return symbols[index - 1]
        }
    }
}
