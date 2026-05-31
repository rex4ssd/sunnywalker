// SunnyWalker — MarkdownAlarmIO.swift  |  鬧鐘設定的 Markdown 匯入 / 匯出

import Foundation

/// 一行 Markdown 解析後的結果（尚未寫入 SwiftData）。
struct ParsedAlarm {
    var hour: Int
    var minute: Int
    var label: String
    var weekdays: [Int]   // 1=日 … 7=六，對齊 Alarm.weekdays
    var isEnabled: Bool
}

/// 鬧鐘的 Markdown 互轉。
///
/// 每行格式： `repeat, HH:MM, label`
/// 例如：
/// ```
/// daily, 08:00, go to school
/// weekdays, 07:00, work
/// weekends, 09:30, 賴床
/// 一三五, 06:30, gym            # 自訂星期（用 日一二三四五六）
/// daily, 13:00, 午睡 (off)      # 結尾加 (off) 代表停用
/// ```
/// 以 `#` 開頭或空白的行會被忽略。
/// 註：資料模型以 weekdays 陣列表示重複，沒有「單次」概念，故不支援 once。
enum MarkdownAlarmIO {

    static let allDays = [1, 2, 3, 4, 5, 6, 7]
    static let workdays = [2, 3, 4, 5, 6]
    static let weekend = [1, 7]
    private static let dayChars: [Character: Int] = [
        "日": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7
    ]

    // MARK: - 匯出

    static func export(_ alarms: [Alarm]) -> String {
        var lines = [
            "# SunnyWalker Alarms",
            "# 格式: repeat, HH:MM, label   （停用的鬧鐘結尾會有 (off)）"
        ]
        lines += alarms.map(line(for:))
        return lines.joined(separator: "\n") + "\n"
    }

    private static func line(for alarm: Alarm) -> String {
        let rep = repeatToken(alarm.weekdays)
        let label = alarm.label.replacingOccurrences(of: ",", with: " ")
        var s = "\(rep), \(alarm.timeString), \(label)".trimmingCharacters(in: .whitespaces)
        if !alarm.isEnabled { s += " (off)" }
        return s
    }

    private static func repeatToken(_ weekdays: [Int]) -> String {
        let set = Set(weekdays)
        if set == Set(allDays) { return "daily" }
        if set == Set(workdays) { return "weekdays" }
        if set == Set(weekend) { return "weekends" }
        let inv = Dictionary(uniqueKeysWithValues: dayChars.map { ($1, $0) })
        return weekdays.sorted().compactMap { inv[$0] }.map(String.init).joined()
    }

    // MARK: - 匯入

    static func parse(_ text: String) -> [ParsedAlarm] {
        text.components(separatedBy: .newlines).compactMap(parseLine(_:))
    }

    static func parseLine(_ raw: String) -> ParsedAlarm? {
        var line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

        var enabled = true
        if line.lowercased().hasSuffix("(off)") {
            enabled = false
            line = String(line.dropLast(5)).trimmingCharacters(in: .whitespaces)
        }

        let parts = line.split(separator: ",", maxSplits: 2,
                               omittingEmptySubsequences: false)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2,
              let weekdays = parseRepeat(parts[0]),
              let (h, m) = parseTime(parts[1]) else { return nil }

        let label = parts.count >= 3 ? parts[2] : ""
        return ParsedAlarm(hour: h, minute: m, label: label,
                           weekdays: weekdays, isEnabled: enabled)
    }

    private static func parseTime(_ s: String) -> (Int, Int)? {
        let c = s.split(separator: ":")
        guard c.count == 2, let h = Int(c[0]), let m = Int(c[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    private static func parseRepeat(_ s: String) -> [Int]? {
        switch s.lowercased() {
        case "daily", "每天", "每日": return allDays
        case "weekdays", "平日", "工作日": return workdays
        case "weekends", "週末", "周末": return weekend
        default:
            let days = s.compactMap { dayChars[$0] }.sorted()
            return days.isEmpty ? nil : Array(Set(days)).sorted()
        }
    }
}
