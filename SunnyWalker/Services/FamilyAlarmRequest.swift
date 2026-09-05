// SunnyWalker — FamilyAlarmRequest.swift  |  其他家族 app 傳時間過來變鬧鐘／提醒（URL scheme 入口）
//
// 未來規劃：家族 iOS app 登入後，其他 app（例：LetAbacus 練習排程、RestBud 休息時段）把「時間」
// 送到 SunnyWalker 變成鬧鐘或待辦。**現在能先做、零後端、Made for Kids 過得了審**的地基就是
// URL scheme：對方 app `openURL("rexsunny://alarm?...")`，SunnyWalker 打開後**只是預覽**，
// 家長過家長閘、按「加入」才真的建鬧鐘——外部 app 不能未經家長同意就往孩子的鬧鐘塞東西。
//
// URL 格式（`rexsunny` scheme 已在 project.yml / Info.plist 宣告）：
//
//     rexsunny://alarm?time=07:30&label=上學囉&days=2,3,4,5,6&kind=alarm&from=LetAbacus
//
//   time   必填，HH:MM（24 小時制）
//   label  選填，標籤（URL-encoded）
//   days   選填，1=日 … 7=六，逗號分隔；省略＝週一到週五（跟新增鬧鐘頁預設一致）
//   kind   選填，alarm（預設）／chime（報時）／todo（待辦，需家長再錄提醒語音）
//   from   選填，來源 app 顯示名（只用來顯示「由 ○○ 傳來」）
//
// 之後接家族登入／CloudKit 時，這個 struct 就是「一筆鬧鐘請求」的資料契約；來源從 URL 換成
// 同步紀錄即可，預覽與加入流程不必重寫。完整規劃見 docs/family_alarm_handoff.md。

import Foundation

struct FamilyAlarmRequest: Equatable, Identifiable {
    enum Kind: String { case alarm, chime, todo }

    /// 給 `.sheet(item:)` 用；同一份請求內容＝同一個 id。
    var id: String { makeURL()?.absoluteString ?? "\(hour):\(minute)-\(label)" }

    var hour: Int
    var minute: Int
    var label: String
    var weekdays: [Int]
    var kind: Kind
    var sourceApp: String?

    static let scheme = "rexsunny"
    static let host = "alarm"

    /// 解析 `rexsunny://alarm?...`；不是這個 host、或 time 不合法 → nil。
    static func parse(_ url: URL) -> FamilyAlarmRequest? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        var q: [String: String] = [:]
        for it in items { q[it.name.lowercased()] = it.value ?? "" }

        guard let time = q["time"] else { return nil }
        let parts = time.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }

        let days: [Int]
        if let raw = q["days"], !raw.isEmpty {
            days = Array(Set(raw.split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })).sorted()
        } else {
            days = [2, 3, 4, 5, 6]
        }

        let label = (q["label"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = Kind(rawValue: (q["kind"] ?? "alarm").lowercased()) ?? .alarm
        let from = (q["from"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return FamilyAlarmRequest(hour: h, minute: m, label: String(label.prefix(40)),
                                  weekdays: days, kind: kind,
                                  sourceApp: from.isEmpty ? nil : String(from.prefix(40)))
    }

    /// 反向：組出一個可以丟給 `openURL` 的連結（給其他家族 app／測試用）。
    func makeURL() -> URL? {
        var c = URLComponents()
        c.scheme = Self.scheme
        c.host = Self.host
        var items = [URLQueryItem(name: "time", value: String(format: "%02d:%02d", hour, minute))]
        if !label.isEmpty { items.append(URLQueryItem(name: "label", value: label)) }
        if !weekdays.isEmpty { items.append(URLQueryItem(name: "days", value: weekdays.map(String.init).joined(separator: ","))) }
        items.append(URLQueryItem(name: "kind", value: kind.rawValue))
        if let sourceApp { items.append(URLQueryItem(name: "from", value: sourceApp)) }
        c.queryItems = items
        return c.url
    }

    /// 建成 SwiftData 鬧鐘（尚未 insert）。todo 沒有錄音 → 先存成一般鬧鐘讓家長進編輯器補錄。
    func makeAlarm() -> Alarm {
        let alarm = Alarm(label: label.isEmpty ? "起床囉" : label, hour: hour, minute: minute, taskType: .button)
        alarm.weekdays = weekdays.isEmpty ? [2, 3, 4, 5, 6] : weekdays
        switch kind {
        case .chime:
            // 報時：走通知模式；語音檔由 AlarmScheduler 第一次排程時合成。
            alarm.backgroundRingMode = .notification
            alarm.chimeCount = 1
            alarm.soundFileName = "\(Alarm.chimeFilePrefix)pending.caf"   // 標成報時（isChimeAlarm）；排程時會換成真檔名
        case .todo, .alarm:
            break
        }
        return alarm
    }
}
