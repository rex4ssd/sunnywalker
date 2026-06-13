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

// MARK: - Background ring mode

/// 鬧鐘在「背景 / 鎖屏 / app 被殺」時用哪個機制響鈴。Stored as raw String（SwiftData migration-safe）。
enum AlarmBackgroundMode: String, Codable {
    /// 系統鬧鐘（AlarmKit）：破靜音/專注模式、持續響直到停。**預設**。
    /// 缺點：app 被 force-quit（上滑殺掉）後，app 端無法自動停 → 會一直響、耗電（iOS 平台限制）。
    case alarmKit
    /// Time-Sensitive 通知：響一次（自訂音效 ≤30 秒）後**自動停**、不耗電、可破專注模式。
    /// 缺點：破不了實體靜音開關（要破靜音需 .critical entitlement，需 Apple 審核），
    /// 音效短、較不會吵醒熟睡的孩子。適合「提醒型、錯過也沒嚴重後果」的鬧鐘。
    case notification
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

    /// 自定關鬧鐘口令：除了 SpeechRecognizer 預設詞（「我起床了」等）之外，額外認的關鍵字。
    /// 多個口令可用逗號（, 或 ，）或換行分隔。Optional + default 配合 SwiftData lightweight migration。
    /// 讀取請用 `effectiveCustomPhrases`。
    var customDismissPhrase: String? = nil

    /// 背景/鎖屏/被殺時的響鈴策略。Optional + default nil 配合 SwiftData lightweight migration
    /// （舊資料 nil → 走 `.alarmKit` 預設，行為完全不變）。讀取請用 `effectiveBackgroundMode`。
    var backgroundRingMode: AlarmBackgroundMode? = nil

    /// 溫和提醒模式下是否「切段」：把語音用多顆秒級錯開的通知堆到 ~30 秒（gentle-repeat burst）。
    /// 預設 nil → false：只響一次（單通知、不堆疊），避免通知中心出現一整排「起床囉！」。
    /// 開啟才排 burst（響滿 ~30s，但 iOS 可能幾秒內就把它收掉，不保證響滿）。
    /// Optional + default nil 配合 SwiftData lightweight migration。讀取請用 `effectiveSegmentedBurst`。
    var segmentedBurst: Bool? = nil

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

    /// 背景響鈴策略——nil（舊資料 / 未設定）→ `.alarmKit`（維持原行為）。請一律用這個讀取。
    var effectiveBackgroundMode: AlarmBackgroundMode { backgroundRingMode ?? .alarmKit }

    /// 溫和提醒「切段響滿 30s」是否開啟。nil（舊資料 / 未設）→ false（只響一次、不堆疊通知）。
    var effectiveSegmentedBurst: Bool { segmentedBurst ?? false }

    /// 「貪睡模式 / strict mode」已於 2026-06-10 移除：它原本承諾「一定要開 App 才能關」，但
    /// AlarmKit 系統鬧鐘的實體鍵(音量/側鍵)由 iOS 直接 map 成「停止」，第三方攔不到，承諾無法兌現；
    /// 而真正想要的「貪睡再響直到橫滑」也做不到。所以一律回 false（全 app 走非嚴格路徑：
    /// 鎖屏停止＝直接關、不發 nag）。stored property 與下游程式保留但永遠不會被觸發。
    var effectiveRequireAppToStop: Bool { false }

    /// 把 customDismissPhrase 拆成乾淨的口令陣列（去空白、濾空）。
    var effectiveCustomPhrases: [String] {
        guard let raw = customDismissPhrase else { return [] }
        return raw
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

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
