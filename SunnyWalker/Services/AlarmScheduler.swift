// SunnyWalker — AlarmScheduler.swift  |  Day 2  |  UNUserNotificationCenter wrapper
//
// ⚠️ DEPRECATED — v1 path kept alongside AlarmKitService (v2) until device validation.
// Remove after confirming AlarmKit breaks silent/Focus mode and weekly repeats on real hardware.

import UserNotifications
import Foundation
import AVFAudio  // CAF duration check（短 CAF 自我修復用）

@MainActor
final class AlarmScheduler {
    static let shared = AlarmScheduler()
    private init() {}

    // Schedule one notification request per active weekday so repeats honour the weekdays array.
    func schedule(alarm: Alarm) async throws {
        // 多人鬧鐘群組閘：群組被關閉 / 超出目前群組數 → 不排，並清掉既有 pending（等家長把群組開回再響）。
        guard AppSettings.groupAllowsFiring(alarm.effectiveGroupIndex) else {
            cancel(alarm.id)
            print("🔔 AlarmScheduler.schedule: \(alarm.id.uuidString.prefix(8)) group inactive/hidden — cancelled, not scheduling")
            return
        }
        let center = UNUserNotificationCenter.current()

        print("🔔 AlarmScheduler.schedule: alarm=\(alarm.id.uuidString.prefix(8)) \(alarm.hour):\(String(format: "%02d", alarm.minute)) weekdays=\(alarm.weekdays) sound=\(alarm.soundFileName) AlarmKitAuthorized=\(AlarmKitService.shared.isAuthorized)")

        // 🚦 通知權限診斷：通知模式要靠 UNUserNotificationCenter 授權（與 AlarmKit 授權是兩回事）。
        //   若 authStatus≠2(authorized) 或 alert/sound≠2(enabled) → 通知不會出現/沒聲音，這才是
        //   「提醒模式什麼都沒發生」的另一個可能源頭（去 設定>SunnyWalker>通知 開啟）。
        let ns = await center.notificationSettings()
        print("🚦 AlarmScheduler: UN authStatus=\(ns.authorizationStatus.rawValue) alert=\(ns.alertSetting.rawValue) sound=\(ns.soundSetting.rawValue) lockScreen=\(ns.lockScreenSetting.rawValue) timeSensitive=\(ns.timeSensitiveSetting.rawValue) (2=enabled/authorized)")

        // 2026-06-12 防 kill-race 根治：center.add() 本來就會【取代】同 identifier 的 pending
        // request，所以「即將重排的 ID」不必先 remove——只移除不再使用的 slot（例如取消勾選的
        // weekday、weekday↔一次性切換後的舊格式）。這讓排程沒有「已 remove、未 add 完成」的
        // 空窗；之前 force-quit 卡在這個空窗會把通知整批清掉（見 issue 文件第二輪）。
        let isNotificationMode = alarm.effectiveBackgroundMode == .notification
        // rep-k（gentle-repeat burst）一律列入清掃：它們是「下一次發生」的一次性 slot，
        // 不放進 keepIDs → 每次排程先清掉舊的，再由 scheduleGentleRepeatBurst 重排新的。
        let allIDs = (1...7).map { "\(alarm.id.uuidString)-\($0)" }
            + (1...Self.maxRepeatSlots).map { "\(alarm.id.uuidString)-rep-\($0)" }
            + [alarm.id.uuidString]
        let keepIDs: Set<String> = isNotificationMode || !AlarmKitService.shared.isAuthorized
            ? (alarm.weekdays.isEmpty
                ? [alarm.id.uuidString]
                : Set(alarm.weekdays.map { "\(alarm.id.uuidString)-\($0)" }))
            : []  // AlarmKit 模式且已授權 → 此路徑只負責清掉殘留通知，全移除
        center.removePendingNotificationRequests(withIdentifiers: allIDs.filter { !keepIDs.contains($0) })

        // AlarmKit is the single source of truth once authorized. Scheduling both an
        // AlarmKit alarm AND a UNNotification makes the device fire twice (full-screen
        // alert + 30s banner). When AlarmKit is active this legacy path stands down and
        // only clears any leftover notifications. It still runs as a fallback on devices
        // where AlarmKit authorization was denied/unavailable.
        //
        // ★ 2026-06-12 例外：per-alarm「通知模式」(effectiveBackgroundMode == .notification)
        //   故意走這條 UNNotification 路徑，即使 AlarmKit 已授權——因為它要的就是「響一次自動停、
        //   不用 AlarmKit 無限響」。這種鬧鐘不排 AlarmKit（syncAlarm 會跳過 + 移除既有 AlarmKit 條目），
        //   所以不會雙重響鈴。
        guard isNotificationMode || !AlarmKitService.shared.isAuthorized else {
            print("🔔 AlarmScheduler: AlarmKit authorized — standing down (UNNotification cleared)")
            return
        }
        if isNotificationMode {
            print("🔔 AlarmScheduler: NOTIFICATION-mode alarm \(alarm.id.uuidString.prefix(8)) — scheduling .timeSensitive UNNotification (AlarmKit deliberately not used)")
        }

        // Self-heal: alarms recorded before the CAF export existed still point at the bundled
        // default sound. If a recording exists but no custom CAF is set, export one now so the
        // banner can ring the parent's voice on the next fire — no manual re-record needed.
        if !alarm.recordingName.isEmpty,
           alarm.soundFileName.isEmpty || alarm.soundFileName == "sunny_wake.caf" {
            if let caf = AlarmSoundExporter.exportLockScreenCAF(fromRecordingNamed: alarm.recordingName) {
                alarm.soundFileName = caf
                print("🔔 AlarmScheduler: self-healed custom sound → \(caf)")
            }
        }

        let content = UNMutableNotificationContent()
        content.title = L("起床囉！")
        // 2026-06-12 UX：body 顯示鬧鐘 label（專注提醒要做的事）。
        // 之前顯示「點開來聽：<recordingName>」，但 recordingName 是內部 UUID，
        // 鎖屏橫幅會出現一串亂碼（實機截圖證實）。沒設 label 就用通用早安語。
        content.body = alarm.label.isEmpty ? L("早安！☀️") : alarm.label
        // Sound selection (this UNNotification path is the one that actually fires while
        // AlarmKit is unauthorized — i.e. before the entitlement is approved):
        //   • Custom recording → ring its exported Library/Sounds/*.caf directly from the banner,
        //     so the parent's voice plays from the FIRST ring instead of only after tapping in.
        //     The export (AlarmSoundExporter) writes a mono 16-bit PCM CAF ≤30s — the format
        //     UNNotificationSound plays reliably (stereo/long CAFs are what used to fall through).
        //   • Otherwise → system default tone.
        // 量到的 CAF 長度（秒）— 餵給 gentle-repeat burst 算「下一顆通知」的秒級間距。預設 5。
        var cafSeconds: Double = 5
        let custom = alarm.soundFileName
        let wantsCustom = !custom.isEmpty && custom != "sunny_wake.caf" && !alarm.recordingName.isEmpty
        // 內建鈴聲選擇＝有 soundFileName、沒有 recordingName、且檔案在 app bundle 裡（sunny_wake.caf / leaf_rustle.caf）。
        // 這條跟 wantsCustom 互斥：錄音走上面、內建走下面、其餘（沒選/舊資料）落 .default。
        let isBundledSelection = !custom.isEmpty
            && alarm.recordingName.isEmpty
            && Bundle.main.url(forResource: custom, withExtension: nil) != nil
        if wantsCustom {
            // Verify the CAF actually exists in Library/Sounds — UNNotificationSound(named:)
            // SILENTLY falls back to the default tone if the file is missing or wrong format.
            // ⚠️ 2026-06-13 真機實證：iOS 對「過長」的自訂通知音也會悄悄退成 ~2s 預設音，門檻【遠低於】
            //   文件寫的 30s（實測 29s 就掛、只驗到 4.6s 安全）。所以下面用短 CAF + 反向自我修復處理。
            //   Checking here turns that invisible failure into a visible log line.
            let fm = FileManager.default
            let soundsDir = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Sounds", isDirectory: true)
            let cafPath = soundsDir.appendingPathComponent(custom).path
            let exists = fm.fileExists(atPath: cafPath)
            let dirList = (try? fm.contentsOfDirectory(atPath: soundsDir.path)) ?? []
            print("🔔 AlarmScheduler: custom sound check → name=\(custom) existsInLibrarySounds=\(exists) path=\(cafPath)")
            print("🔔 AlarmScheduler: Library/Sounds contents = \(dirList)")
            if exists {
                // 2026-06-13：CAF 現在是「短的原始錄音」（exporter 不再 loop 成 29s）。
                //   原因：真機證實 iOS 會把長的自訂通知音整顆退成 ~2s 預設音，短的才照播完整。
                //   「響滿 ~30s」改由 scheduleGentleRepeatBurst 用秒級錯開的多顆通知堆出來。
                //   這裡量長度（餵 burst 算間距）並印 measure log。
                var effectiveName = custom
                if let caf = try? AVAudioFile(forReading: URL(fileURLWithPath: cafPath)) {
                    // length 單位是檔案原生 sample frames → 用 fileFormat 才語意正確
                    let secs = Double(caf.length) / caf.fileFormat.sampleRate
                    let cafBytes = ((try? FileManager.default.attributesOfItem(atPath: cafPath))?[.size] as? Int) ?? -1
                    cafSeconds = max(1, secs)
                    print("🔬 AlarmScheduler: CAF measure → \(String(format: "%.1f", secs))s frames=\(caf.length) sr=\(caf.fileFormat.sampleRate) bytes=\(cafBytes)")

                    // 🔁 反向自我修復：舊版（2026-06-12 以前）把 CAF loop 成 ~29s，會被 iOS 截成 ~2s。
                    //   偵測到「過長」(≥25s) 就用原始錄音重匯出成短 CAF（新 exporter 不 loop），
                    //   讓既有鬧鐘自動痊癒、免使用者一顆顆重選。新短 CAF 之後不會再觸發（<25s）。
                    if secs >= 25, !alarm.recordingName.isEmpty,
                       let short = AlarmSoundExporter.exportLockScreenCAF(fromRecordingNamed: alarm.recordingName) {
                        effectiveName = short
                        alarm.soundFileName = short
                        // 重新量短檔長度給 burst 用（不然 burst 會拿舊的 29s 算出超大間距而不排）。
                        if let c2 = try? AVAudioFile(forReading: soundsDir.appendingPathComponent(short)) {
                            cafSeconds = max(1, Double(c2.length) / c2.fileFormat.sampleRate)
                        }
                        print("🔔 AlarmScheduler: old long CAF (\(String(format: "%.1f", secs))s) auto-healed → short \(short) (\(String(format: "%.1f", cafSeconds))s)")
                    }
                }
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: effectiveName))
                print("🔔 AlarmScheduler: using CUSTOM banner sound → \(effectiveName)")
            } else {
                content.sound = .default
                print("🔔 AlarmScheduler: ⚠️ custom CAF missing — FALLING BACK to default. (re-record or re-save to regenerate)")
            }
        } else if isBundledSelection {
            // 內建鈴聲（陽光起床 / 樹葉沙沙）走通知模式：以前這裡漏接 → 一律 .default（系統「咚」一聲），
            // 內建音從來沒響過。現在比照錄音路徑：把 bundle 裡的 18–20s CAF 修剪成短 CAF（避開 iOS 對
            // 長自訂通知音「鎖屏退成 ~2s」的雷），存進 Library/Sounds，再交給 gentle-repeat burst 鋪滿 ~30s。
            if let shortName = AlarmSoundExporter.exportBundledShortCAF(bundledName: custom) {
                let soundsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Sounds", isDirectory: true)
                if let caf = try? AVAudioFile(forReading: soundsDir.appendingPathComponent(shortName)) {
                    cafSeconds = max(1, Double(caf.length) / caf.fileFormat.sampleRate)
                }
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: shortName))
                print("🔔 AlarmScheduler: using BUNDLED banner sound → \(custom) via short \(shortName) (\(String(format: "%.1f", cafSeconds))s)")
            } else {
                content.sound = .default
                print("🔔 AlarmScheduler: ⚠️ bundled short export failed for \(custom) — FALLING BACK to default")
            }
        } else {
            content.sound = .default
            print("🔔 AlarmScheduler: using DEFAULT banner sound (custom=\(custom) recording=\(alarm.recordingName.isEmpty ? "none" : "yes"))")
        }
        content.categoryIdentifier = "SUNNYWAKE_ALARM"
        // 同一顆鬧鐘的所有通知（baseline + 切段 burst 的 rep-k）共用同一個 threadIdentifier，
        // 讓通知中心把它們「收成一組」而不是一整排散開的「起床囉！」（修圖1的堆疊觀感）。
        content.threadIdentifier = alarm.id.uuidString
        // 鬧鐘類通知優先 .timeSensitive：能突破「專注模式 / 勿擾」即時送達並亮屏。
        // ⚠️ 注意：.timeSensitive 突破不了實體靜音開關（要破靜音得用 .critical + Apple entitlement）。
        //
        // 🔴 2026-06-12 實測（NOTIFICATION_MODE_NOT_FIRING）：entitlement【沒進 binary】時，
        //   標了 .timeSensitive 的通知會被 iOS【整顆悄悄丟棄】——不顯示、不出聲、也不進
        //   delivered 清單（不是想像中的「只降級」）。症狀＝pending=7 但到點完全沒反應。
        //   因此這裡用 timeSensitiveSetting 做 runtime 防衛：
        //   .notSupported(0)＝entitlement 不在 binary（漏跑 xcodegen generate / signing 拿掉）
        //   .disabled(1)   ＝使用者在 設定>通知 把 Time Sensitive 關了
        //   兩者都降回 .active，通知至少還會正常顯示，只是不破專注模式。
        if ns.timeSensitiveSetting == .enabled {
            content.interruptionLevel = .timeSensitive
        } else {
            content.interruptionLevel = .active
            print("🚦 AlarmScheduler: ⚠️ timeSensitiveSetting=\(ns.timeSensitiveSetting.rawValue) (0=entitlement missing, 1=user disabled) — downgrading to .active so the notification still shows")
        }
        // requireAppToStop travels with the banner so the ✕ (dismiss) handler in AppDelegate knows
        // whether this is strict mode. Non-strict → ✕ turns the alarm off; strict → nags persist.
        content.userInfo = [
            "alarmID": alarm.id.uuidString,
            "requireAppToStop": alarm.effectiveRequireAppToStop,
            // 2026-06-12：點擊路由用——提醒模式點橫幅只回主畫面，不開 AlarmRingView
            //（聲音已播完自動停，沒有「關鬧鐘」的需求）。AppDelegate.didReceive 讀這個 key。
            "backgroundMode": alarm.effectiveBackgroundMode.rawValue
        ]

        if alarm.weekdays.isEmpty {
            // One-shot: fire at the next occurrence of hour:minute (today or tomorrow).
            var comps = DateComponents()
            comps.hour = alarm.hour
            comps.minute = alarm.minute
            comps.second = 0
            guard let fireDate = Calendar.current.nextDate(
                after: Date(), matching: comps, matchingPolicy: .nextTime
            ) else { return }
            let dateParts = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateParts, repeats: false)
            let request = UNNotificationRequest(
                identifier: alarm.id.uuidString, content: content, trigger: trigger
            )
            try await center.add(request)
            await scheduleNagsIfNeeded(alarm: alarm, content: content, fireDate: fireDate, center: center)
            // 切段（segmentedBurst）開啟才堆疊響滿 ~30s；關閉＝只響一下（單通知），避免圖1的整排通知。
            if alarm.effectiveSegmentedBurst {
                await scheduleGentleRepeatBurst(alarm: alarm, content: content, fireDate: fireDate, voiceSeconds: cafSeconds, center: center)
            }
            return
        }

        for weekday in alarm.weekdays {
            var components = DateComponents()
            components.hour = alarm.hour
            components.minute = alarm.minute
            components.weekday = weekday  // 1=Sun … 7=Sat, matches Alarm.weekdays convention

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: "\(alarm.id.uuidString)-\(weekday)",
                content: content,
                trigger: trigger)

            try await center.add(request)
        }
        // Strict mode for a repeating alarm: nag for the NEXT occurrence (one-shot). Renews on the
        // next app launch / re-arm. Keeps us well under the 64 pending-notification limit.
        // gentle-repeat burst 也只鋪「下一次發生」（一次性），每次 re-arm 重排。
        if let next = nextOccurrence(for: alarm) {
            await scheduleNagsIfNeeded(alarm: alarm, content: content, fireDate: next, center: center)
            // 切段開啟才堆疊；關閉＝只響一下。
            if alarm.effectiveSegmentedBurst {
                await scheduleGentleRepeatBurst(alarm: alarm, content: content, fireDate: next, voiceSeconds: cafSeconds, center: center)
            }
        }
    }

    // MARK: - Strict mode ("貪睡模式") nag notifications

    /// When `requireAppToStop` is on, schedule a burst of follow-up notifications at +1…+N minutes
    /// after the alarm fires. Dismissing one (tapping ✕) just lets the next minute's nag fire, so
    /// the child can't silence the alarm without opening the app. `AlarmRingView` cancels these the
    /// moment the app actually opens for this alarm (`cancelNags`). N is capped by the configured
    /// ring duration (and 9) to stay within the per-app pending-notification limit.
    private func scheduleNagsIfNeeded(
        alarm: Alarm,
        content: UNNotificationContent,
        fireDate: Date,
        center: UNUserNotificationCenter
    ) async {
        guard alarm.effectiveRequireAppToStop else { return }
        let n = max(1, min(9, AppSettings.shared.alarmRingDurationMinutes))
        for k in 1...n {
            guard let nagDate = Calendar.current.date(byAdding: .minute, value: k, to: fireDate) else { continue }
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: nagDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let req = UNNotificationRequest(
                identifier: "\(alarm.id.uuidString)-nag-\(k)", content: content, trigger: trigger
            )
            try? await center.add(req)
        }
        print("🔔 AlarmScheduler: strict mode — scheduled \(n) nag(s) after \(fireDate)")
    }

    // MARK: - 溫和提醒「響滿 ~30s」堆疊（gentle-repeat burst）

    private static let maxRepeatSlots = 12   // 清理 {uuid}-rep-k 用的列舉上限

    /// 提醒模式「響滿 ~30s」：真機證實 iOS 只完整播「短的」自訂通知音，單顆只響一段語音。
    /// 這裡對【下一次發生】加排數顆秒級錯開的一次性通知（`{uuid}-rep-k`），把語音重複鋪到 ~30s，
    /// 之後沒有更多通知 → 自然停（溫和、不續電）。每次 `schedule()` 都重排下一次的 burst
    /// （app 前景/背景常 re-arm）。即使被殺多天沒開 app，baseline 那顆 repeating 仍會響一段完整語音。
    /// ⚠️ iOS 每 app pending 上限 64：用 runtime pending 計數自我設限，先到先得，後面的鬧鐘自動少排。
    private func scheduleGentleRepeatBurst(
        alarm: Alarm,
        content: UNNotificationContent,
        fireDate: Date,
        voiceSeconds: Double,
        center: UNUserNotificationCenter
    ) async {
        // 兩顆通知 fire 時間的間距（秒）＝一段語音長度 + 使用者設定的靜音間隔（recordingGapSeconds，預設 2）。
        let gap = max(0, AppSettings.shared.recordingGapSeconds)
        let period = max(2, Int(ceil(voiceSeconds)) + gap)
        let targetSpan = 30   // 目標總響鈴長度（秒）

        // slot 0 = baseline 那顆（已在 fireDate 第 0 秒排好），這裡只補 slot 1…N。
        // 秒位須 < 60（留在同一分鐘內，避免跨分鐘 DateComponents 複雜化），且不超過 targetSpan。
        var offsets: [Int] = []
        var t = period
        while t <= targetSpan && t < 60 {
            offsets.append(t)
            t += period
        }
        guard !offsets.isEmpty else { return }

        // 64 上限防衛：看現在還剩多少額度，最多補這麼多顆（留 2 顆 margin）。
        let pendingNow = await center.pendingNotificationRequests().count
        let budget = max(0, 64 - pendingNow - 2)
        guard budget > 0 else {
            print("🔔 AlarmScheduler: gentle-repeat burst SKIPPED — pending=\(pendingNow) near 64 limit")
            return
        }
        let slots = Array(offsets.prefix(min(budget, Self.maxRepeatSlots)))

        let cal = Calendar.current
        var added = 0
        for (i, off) in slots.enumerated() {
            guard let slotDate = cal.date(byAdding: .second, value: off, to: fireDate) else { continue }
            let parts = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: slotDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let req = UNNotificationRequest(
                identifier: "\(alarm.id.uuidString)-rep-\(i + 1)", content: content, trigger: trigger
            )
            do { try await center.add(req); added += 1 } catch {
                print("🔔 AlarmScheduler: gentle-repeat slot \(i + 1) add failed — \(error.localizedDescription)")
            }
        }
        print("🔔 AlarmScheduler: gentle-repeat burst → \(added) extra slot(s), every \(period)s over ~\(targetSpan)s (voice=\(String(format: "%.1f", voiceSeconds))s gap=\(gap)s pendingWas=\(pendingNow))")
    }

    /// Soonest future fire date across an alarm's weekdays (for scheduling strict-mode nags).
    private func nextOccurrence(for alarm: Alarm) -> Date? {
        var comps = DateComponents()
        comps.hour = alarm.hour; comps.minute = alarm.minute; comps.second = 0
        let cal = Calendar.current
        if alarm.weekdays.isEmpty {
            return cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime)
        }
        var best: Date?
        for wd in alarm.weekdays {
            var c = comps; c.weekday = wd
            if let d = cal.nextDate(after: Date(), matching: c, matchingPolicy: .nextTime),
               best == nil || d < best! {
                best = d
            }
        }
        return best
    }

    /// Cancel only the strict-mode nag notifications for an alarm (leaves the main alarm intact so
    /// a repeating alarm still fires next time). Called when the app opens for the ringing alarm.
    func cancelNags(_ alarmID: UUID) {
        // 連 gentle-repeat burst 一起清——app 為這顆鬧鐘開起來＝小孩醒了，後續語音不該再響。
        let ids = (1...9).map { "\(alarmID.uuidString)-nag-\($0)" }
            + (1...Self.maxRepeatSlots).map { "\(alarmID.uuidString)-rep-\($0)" }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        print("🔔 AlarmScheduler: cancelled nags for \(alarmID.uuidString.prefix(8))")
    }

    func cancel(_ alarmID: UUID) {
        let identifiers = (1...7).map { "\(alarmID.uuidString)-\($0)" }
            + (1...9).map { "\(alarmID.uuidString)-nag-\($0)" }
            + (1...Self.maxRepeatSlots).map { "\(alarmID.uuidString)-rep-\($0)" }
            + [alarmID.uuidString]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // Convenience: schedule if enabled, cancel if disabled.
    func syncWithModel(alarm: Alarm) async throws {
        if alarm.isEnabled {
            try await schedule(alarm: alarm)
        } else {
            cancel(alarm.id)
        }
    }

    #if DEBUG
    /// 🔬 暫時：排 5 顆一次性 timeSensitive 通知（now+1…+5 分），長度 8/12/16/20/24s 的「每秒嗶」尺規音。
    /// 殺 App+關屏逐顆聽：播滿≈該秒數＝該長度 OK；只剩~2s＝被 iOS 截/退預設。最大「播滿」者＝安全上限。
    /// 由 Settings 的 DEBUG 按鈕觸發。測完整段（含 makeProbeBeepCAF / 按鈕）可刪。
    func scheduleCutoffProbe() async {
        let center = UNUserNotificationCenter.current()
        let ns = await center.notificationSettings()
        let lengths = [8, 12, 16, 20, 24]
        for (i, L) in lengths.enumerated() {
            guard let caf = AlarmSoundExporter.makeProbeBeepCAF(seconds: L) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "🔬 Cutoff probe \(L)s"
            content.body = "數嗶聲：播滿≈\(L) 聲(秒) 還是只剩 ~2s？"
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: caf))
            content.interruptionLevel = (ns.timeSensitiveSetting == .enabled) ? .timeSensitive : .active
            let fireDate = Date().addingTimeInterval(Double((i + 1) * 60))
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let req = UNNotificationRequest(identifier: "cutoff-probe-\(L)", content: content, trigger: trigger)
            do { try await center.add(req); print("🔬 Probe: scheduled \(L)s at \(fireDate)") }
            catch { print("🔬 Probe: schedule \(L)s failed — \(error.localizedDescription)") }
        }
        print("🔬 Probe: 5 顆已排（now+1…+5 分）。殺 App、關屏，逐顆聽嗶聲數到幾。")
    }
    #endif
}
