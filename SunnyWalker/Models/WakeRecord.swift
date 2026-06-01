// SunnyWalker — WakeRecord.swift  |  Day 21  |  P5 wake history log

import SwiftData
import Foundation

/// Persisted each time a child successfully wakes up and dismisses an alarm.
/// Used by the parent to see wake history and trends.
@Model
final class WakeRecord {
    @Attribute(.unique) var id: UUID
    /// The alarm that fired.
    var alarmID: UUID
    /// Label of the alarm at fire time (snapshot — in case alarm is later edited/deleted).
    var alarmLabel: String
    /// When AlarmRingView was first presented (alarm fire time).
    var firedAt: Date
    /// When the child tapped dismiss / voice-matched (wake time).
    var wokeAt: Date
    /// How the child dismissed — mirrors AlarmTaskType raw value.
    var dismissMethod: String    // "voice" | "button" | "fallback"

    init(alarmID: UUID, alarmLabel: String, firedAt: Date,
         wokeAt: Date = .now, dismissMethod: String = "voice") {
        self.id = UUID()
        self.alarmID = alarmID
        self.alarmLabel = alarmLabel
        self.firedAt = firedAt
        self.wokeAt = wokeAt
        self.dismissMethod = dismissMethod
    }

    /// Seconds between alarm fire and child waking up.
    var responseSeconds: Int {
        max(0, Int(wokeAt.timeIntervalSince(firedAt)))
    }

    var responseFormatted: String {
        let s = responseSeconds
        if s < 60 { return L("response_seconds %lld", s) }
        return L("response_minutes %1$lld %2$lld", s / 60, s % 60)
    }
}
