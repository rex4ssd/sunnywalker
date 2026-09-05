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

// MARK: - Chime voice

/// 報時用的 iOS 內建人聲性別（AVSpeechSynthesisVoice.gender）。Stored as raw String（migration-safe）。
/// 該語言沒有對應性別的語音時，ChimeSoundComposer 退回該語言的預設語音，不會無聲。
enum ChimeVoiceGender: String, Codable, CaseIterable, Identifiable {
    case female
    case male

    var id: String { rawValue }

    /// 給 UI 的在地化 key（Localizable.xcstrings）。
    var labelKey: String {
        switch self {
        case .female: return "chime_voice_female"
        case .male:   return "chime_voice_male"
        }
    }
}

// MARK: - Todo icon

/// 待辦提醒在主頁吉祥物旁顯示的小圖示。家長每則待辦自己挑一個。Stored as raw String（migration-safe）。
enum TodoIcon: String, CaseIterable, Identifiable, Codable {
    case balloon
    case star
    case heart
    case gift
    case sun

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .balloon: return "balloon.fill"
        case .star:    return "star.fill"
        case .heart:   return "heart.fill"
        case .gift:    return "gift.fill"
        case .sun:     return "sun.max.fill"
        }
    }

    var emoji: String {
        switch self {
        case .balloon: return "🎈"
        case .star:    return "⭐️"
        case .heart:   return "❤️"
        case .gift:    return "🎁"
        case .sun:     return "🌞"
        }
    }
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

    /// 多人鬧鐘的群組索引（0 = 群組 A／預設、1 = B … 4 = E）。
    /// 群組功能由家長在設定頁開關（AppSettings.groupEnabled / groupCount / groupNames）；
    /// 未啟用時所有鬧鐘都視為群組 A。Optional + default nil 配合 SwiftData lightweight migration
    /// （舊資料 nil → 群組 A，行為完全不變）。讀取請一律用 `effectiveGroupIndex`。
    var groupIndex: Int? = nil

    /// 報時次數：這顆鬧鐘屬於「報時群組」時，時間到要用系統語音念出時刻幾次（例：07:00、times=2 ＝
    /// 早上七點報兩次）。nil（一般鬧鐘 / 舊資料）→ 走原本的鈴聲。Optional + default nil 配合
    /// SwiftData lightweight migration。是否為報時鬧鐘請看 `isChimeAlarm`，次數請讀 `effectiveChimeCount`。
    var chimeCount: Int? = nil

    /// 區間報時的「迄」時刻（時／分）。nil（舊資料 / 單一時刻報時）→ 只報 `hour:minute` 一次。
    /// 「起」就是鬧鐘本身的 hour/minute。Optional + default nil 配合 SwiftData lightweight migration。
    var chimeEndHour: Int? = nil
    var chimeEndMinute: Int? = nil

    /// 區間報時的間隔（分鐘）。nil / 0 → 單一時刻。讀取請用 `chimeSlotTimes`（已算好每個報時時刻）。
    var chimeIntervalMinutes: Int? = nil

    /// 報時人聲性別（ChimeVoiceGender rawValue）。nil → 女聲（跟以前一樣）。讀取請用 `effectiveChimeVoice`。
    var chimeVoice: String? = nil

    /// 區間報時每個時刻各自合成的 CAF 檔名（與 `chimeSlotTimes` 索引對齊；slot 0 同時也是 soundFileName）。
    /// nil（舊資料）→ 由 AlarmSoundUpgradeHealer / AlarmScheduler 重新合成補齊。
    var chimeSlotSoundFiles: [String]? = nil

    /// 待辦圖示（TodoIcon rawValue）。非 nil ⇒ 這顆是「待辦語音提醒」而不是會響的鬧鐘：時間到時在
    /// 主頁吉祥物旁冒出此圖示，兒童長按播放 recordingName 的錄音。nil（一般鬧鐘 / 報時）→ 不是待辦。
    /// Optional + default nil 配合 SwiftData lightweight migration。判斷請用 `isTodo`。
    var todoIcon: String? = nil

    /// 待辦圖示在主頁顯示的持續分鐘數。0 ＝ 直到兒童點開才消失；其餘正整數 ＝ N 分鐘後自動消失。
    /// nil（舊資料）→ 預設 10 分鐘。讀取請用 `effectiveTodoDurationMinutes`。
    var todoDurationMinutes: Int? = nil

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

    /// 群組索引——nil（舊資料 / 未設定）→ 0（群組 A）。請一律用這個讀取，並 clamp 到 0...4。
    var effectiveGroupIndex: Int {
        let raw = groupIndex ?? 0
        return min(max(raw, 0), 4)
    }

    /// 報時次數上限（報時鬧鐘最多連報幾次）。
    static let maxChimeCount = 5

    /// 報時次數——nil → 1，並 clamp 到 1...maxChimeCount。
    var effectiveChimeCount: Int {
        min(max(chimeCount ?? 1, 1), Self.maxChimeCount)
    }

    /// 這顆是不是報時鬧鐘：鈴聲檔名走報時合成檔（chime_ 前綴）即視為報時。
    /// soundFileName 是單一事實來源——前景 AlarmRingView / 背景 AlarmKit 都靠它選音，
    /// 所以「是否報時」也以它為準，不額外存旗標避免兩邊不同步。
    var isChimeAlarm: Bool { soundFileName.hasPrefix(Self.chimeFilePrefix) }

    /// 報時合成 CAF 的檔名前綴（與 ChimeSoundComposer 一致）。
    static let chimeFilePrefix = "chime_"

    // MARK: 區間報時（起 → 迄，每隔 N 分報一次）

    /// 區間報時最多幾個時刻。上限的來源是 iOS「每 app 最多 64 顆 pending 通知」：
    /// 每個時刻每天至少 1 顆（勾 1–6 天時每天各 1 顆），12 個時刻 × 5 個上學日 ＝ 60 顆就已貼近上限。
    static let maxChimeSlots = 12

    /// 可選的報時間隔（分鐘）。
    static let chimeIntervalOptions = [1, 2, 3, 5, 10, 15, 20, 30]

    /// 報時人聲——nil（舊資料）→ 女聲。
    var effectiveChimeVoice: ChimeVoiceGender {
        ChimeVoiceGender(rawValue: chimeVoice ?? "") ?? .female
    }

    /// 是否為「區間報時」（有迄時刻 + 有間隔，且算出來不只一個時刻）。
    var isIntervalChime: Bool { chimeSlotTimes.count > 1 }

    /// 這顆報時鬧鐘要念出的每個時刻（起、起+N、起+2N…，**不含迄**）。
    /// 單一時刻報時 / 一般鬧鐘 → 只有 `[hour:minute]`。純函式版見 `chimeSlotTimes(startHour:…)`。
    var chimeSlotTimes: [(hour: Int, minute: Int)] {
        Self.chimeSlotTimes(
            startHour: hour, startMinute: minute,
            endHour: chimeEndHour, endMinute: chimeEndMinute,
            intervalMinutes: chimeIntervalMinutes
        )
    }

    /// 起 07:00、迄 07:30、間隔 5 → 07:00, 07:05 … 07:25（六次；**迄時刻本身不報**——
    /// Rex 的原始需求：「7:00 囉、7:05 囉 … 7:25 囉」，7:30 是該出門的時刻，不是再提醒一次）。
    /// 迄 ≤ 起、間隔 ≤ 0、或任一欄 nil → 只有起這一個時刻。最多 `maxChimeSlots` 個。
    static func chimeSlotTimes(startHour: Int, startMinute: Int,
                               endHour: Int?, endMinute: Int?,
                               intervalMinutes: Int?) -> [(hour: Int, minute: Int)] {
        let start = startHour * 60 + startMinute
        guard let eh = endHour, let em = endMinute,
              let interval = intervalMinutes, interval > 0 else {
            return [(startHour, startMinute)]
        }
        let end = eh * 60 + em
        guard end > start else { return [(startHour, startMinute)] }
        var out: [(hour: Int, minute: Int)] = []
        var t = start
        while t < end, out.count < maxChimeSlots {
            out.append((t / 60, t % 60))
            t += interval
        }
        return out
    }

    /// 每個報時時刻對應的 CAF 檔名（與 `chimeSlotTimes` 對齊）。
    /// 陣列缺／長度不符（舊資料、改過時間但還沒重合成）→ nil，呼叫端要重新合成。
    var alignedChimeSlotFiles: [String]? {
        guard let files = chimeSlotSoundFiles, files.count == chimeSlotTimes.count,
              !files.contains(where: \.isEmpty) else { return nil }
        return files
    }

    /// 顯示用：`07:00–07:30`（區間）或 `07:00`（單一時刻）。
    func formattedChimeRange(use24h: Bool) -> String {
        guard isIntervalChime, let eh = chimeEndHour, let em = chimeEndMinute else {
            return formattedTime(use24h: use24h)
        }
        return "\(formattedTime(use24h: use24h))–\(Self.timeString(hour: eh, minute: em, use24h: use24h))"
    }

    /// 這顆是不是待辦語音提醒（有挑圖示即視為待辦）。待辦不會響（不進 AlarmKit / 通知），只在主頁冒圖示。
    var isTodo: Bool { todoIcon != nil }

    /// 待辦圖示（解析 rawValue，壞值/未設→氣球）。
    var effectiveTodoIcon: TodoIcon {
        guard let raw = todoIcon, let icon = TodoIcon(rawValue: raw) else { return .balloon }
        return icon
    }

    /// 待辦圖示顯示時長（分鐘）。nil→10；0 ＝ 直到點開。
    var effectiveTodoDurationMinutes: Int {
        let v = todoDurationMinutes ?? 10
        return max(0, v)
    }

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
        Self.timeString(hour: hour, minute: minute, use24h: use24h)
    }

    /// 同上的靜態版——編輯器「用時間當標籤」也要格式化還沒存進鬧鐘的時間，共用這一份。
    static func timeString(hour: Int, minute: Int, use24h: Bool) -> String {
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

// MARK: - 鈴聲檔解析（全 app 唯一一份）

extension Alarm {
    /// 這顆鬧鐘實際會播的音檔，nil = 連內建預設音都不在 bundle 裡（不該發生）。
    ///
    /// 優先序：家長錄音 → `Library/Sounds` 的匯出檔（自訂 CAF／報時 chime）→ bundle 內建鈴聲
    /// → 內建預設音 `sunny_wake.caf`。三種鬧鐘都涵蓋：一般錄音走第一段、報時走第二段
    /// （`chime_*.caf` 只存在於 Library/Sounds）、內建鈴聲走第三段。
    ///
    /// ⚠️ 這段邏輯先前在響鈴畫面／編輯器試聽／錄音頁各有一份；分歧過就會出現
    /// 「試聽聽到 A、真的響時是 B」。要改優先序**只改這裡**。
    var ringtoneURL: URL? {
        let fm = FileManager.default

        if !recordingName.isEmpty {
            let url = AppPaths.recordingURL(named: recordingName)
            if fm.fileExists(atPath: url.path) { return url }
            print("🔊 Alarm.ringtoneURL: recording \(recordingName).m4a MISSING — falling back")
        }

        // 匯出的自訂音／報時音在 Library/Sounds（AlarmSoundExporter / ChimeSoundComposer 寫在那），
        // 不在 bundle —— 先查 Library/Sounds，再查 bundle。
        if !soundFileName.isEmpty {
            let cafURL = AppPaths.soundURL(named: soundFileName)
            if fm.fileExists(atPath: cafURL.path) { return cafURL }
            if let bundleURL = Bundle.main.url(forResource: soundFileName, withExtension: nil) { return bundleURL }
            print("🔊 Alarm.ringtoneURL: \(soundFileName) not in Library/Sounds or bundle — using default tone")
        }

        // 保底：內建預設音。響鈴畫面絕不能靜音。
        if let defaultURL = Bundle.main.url(forResource: "sunny_wake.caf", withExtension: nil) {
            return defaultURL
        }
        print("🔊 Alarm.ringtoneURL: ⚠️ default sunny_wake.caf missing from bundle — no audio")
        return nil
    }

    /// 首頁長按試聽用：這顆鬧鐘有沒有「家長自己準備的聲音」（錄音或匯出的自訂音／報時音）。
    /// 只有內建鈴聲的鬧鐘也能長按試聽，所以這個旗標目前只用來決定 VoiceOver 提示措辭。
    var hasCustomVoice: Bool {
        !recordingName.isEmpty || soundFileName.hasPrefix("alarm_") || soundFileName.hasPrefix(Self.chimeFilePrefix)
    }
}

// MARK: - 鬧鐘種類（首頁卡片 / 統計用的單一判斷）

/// 三種提醒的分類：一般鬧鐘（會響、要關）／報時（念時間、自動停）／待辦（不響、主頁冒圖示）。
/// 判斷邏輯散在 `isTodo` / `isChimeAlarm` 兩個旗標，這裡收成一個 enum 讓 UI 只 switch 一次。
enum AlarmKind {
    case alarm
    case chime
    case todo

    var systemImage: String {
        switch self {
        case .alarm: return "alarm.fill"
        case .chime: return "speaker.wave.2.bubble.fill"
        case .todo:  return "balloon.fill"
        }
    }
}

extension Alarm {
    var kind: AlarmKind {
        if isTodo { return .todo }
        if isChimeAlarm { return .chime }
        return .alarm
    }
}
