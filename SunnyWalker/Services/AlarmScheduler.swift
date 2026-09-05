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
        // 待辦語音提醒不會響（不發通知、不進 AlarmKit）——只在主頁冒圖示。清掉任何殘留通知後直接返回。
        guard !alarm.isTodo else {
            cancel(alarm.id)
            return
        }
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
        // 後續通知（rep-k 切段堆疊、chime 連報、nag）一律列入清掃：它們是「下一次發生」的一次性 slot，
        // 不放進 keepIDs → 每次排程先清掉舊的，再重排新的。id 清單統一來自 AlarmNotificationIDs。
        let keepIDs: Set<String>
        if isNotificationMode || !AlarmKitService.shared.isAuthorized {
            if alarm.isChimeAlarm {
                keepIDs = Set(chimeRequestIDs(for: alarm))
            } else if alarm.weekdays.isEmpty {
                keepIDs = [AlarmNotificationIDs.base(alarm.id)]
            } else {
                keepIDs = Set(alarm.weekdays.map { AlarmNotificationIDs.weekday(alarm.id, $0) })
            }
        } else {
            keepIDs = []  // AlarmKit 模式且已授權 → 此路徑只負責清掉殘留通知，全移除
        }
        center.removePendingNotificationRequests(
            withIdentifiers: AlarmNotificationIDs.all(for: alarm.id).filter { !keepIDs.contains($0) }
        )

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

        // 報時（單一時刻或區間）：自己一條路——每個時刻各一個語音檔、各自的 request。
        if alarm.isChimeAlarm {
            await scheduleChime(alarm: alarm, center: center,
                                timeSensitiveEnabled: ns.timeSensitiveSetting == .enabled)
            return
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
            let soundsDir = AppPaths.soundsDirectory
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
                if let caf = try? AVAudioFile(forReading: AppPaths.soundURL(named: shortName)) {
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

    // MARK: - 報時（單一時刻 / 區間）

    /// 這顆報時鬧鐘「會被 add」的所有 request id（給 schedule() 的清掃當 keep 清單用）。
    private func chimeRequestIDs(for alarm: Alarm) -> [String] {
        let slots = alarm.chimeSlotTimes.indices
        let daily = Set(alarm.weekdays) == Set(1...7)
        if alarm.weekdays.isEmpty || daily {
            return slots.map { AlarmNotificationIDs.chimeSlot(alarm.id, slot: $0) }
        }
        return slots.flatMap { s in alarm.weekdays.map { AlarmNotificationIDs.chimeSlot(alarm.id, slot: s, weekday: $0) } }
    }

    /// 報時排程：每個時刻（slot）各自一個語音檔 + 各自的 request；連報 N 次為每個時刻的下一次發生
    /// 補排第 2…N 顆秒級錯開的一次性通知。
    ///
    /// 通知額度（iOS 每 app 64 顆 pending）：
    ///   • 七天都勾 → 每個 slot 只用 1 顆「每天重複」的 request（不帶 weekday），12 個時刻＝12 顆。
    ///   • 勾部分星期 → 每個 slot × 每個星期各 1 顆；12 × 5 ＝ 60，貼近上限，所以先排「時刻」
    ///     再排「連報」，額度不夠時連報自動少排（時刻優先，寧可少報幾次也不能漏掉時刻）。
    ///   • 語音檔缺／舊資料 → 先在背景重新合成全部時刻（全成功才換），失敗保留舊檔照排。
    private func scheduleChime(alarm: Alarm, center: UNUserNotificationCenter,
                               timeSensitiveEnabled: Bool) async {
        let slots = alarm.chimeSlotTimes
        let locale = SunnyLocalization.locale
        let voice = alarm.effectiveChimeVoice

        // 1. 語音檔：與時刻數對齊且檔案都在 → 直接用；否則重新合成（舊格式單檔、改過時間/人聲、檔案遺失）。
        var files = alarm.alignedChimeSlotFiles
        if let f = files, f.contains(where: { !FileManager.default.fileExists(atPath: AppPaths.soundURL(named: $0).path) }) {
            files = nil
        }
        if files == nil {
            let old = Set((alarm.chimeSlotSoundFiles ?? []) + [alarm.soundFileName])
            let composed = await Task.detached(priority: .userInitiated) {
                ChimeSoundComposer.composeSlots(slots, locale: locale, voice: voice)
            }.value
            if let composed, let first = composed.first {
                alarm.chimeSlotSoundFiles = composed
                alarm.soundFileName = first
                for o in old where !composed.contains(o) { ChimeSoundComposer.removeChimeFile(named: o) }
                files = composed
                print("🔔 AlarmScheduler.chime: (re)composed \(composed.count) slot file(s) for \(alarm.id.uuidString.prefix(8))")
            } else if !alarm.soundFileName.isEmpty,
                      FileManager.default.fileExists(atPath: AppPaths.soundURL(named: alarm.soundFileName).path) {
                // 合成失敗（極少數）→ 至少讓每個時刻都用舊的那句報時，不會無聲。
                files = Array(repeating: alarm.soundFileName, count: slots.count)
                print("🔔 AlarmScheduler.chime: ⚠️ compose failed — reusing \(alarm.soundFileName) for all \(slots.count) slot(s)")
            }
        }
        guard let files else {
            print("🔔 AlarmScheduler.chime: ⚠️ no chime sound available for \(alarm.id.uuidString.prefix(8)) — nothing scheduled")
            return
        }

        // 2. 額度：扣掉「不是這顆鬧鐘」的 pending（自己的會被同 id add 取代，不佔新額度）。
        let pending = await center.pendingNotificationRequests()
        let others = pending.filter { !$0.identifier.hasPrefix(alarm.id.uuidString) }.count
        var budget = max(0, 64 - others - 2)

        let cal = Calendar.current
        let daily = Set(alarm.weekdays) == Set(1...7)
        var added = 0
        var slotSeconds: [Double] = []

        for (s, slot) in slots.enumerated() {
            let file = files[s]
            let content = makeChimeContent(alarm: alarm, hour: slot.hour, minute: slot.minute,
                                           soundFile: file, locale: locale,
                                           timeSensitiveEnabled: timeSensitiveEnabled)
            var secs: Double = 3
            if let caf = try? AVAudioFile(forReading: AppPaths.soundURL(named: file)) {
                secs = max(1, Double(caf.length) / caf.fileFormat.sampleRate)
            }
            slotSeconds.append(secs)

            var comps = DateComponents()
            comps.hour = slot.hour; comps.minute = slot.minute
            if alarm.weekdays.isEmpty {
                // 單次：下一次發生（今天或明天）
                guard budget > 0,
                      let fire = cal.nextDate(after: Date(), matching: { var c = comps; c.second = 0; return c }(),
                                              matchingPolicy: .nextTime) else { continue }
                let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let req = UNNotificationRequest(
                    identifier: AlarmNotificationIDs.chimeSlot(alarm.id, slot: s), content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
                if (try? await center.add(req)) != nil { added += 1; budget -= 1 }
            } else if daily {
                guard budget > 0 else { break }
                let req = UNNotificationRequest(
                    identifier: AlarmNotificationIDs.chimeSlot(alarm.id, slot: s), content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
                if (try? await center.add(req)) != nil { added += 1; budget -= 1 }
            } else {
                for wd in alarm.weekdays {
                    guard budget > 0 else { break }
                    var c = comps; c.weekday = wd
                    let req = UNNotificationRequest(
                        identifier: AlarmNotificationIDs.chimeSlot(alarm.id, slot: s, weekday: wd), content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true))
                    if (try? await center.add(req)) != nil { added += 1; budget -= 1 }
                }
            }
        }
        print("🔔 AlarmScheduler.chime: \(alarm.id.uuidString.prefix(8)) \(slots.count) slot(s) × \(alarm.weekdays.isEmpty ? "once" : (daily ? "daily" : "\(alarm.weekdays.count) day(s)")) → \(added) request(s), voice=\(voice.rawValue), budgetLeft=\(budget)")

        // 3. 連報 N 次：每個時刻的「下一次發生」補排第 2…N 顆（一次性，每次 re-arm 重排）。
        let count = alarm.effectiveChimeCount
        guard count > 1 else { return }
        var extra = 0
        for (s, slot) in slots.enumerated() {
            guard let next = nextOccurrence(hour: slot.hour, minute: slot.minute, weekdays: alarm.weekdays) else { continue }
            // 兩句報時之間的間距（秒）＝一句長度 + ~1s 喘息，至少 2 秒；slot 秒位須 < 60 留在同一分鐘內。
            let period = max(2, Int(ceil(slotSeconds[s])) + 1)
            let content = makeChimeContent(alarm: alarm, hour: slot.hour, minute: slot.minute,
                                           soundFile: files[s], locale: locale,
                                           timeSensitiveEnabled: timeSensitiveEnabled)
            for k in 2...count {
                let off = period * (k - 1)
                guard off < 60, budget > 0, let date = cal.date(byAdding: .second, value: off, to: next) else { break }
                let parts = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                let req = UNNotificationRequest(
                    identifier: AlarmNotificationIDs.chimeSlotRepeat(alarm.id, slot: s, k), content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
                if (try? await center.add(req)) != nil { extra += 1; budget -= 1 }
            }
        }
        print("🔔 AlarmScheduler.chime: repeats ×\(count) → +\(extra) one-shot(s) (budgetLeft=\(budget))")
    }

    /// 報時橫幅：標題＝鬧鐘標籤（沒有就「報時」），內文＝跟語音念的一模一樣（早上七點零五分）。
    private func makeChimeContent(alarm: Alarm, hour: Int, minute: Int, soundFile: String,
                                  locale: Locale, timeSensitiveEnabled: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let label = alarm.label.trimmingCharacters(in: .whitespaces)
        content.title = label.isEmpty ? L("chime_notification_title") : label
        content.body = ChimeSoundComposer.phrase(hour: hour, minute: minute, locale: locale)
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: soundFile))
        content.categoryIdentifier = "SUNNYWAKE_ALARM"
        content.threadIdentifier = alarm.id.uuidString
        content.interruptionLevel = timeSensitiveEnabled ? .timeSensitive : .active
        content.userInfo = [
            "alarmID": alarm.id.uuidString,
            "requireAppToStop": false,
            // 點橫幅只回主畫面（報時放完就停，沒有「關鬧鐘」的需求）。AppDelegate.didReceive 讀這個 key。
            "backgroundMode": AlarmBackgroundMode.notification.rawValue
        ]
        return content
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
                identifier: AlarmNotificationIDs.nag(alarm.id, k), content: content, trigger: trigger
            )
            try? await center.add(req)
        }
        print("🔔 AlarmScheduler: strict mode — scheduled \(n) nag(s) after \(fireDate)")
    }

    // MARK: - 溫和提醒「響滿 ~30s」堆疊（gentle-repeat burst）


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
        // 兩顆通知 fire 時間的間距（秒）＝一段語音長度 + 切段間隔（burstGapSeconds，1 或 2，預設 2）。
        // 2026-08-14 起與 recordingGapSeconds 脫鉤：那顆同時控制 in-app 循環播放；多裝置實測
        // 通知沒聲音時要能單獨調切段間距（1s vs 2s 對照）而不改響鈴節奏。
        let gap = max(0, AppSettings.shared.burstGapSeconds)
        let period = max(2, Int(ceil(voiceSeconds)) + gap)
        // 目標總響鈴長度（秒）——家長可在設定選 10/20/30，預設 30（原本寫死的值）。
        let targetSpan = AppSettings.shared.effectiveBurstSpanSeconds

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
        let slots = Array(offsets.prefix(min(budget, AlarmNotificationIDs.maxRepeatSlots)))
        if slots.count < offsets.count {
            print("🔔 AlarmScheduler: gentle-repeat burst TRUNCATED — planned \(offsets.count) slots, room for \(slots.count) (pending=\(pendingNow), maxRepeatSlots=\(AlarmNotificationIDs.maxRepeatSlots))")
        }

        let cal = Calendar.current
        var added = 0
        for (i, off) in slots.enumerated() {
            guard let slotDate = cal.date(byAdding: .second, value: off, to: fireDate) else { continue }
            let parts = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: slotDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let req = UNNotificationRequest(
                identifier: AlarmNotificationIDs.repeatSlot(alarm.id, i + 1), content: content, trigger: trigger
            )
            do { try await center.add(req); added += 1 } catch {
                print("🔔 AlarmScheduler: gentle-repeat slot \(i + 1) add failed — \(error.localizedDescription)")
            }
        }
        // 🔬 多裝置「有時沒聲音」實測用完整計畫 log：baseline 在 fireDate+0s，其餘每顆的
        // offset 一起印，對照裝置端「實際響了幾聲」（WakeRecord 響鈴診斷）就能定位是
        // 排程端少排、還是 iOS 收掉/靜音。sound log 在上方 CUSTOM/BUNDLED banner 行。
        let hhmmss = { (d: Date) -> String in
            let c = cal.dateComponents([.hour, .minute, .second], from: d)
            return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        }
        print("🔬 BurstPlan[\(alarm.id.uuidString.prefix(8))]: baseline@\(hhmmss(fireDate)) +\(slots.map(String.init).joined(separator: "s,+"))s | period=\(period)s (voice=\(String(format: "%.1f", voiceSeconds))s + burstGap=\(gap)s) added=\(added)/\(slots.count) pendingWas=\(pendingNow) sound=\(alarm.soundFileName)")
    }

    /// Soonest future fire date across an alarm's weekdays (for scheduling strict-mode nags / bursts).
    private func nextOccurrence(for alarm: Alarm) -> Date? {
        nextOccurrence(hour: alarm.hour, minute: alarm.minute, weekdays: alarm.weekdays)
    }

    /// 給定時刻 + 星期集合的下一次發生（星期空＝今天或明天）。
    private func nextOccurrence(hour: Int, minute: Int, weekdays: [Int]) -> Date? {
        var comps = DateComponents()
        comps.hour = hour; comps.minute = minute; comps.second = 0
        let cal = Calendar.current
        if weekdays.isEmpty {
            return cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime)
        }
        var best: Date?
        for wd in weekdays {
            var c = comps; c.weekday = wd
            if let d = cal.nextDate(after: Date(), matching: c, matchingPolicy: .nextTime),
               best == nil || d < best! {
                best = d
            }
        }
        return best
    }

    /// Cancel only the follow-up notifications for an alarm (leaves the main alarm intact so
    /// a repeating alarm still fires next time). Called when the app opens for the ringing alarm.
    /// 連 gentle-repeat burst / 報時連報一起清——app 為這顆鬧鐘開起來＝小孩醒了，後續語音不該再響。
    func cancelNags(_ alarmID: UUID) {
        let ids = AlarmNotificationIDs.followUps(for: alarmID)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        print("🔔 AlarmScheduler: cancelled follow-ups for \(alarmID.uuidString.prefix(8))")
    }

    /// 清掉這顆鬧鐘在系統裡的【每一顆】通知（baseline + 後續 + 區間報時 slot）。刪除／停用時用。
    func cancel(_ alarmID: UUID) {
        let identifiers = AlarmNotificationIDs.all(for: alarmID)
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

// MARK: - 升級後聲音自癒（App 更新 → 自訂鈴聲變系統「咚」聲）

/// App 更新（TestFlight / App Store 換 build）會把 .app bundle 與 app container 搬到新的 UUID
/// 路徑。更新【前】排進系統的東西——AlarmKit daemon 條目、pending UNNotification、以及
/// sound server 的「檔名→路徑」快取——仍握著舊路徑的參照；自訂音解析失敗時 iOS 一律【靜默】
/// 退成預設「咚」聲（鬧鐘照響、只是聲音不對，使用者回報的正是這個）。
///
/// 修法＝偵測 build 變更後，把每顆鬧鐘的聲音檔用【新檔名】重匯出（沿用錄音 CAF 的 epoch
/// 檔名機制——同名重寫繞不過快取，換名才行），再交給既有流程重排：
///   • 通知模式：HomeView.task 啟動時 schedule() 以新檔名重排（add() 同 id 直接取代）。
///   • AlarmKit 模式：離開前景時 enterBackgroundAlarmMode → syncAlarm 以新 soundFileName 重註冊。
/// ⚠️ 更新後、第一次開 app 之前就響的那一顆救不了（系統端已握舊參照）——開一次 app 即痊癒。
@MainActor
enum AlarmSoundUpgradeHealer {
    private static let lastHealedBuildKey = "alarmSoundHealBuild"

    static func healIfNeeded(alarms: [Alarm]) async {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let last = UserDefaults.standard.string(forKey: lastHealedBuildKey)
        guard last != build else { return }
        print("🩹 SoundHealer: build \(last ?? "首次") → \(build) — 重匯出 \(alarms.count) 顆鬧鐘的聲音（繞過更新後的 stale 路徑/快取）")
        for alarm in alarms { await heal(alarm) }
        UserDefaults.standard.set(build, forKey: lastHealedBuildKey)
    }

    /// 先修舊版資料的欄位組合（否則 schedule() 的分支判斷會直接落 .default），再換新檔名重匯。
    /// 匯出（整段錄音讀進記憶體再寫 CAF）走背景執行緒——這裡是 app 啟動第一畫面，卡 main 會白屏。
    private static func heal(_ alarm: Alarm) async {
        guard !alarm.isTodo else { return }   // 待辦不發通知、無聲音檔
        if alarm.isChimeAlarm {
            // 報時音檔（chime_*.caf）也在 Library/Sounds，同樣中更新後 stale 路徑/快取的雷。
            // 只把 slot 檔清單標成「需重合成」——實際合成在 AlarmScheduler.scheduleChime（背景執行緒、
            // 全成功才換檔、順手刪舊檔）。soundFileName 刻意保留：isChimeAlarm 靠它的 chime_ 前綴判斷。
            alarm.chimeSlotSoundFiles = nil
            print("🩹 SoundHealer: \(alarm.id.uuidString.prefix(8)) chime marked for recompose")
            return
        }
        func recordingExists(_ name: String) -> Bool { AppPaths.recordingExists(named: name) }

        if alarm.recordingName.isEmpty, alarm.soundFileName.hasPrefix("alarm_"),
           let base = recordingBase(fromCAFName: alarm.soundFileName) {
            // 舊版資料：soundFileName 指向錄音 CAF 但 recordingName 沒跟上 → wantsCustom 不成立
            // → 永遠 .default。從 CAF 檔名反推錄音名補回來。
            if recordingExists(base) {
                alarm.recordingName = base
                print("🩹 SoundHealer: \(alarm.id.uuidString.prefix(8)) recovered recordingName=\(base) from \(alarm.soundFileName)")
            } else {
                alarm.soundFileName = "sunny_wake.caf"   // 源頭錄音已不在 → 回內建預設（有聲，不是「咚」）
                print("🩹 SoundHealer: \(alarm.id.uuidString.prefix(8)) source m4a gone — reset to sunny_wake.caf")
            }
        } else if !alarm.recordingName.isEmpty, !recordingExists(alarm.recordingName) {
            // 錄音已被刪（VoiceLibrary 刪 clip 不回寫 alarm）→ 清掉、回內建預設。
            alarm.recordingName = ""
            if !alarm.soundFileName.isEmpty,
               Bundle.main.url(forResource: alarm.soundFileName, withExtension: nil) == nil {
                alarm.soundFileName = "sunny_wake.caf"
            }
            print("🩹 SoundHealer: \(alarm.id.uuidString.prefix(8)) recording deleted — fell back to bundled default")
        } else if !alarm.recordingName.isEmpty, alarm.soundFileName != "sunny_wake.caf",
                  Bundle.main.url(forResource: alarm.soundFileName, withExtension: nil) != nil {
            // 舊版選了內建鈴聲但沒清 recordingName（現在的 editor 會清）→ wantsCustom 誤判去
            // Library/Sounds 找內建檔 → .default。以較晚的選擇（內建鈴聲）為準。
            alarm.recordingName = ""
            print("🩹 SoundHealer: \(alarm.id.uuidString.prefix(8)) bundled selection with stale recordingName — cleared")
        }

        // 換新檔名重匯出，讓 sound server / AlarmKit 不可能命中更新前的 stale 參照。
        let recording = alarm.recordingName
        let bundled = alarm.soundFileName
        if !recording.isEmpty {
            if let caf = await Task.detached(priority: .userInitiated, operation: {
                AlarmSoundExporter.exportLockScreenCAF(fromRecordingNamed: recording)
            }).value {
                alarm.soundFileName = caf
            }
        } else if Bundle.main.url(forResource: bundled, withExtension: nil) != nil {
            _ = await Task.detached(priority: .userInitiated) {
                AlarmSoundExporter.exportBundledShortCAF(bundledName: bundled, regenerate: true)
            }.value
        }
    }

    /// `alarm_<base>_<epoch>.caf` → `<base>`（base 可含底線；epoch 是最後一段純數字）。
    private static func recordingBase(fromCAFName name: String) -> String? {
        var stem = (name as NSString).deletingPathExtension
        guard stem.hasPrefix("alarm_") else { return nil }
        stem.removeFirst("alarm_".count)
        guard let cut = stem.lastIndex(of: "_"), Int(stem[stem.index(after: cut)...]) != nil else { return nil }
        let base = String(stem[..<cut])
        return base.isEmpty ? nil : base
    }
}
