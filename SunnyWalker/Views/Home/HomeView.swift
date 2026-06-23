// SunnyWalker — HomeView.swift  |  Day 20  |  DEBUG overlay removed; bed-side mode

import SwiftUI
import SwiftData
import UIKit
import AVFoundation   // AVAudioSession — release the capture session on background so the UN alarm sound isn't ducked

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: [SortDescriptor(\Alarm.hour), SortDescriptor(\Alarm.minute)])
    private var alarms: [Alarm]

    // Drives alarm-ring routing when the app is resumed from the background (e.g. after the
    // user unlocks and taps the AlarmKit stop button on the lock screen).
    @Environment(\.scenePhase) private var scenePhase

    @State private var currentTime = Date()

    // FAB hint: which icon's label capsule is currently shown. Default nil keeps the bar clean;
    // long-pressing an icon reveals its hint for ~1.6s. See revealHint(_:) / FabHint.
    @State private var hintedFab: String? = nil

    // Max number of alarms a parent can keep (free-tier cap from FeatureLimits; Pro = unlimited).
    // The "+" flow is blocked (with an alert) once this is reached. See openAddAlarmFlow().
    private var maxAlarms: Int { FeatureLimits.maxAlarms }
    @State private var showingMaxAlarmsAlert = false

    // "+" (add alarm) gate states
    @State private var showingParentalGate = false
    @State private var gateDidSucceed = false
    @State private var showingAddAlarm = false

    // Notification-driven / long-press alarm ring
    @State private var firingAlarm: Alarm?

    // Multi-person alarm groups: which group page the home list is currently showing.
    // 0 = group A. Clamped whenever the parent lowers the group count / disables grouping.
    @State private var homeGroupSelection = 0

    // Day 19: bed-side mode
    @StateObject private var bedSide = BedSideManager.shared

    // Language switching — no parental gate, accessible to kids
    @ObservedObject private var localization = LocalizationManager.shared

    // App settings (drives background-listening start/stop)
    @ObservedObject private var settings = AppSettings.shared


    // Settings — gated behind parental gate at the button level
    @State private var showingParentalForSettings = false
    @State private var gateSettingsOK = false
    @State private var showingSettings = false

    // Group on/off (home banner) — also gated behind the parental gate
    @State private var showingParentalForGroup = false
    @State private var groupGateOK = false
    @State private var pendingGroupToggle: Int? = nil

    // Drives only the time-of-day scene (background gradient + clock color), which can
    // only change on an hour boundary — a 60s cadence is plenty. The per-second clock
    // redraw lives in ClockHeaderView so it no longer invalidates the whole screen
    // (animated background, cloud layer, mascot, and the alarm list) every second.
    private let sceneTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    // Foreground in-app alarm: while the app is on-screen we present AlarmRingView OURSELVES (which
    // owns the audio session → mic + parent recording work, so voice-stop works) instead of leaving
    // the alarm to the AlarmKit black banner, which seizes the audio session. Ticks every second
    // while the view is visible (cheap: a few date comparisons). See checkForegroundAlarm().
    @State private var lastForegroundFiredKey: String?
    @State private var lastForegroundGuardLogMinute: Int = -1   // throttle checkForegroundAlarm logs
    private let foregroundAlarmTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var scene: DaytimeScene {
        DaytimeScene.current(hour: Calendar.current.component(.hour, from: currentTime))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            background
            CloudBackground(scene: scene, isActive: scenePhase == .active)
            PaperTextureOverlay(tint: scene.colorGrade)
            if sizeClass == .regular {
                // iPad: GeometryReader distinguishes landscape (width > height) from portrait.
                // The prior sizeClass == .regular && vSizeClass == .compact condition was dead code
                // because iPad landscape gives verticalSizeClass = .regular, not .compact.
                GeometryReader { geo in
                    if geo.size.width > geo.size.height {
                        // iPad landscape: compact two-column with smaller clock to avoid clipping
                        HStack(spacing: 0) {
                            VStack(spacing: 8) {
                                ClockHeaderView(fontSize: 52, textColor: scene.clockTextColor)
                                    .padding(.top, 32)
                                    .padding(.bottom, 8)
                                MascotView(tappable: true, scene: scene,
                                           themeOverride: settings.groupEnabled ? settings.groupMascot(homeGroupSelection) : nil)
                                    .overlay(alignment: .topTrailing) {
                                        TodoBadgesView(group: settings.groupEnabled ? homeGroupSelection : nil)
                                            .offset(x: 14, y: 6)
                                    }
                                    .scaleEffect(0.75)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            alarmColumn()
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        // iPad portrait: side-by-side clock/avatar | alarm list
                        HStack(spacing: 0) {
                            VStack(spacing: 0) {
                                ClockHeaderView(fontSize: 76, textColor: scene.clockTextColor)
                                    .padding(.top, 56)
                                    .padding(.bottom, 16)
                                MascotView(tappable: true, scene: scene,
                                           themeOverride: settings.groupEnabled ? settings.groupMascot(homeGroupSelection) : nil)
                                    .overlay(alignment: .topTrailing) {
                                        TodoBadgesView(group: settings.groupEnabled ? homeGroupSelection : nil)
                                            .offset(x: 14, y: 6)
                                    }
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            alarmColumn()
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                // iPhone: ONE continuous scroll, like the built-in Clock app. Clock + mascot are the
                // first scrolling rows above the alarm cards, so the whole page reads as a single long
                // strip you can drag up/down freely (no pinned header, no separate panel, no scrollbar).
                // When grouping is on, this becomes a horizontal pager (one page per group).
                iphoneAlarmList()
            }
            addButton
        }
        .ignoresSafeArea(edges: .top)
        // Keep the visible group page valid when the parent lowers the count or disables grouping.
        .onChange(of: settings.effectiveGroupCount) { _, n in
            if homeGroupSelection >= n { homeGroupSelection = max(0, n - 1) }
        }
        .onAppear {
            checkPendingAlarm()
        }
        // Use .task(id:) instead of onAppear so sync re-fires when @Query finishes loading.
        // onAppear fires before SwiftData populates @Query → alarms is [] on first call.
        // Triggering on alarms.count catches the initial load (0 → N) and any add/delete.
        .task(id: alarms.count) {
            guard !alarms.isEmpty else { return }
            if AlarmKitService.shared.isAuthorized {
                // We launched in the FOREGROUND → in-app ring mode: cancel AlarmKit so its system
                // alarm UI can't appear (it would background the app and kill voice-stop). AlarmKit
                // is re-armed the moment we leave the foreground (scenePhase handler) so the
                // lock-screen / silent-mode alarm still works. See enterForegroundAlarmMode().
                enterForegroundAlarmMode()
                // ★ 2026-06-12：通知模式的鬧鐘在【前景啟動】時可靠地（補）排一次 .timeSensitive 通知。
                //   背景轉場故意不排（remove-readd 會被 force-quit 中斷 → 通知遺失，就是「提醒模式
                //   什麼都沒發生」的根因）。前景 add() 一定跑得完，所以放這裡補；repeats:true 會自己持續存在。
                for alarm in alarms where alarm.isEnabled
                    && !alarm.isTodo
                    && alarm.effectiveBackgroundMode == .notification
                    && AppSettings.groupAllowsFiring(alarm.effectiveGroupIndex) {
                    try? await AlarmScheduler.shared.schedule(alarm: alarm)
                }
            } else {
                // AlarmKit unavailable → UNNotification fallback fires; re-arm on every launch.
                print("🏠 HomeView.task: AlarmKit NOT authorized — re-arming \(alarms.count) alarms on UNNotification path")
                for alarm in alarms {
                    try? await AlarmScheduler.shared.syncWithModel(alarm: alarm)
                }
            }
            // @Query may have been empty when onAppear ran (killed-state launch). Retry routing
            // now that alarms are loaded so a pending alarm can resolve to a real Alarm object.
            checkPendingAlarm()
            syncBackgroundListening()
        }
        .onChange(of: settings.backgroundListeningEnabled) { _, _ in
            syncBackgroundListening()
        }
        .onChange(of: firingAlarm != nil) { _, ringing in
            // Free the mic for AlarmRingView while it's up (two AVAudioEngines would clash);
            // resume the keep-alive listener once it's dismissed.
            if ringing {
                BackgroundListeningManager.shared.stop()
            } else if settings.backgroundListeningEnabled {
                BackgroundListeningManager.shared.start()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Background-resume case: after StopAlarmIntent foregrounds the app, onAppear does
            // NOT fire again and the ephemeral .alarmFired post can be lost. Re-check the pending
            // alarm on every activation so the in-app wake screen reliably appears — without this
            // the alarm just goes silent when the user unlocks. (Fixes "解鎖鐘就停了".)
            if newPhase == .active {
                print("🏠 HomeView.scenePhase → active; re-checking pending alarm")
                // Foreground needs no keep-alive: tear down silent audio / watchdog / timers
                // (armedAlarms + BGTask stay as Layer-1 insurance; enterForegroundAlarmMode's
                // stop() chain disarms them one by one).
                // ⚠️ firingAlarm != nil 時不要動 — AlarmRingView 擁有 audio session，
                // endBackgroundLifecycle 的 setActive(false) 會跟 in-app 鈴聲打架（560557684 雷）。
                if firingAlarm == nil {
                    AlarmAutoStopService.shared.endBackgroundLifecycle()
                }
                // Fallback: stop any alarm that outlived its ring window (covers the case where
                // BGProcessingTask / DispatchTimer didn't fire before user opened the app).
                AlarmAutoStopService.shared.checkAndStopOverdue()
                // 把背景 auto-stop 留下的 timeout 記錄轉入 SwiftData（準時率/回應率統計）。
                // 延遲 0.5s：等 checkAndStopOverdue 的 async stop/queue 跑完再 drain；
                // 萬一沒趕上，殘餘 pending 會在下次 .active 時補入庫（queue 不會掉資料）。
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    drainTimeoutRecords()
                }
                checkPendingAlarm()
                // Foreground = in-app ring. Cancel AlarmKit so it can't fire its system banner while
                // we're on-screen (which would background us and break voice-stop). The 1s
                // foregroundAlarmTick presents AlarmRingView when an alarm is due.
                enterForegroundAlarmMode()
                // Smart background-listening: only start mic when app is in foreground.
                // If enabled AND no alarm is ringing, restart the session now.
                if settings.backgroundListeningEnabled && firingAlarm == nil {
                    syncBackgroundListening()
                }
            } else {
                // Leaving foreground → re-arm AlarmKit so the lock-screen / silent-mode alarm works.
                // ★ Issue #2 根因之一：原本「無條件」呼叫。當 AlarmRingView 正在響鈴
                //   （firingAlarm != nil）時，AlarmRingView 的 AudioPlayer 擁有並要保住 audio
                //   session 才能在關屏時繼續響；此時 enterBackgroundAlarmMode 會 syncAllEnabled
                //   重排 AlarmKit + beginBackgroundLifecycle（註冊中斷觀察者 / 可能 setActive +
                //   切 .mixWithOthers）→ 跟 in-app 鈴聲搶 session → 關屏瞬間就沒聲。
                //   而且這次響鈴的這顆鬧鐘根本不該被重排（in-app ring 已經接手）。
                //   → 響鈴中不要動 AlarmKit / 背景 keep-alive，把 session 完全留給 AlarmRingView。
                if firingAlarm == nil {
                    enterBackgroundAlarmMode()
                } else {
                    print("🏠 HomeView.scenePhase → \(newPhase): alarm ringing in-app — SKIP enterBackgroundAlarmMode (AlarmRingView owns the session)")
                }
                // Screen locked / app backgrounded → ALWAYS release the mic + audio session.
                // Two reasons:
                //   (1) Battery / App Store: no always-on orange mic dot overnight.
                //   (2) ★ The real "關屏只彈訊息、沒鈴聲" bug: an active .playAndRecord session
                //       (from 聲控模式 / the foreground voice-stop feature) DUCKS / suppresses the
                //       UNNotification alarm sound — and while the app is suspended that notification
                //       is the ONLY ringer. If we leave ANY capture session active here, the alarm
                //       banner pops but plays no sound. So tear the whole session down unconditionally,
                //       not just BackgroundListeningManager's (the foreground feature may have left a
                //       SpeechRecognizer/AudioPlayer session active that BGListen.stop() won't touch).
                if firingAlarm == nil {
                    let sess = AVAudioSession.sharedInstance()
                    let prevCat = sess.category
                    // ALWAYS stop the mic/capture session: a leftover .playAndRecord session (聲控 /
                    // 背景聆聽 / foreground voice-stop) ducks the ringer, which is the ONLY sound while
                    // the app is suspended. This is the actual fix for issue#2 ("關屏只彈訊息、沒鈴聲").
                    BackgroundListeningManager.shared.stop()   // no-op if it wasn't the one that's active
                    // ★ But do NOT blanket-deactivate the session when AlarmAutoStop needs its 0-vol
                    //   .playback keep-alive alive. That keep-alive is what keeps the app running in the
                    //   background so the DispatchTimer can fire stop() at stopAt. The unconditional
                    //   setActive(false) (added for issue#2) killed it — log shows
                    //   prevCategory=AVAudioSessionCategoryPlayback — so a 1-min alarm with the app
                    //   closed + screen off never auto-stops. A .mixWithOthers 0-vol playback session
                    //   does NOT duck AlarmKit's SpringBoard ring, so it is safe to keep here.
                    //   (Killing the mic above already handles the issue#2 ducking culprit.)
                    if AlarmKitService.shared.isAuthorized,
                       AlarmAutoStopService.shared.keepAliveNeededNow() {
                        // ★ 2026-06-12：不只「保留 session」，而是立刻把 0 音量 keep-alive 音訊
                        //   播起來，讓 audio background mode 在進背景第一時間就生效，撐過
                        //   enterBackgroundAlarmMode 的 `await syncAllEnabled` IPC 空窗。
                        //   原本要等那段 async 之後才 startSilentAudio，空窗期沒有正在播放的音訊 →
                        //   app 可能在 keep-alive 啟動前就被 iOS suspend/terminate（真機 log：
                        //   applicationWillTerminate 出現在 startSilentAudio 之前）。
                        //   ⚠️ 注意：force-quit（上滑殺 app）此修法救不了——process 直接消失，
                        //   沒有任何 app-side keep-alive 能撐住；那是 iOS 平台限制。
                        AlarmAutoStopService.shared.ensureKeepAliveAudioNow()
                        print("🏠 HomeView.scenePhase → \(newPhase): stopped mic, STARTED keep-alive audio NOW for AlarmAutoStop (prevCategory=\(prevCat.rawValue))")
                    } else {
                        try? sess.setActive(false, options: [.notifyOthersOnDeactivation])
                        print("🏠 HomeView.scenePhase → \(newPhase): released mic + audio session so the UN alarm sound isn't ducked (prevCategory=\(prevCat.rawValue), bgListenActive=\(BackgroundListeningManager.shared.isActive))")
                    }
                } else {
                    // An alarm is ringing in-app (AlarmRingView) — it owns the audio session and
                    // needs it alive to keep playing while the screen is off. Don't tear it down.
                    print("🏠 HomeView.scenePhase → \(newPhase): alarm ringing in-app — keeping audio session for AlarmRingView")
                }
            }
        }
        .onReceive(sceneTick) { currentTime = $0 }
        .onReceive(foregroundAlarmTick) { _ in checkForegroundAlarm() }
        .onReceive(NotificationCenter.default.publisher(for: .alarmFired)) { note in
            print("🏠 HomeView.onReceive(.alarmFired): object=\(String(describing: note.object))")
            guard let uuidString = note.object as? String,
                  let uuid = UUID(uuidString: uuidString),
                  let alarm = alarms.first(where: { $0.id == uuid }) else {
                print("🏠 HomeView.onReceive: no matching alarm in \(alarms.count) loaded alarms — ignored")
                return
            }
            // If the user just turned this alarm off via the banner ✕, do NOT re-open the ring.
            if wasRecentlyDismissed(uuid) {
                print("🏠 HomeView.onReceive: alarm \(uuid.uuidString.prefix(8)) was just ✕-dismissed — NOT routing")
                return
            }
            // Consume the pending-alarm marker so a later background-resume doesn't re-trigger
            // the ring spuriously (the scenePhase/onAppear paths read the same marker).
            UserDefaults.standard.removeObject(forKey: "pendingAlarmKitAlarmID")
            (UIApplication.shared.delegate as? AppDelegate)?.pendingAlarmID = nil
            print("🏠 HomeView.onReceive: routing → AlarmRingView for \(uuid.uuidString.prefix(8))")
            presentRing(alarm)
        }
        .fullScreenCover(item: $firingAlarm) { alarm in
            AlarmRingView(alarm: alarm)
        }
    }

    // Handles the killed-state case: AppDelegate stored the alarm ID before HomeView was ready.
    // Accepts an injected delegate to allow unit testing without UIApplicationMain.
    func checkPendingAlarm(delegate: AppDelegate? = UIApplication.shared.delegate as? AppDelegate) {
        // Two sources, in priority order:
        //  1. AppDelegate.pendingAlarmID — set during a killed-state launch.
        //  2. UserDefaults "pendingAlarmKitAlarmID" — set by StopAlarmIntent and still present
        //     when the app was only backgrounded (didFinishLaunching never re-ran to drain it).
        var pendingID = delegate?.pendingAlarmID
        if pendingID == nil {
            pendingID = UserDefaults.standard.string(forKey: "pendingAlarmKitAlarmID")
        }
        let udKey = UserDefaults.standard.string(forKey: "pendingAlarmKitAlarmID")
        print("🏠 checkPendingAlarm: delegate.pendingAlarmID=\(delegate?.pendingAlarmID ?? "nil") udKey=\(udKey ?? "nil")")
        guard let id = pendingID else {
            print("🏠 checkPendingAlarm: no pending ID — AlarmRingView will NOT be shown (DismissAlarmIntent never writes this key)")
            return
        }
        guard let uuid = UUID(uuidString: id) else {
            // Invalid marker: consume it so we don't retry forever.
            delegate?.pendingAlarmID = nil
            UserDefaults.standard.removeObject(forKey: "pendingAlarmKitAlarmID")
            return
        }
        guard let alarm = alarms.first(where: { $0.id == uuid }) else {
            print("🏠 HomeView.checkPendingAlarm: pending=\(id.prefix(8)) but no matching alarm (alarms=\(alarms.count)) — will retry on next load")
            return
        }
        // Consume from both sources only after the alarm exists. On launch, @Query may be empty
        // on the first pass; clearing early loses the killed-state route before the retry.
        delegate?.pendingAlarmID = nil
        UserDefaults.standard.removeObject(forKey: "pendingAlarmKitAlarmID")
        // The user may have ✕-dismissed this exact fire — don't resurrect it on the next foreground.
        if wasRecentlyDismissed(uuid) {
            print("🏠 HomeView.checkPendingAlarm: alarm \(uuid.uuidString.prefix(8)) was just ✕-dismissed — NOT routing")
            return
        }
        print("🏠 HomeView.checkPendingAlarm: routing → AlarmRingView for \(uuid.uuidString.prefix(8))")
        presentRing(alarm)
    }

    /// Present the in-app ring screen for `alarm`. ⚠️ AlarmRingView is a `.fullScreenCover` on
    /// HomeView, but Settings / Add-alarm / parental-gate are `.sheet`s on the SAME view — SwiftUI
    /// only allows ONE presentation at a time, so a due alarm could NOT show its ring while a sheet
    /// was open (e.g. the parent is on the Settings page / just toggled 床邊模式) until the sheet was
    /// manually closed — the reported "開設定頁時鬧鐘不會動" bug. Fix: close any open sheet first,
    /// then present the cover on the next runloop (avoids a present-while-dismissing race).
    private func presentRing(_ alarm: Alarm) {
        bedSide.disable()   // restore brightness if 床邊模式 dimmed the screen
        let sheetWasOpen = showingSettings || showingAddAlarm
            || showingParentalGate || showingParentalForSettings || showingParentalForGroup
        guard sheetWasOpen else {
            firingAlarm = alarm
            return
        }
        print("🏠 presentRing: a sheet was open → closing it first, then presenting ring for \(alarm.id.uuidString.prefix(8))")
        showingSettings = false
        showingAddAlarm = false
        showingParentalGate = false
        showingParentalForSettings = false
        showingParentalForGroup = false
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.35))   // let the sheet finish dismissing
            firingAlarm = alarm
        }
    }

    /// While the app is on-screen, fire the alarm IN-APP (full-screen AlarmRingView) rather than via
    /// the AlarmKit system banner. The app then owns the audio session, so the parent recording plays
    /// AND the mic/speech runs → the child can voice-stop. We also stop the AlarmKit ring for this
    /// occurrence so its banner doesn't seize the session, then re-arm it for the next occurrence.
    ///
    /// Trade-off: AlarmKit fires at the same minute, so there can be a ≤1s banner/sound flash before
    /// we catch it and AlarmRingView covers the screen. Only runs while AlarmKit is authorized and
    /// the app is .active; in the background AlarmKit owns the alarm (voice-stop isn't possible then).
    private func checkForegroundAlarm() {
        guard scenePhase == .active, firingAlarm == nil, AlarmKitService.shared.isAuthorized else {
            // Log guard failures once per minute to avoid spam
            let nowMin = Calendar.current.component(.minute, from: Date())
            if nowMin != lastForegroundGuardLogMinute {
                lastForegroundGuardLogMinute = nowMin
                print("🏠 checkForegroundAlarm GUARD: scenePhase=\(scenePhase) firingAlarm=\(firingAlarm?.id.uuidString.prefix(8) ?? "nil") akAuthorized=\(AlarmKitService.shared.isAuthorized)")
            }
            return
        }
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute, .weekday, .day], from: Date())
        guard let h = c.hour, let m = c.minute, let wd = c.weekday, let day = c.day else { return }
        // Log current time vs enabled alarms once per minute
        let nowMin = Calendar.current.component(.minute, from: Date())
        if nowMin != lastForegroundGuardLogMinute {
            lastForegroundGuardLogMinute = nowMin
            let alarmSummary = alarms.filter(\.isEnabled).map { "\($0.id.uuidString.prefix(8)) \($0.hour):\(String(format: "%02d", $0.minute))" }.joined(separator: ", ")
            print("🏠 checkForegroundAlarm: now=\(h):\(String(format: "%02d", m)) wd=\(wd) enabledAlarms=[\(alarmSummary)]")
        }
        for a in alarms where a.isEnabled && a.hour == h && a.minute == m
            && AppSettings.groupAllowsFiring(a.effectiveGroupIndex) {
            // 待辦語音提醒不會響：跳過（它只在主頁吉祥物旁冒圖示，由 TodoBadgesView 處理）。
            if a.isTodo { continue }
            // 通知模式：響鈴交給 .timeSensitive 通知本身（前景由 willPresent 出 banner+sound 並自動停），
            // 不在前景另外彈 in-app AlarmRingView，避免「通知音 + 鈴聲」雙重音效。點通知才開喚醒畫面。
            if a.effectiveBackgroundMode == .notification { continue }
            let firesToday = a.weekdays.isEmpty || a.weekdays.contains(wd)
            guard firesToday else { continue }
            let key = "\(a.id.uuidString)-\(day)-\(h)-\(m)"
            guard key != lastForegroundFiredKey else { continue }   // fire once per minute
            // If the user already ✕-dismissed this (non-strict) alarm on the Lock Screen via
            // DismissAlarmIntent, DO NOT re-pop the in-app ring just because the app was opened
            // during the same minute. Without this, dismissing on the lock screen and then opening
            // SunnyWalker forces a second dismissal in-app. (checkPendingAlarm already honours this;
            // the per-second foreground tick was the leak.)
            if recentlyDismissedPeek(a.id) {
                lastForegroundFiredKey = key   // mark this minute handled so we stop re-checking it
                print("🏠 HomeView.checkForegroundAlarm: \(a.id.uuidString.prefix(8)) was ✕-dismissed — not opening ring")
                continue
            }
            lastForegroundFiredKey = key
            print("🏠 HomeView.checkForegroundAlarm: \(a.id.uuidString.prefix(8)) DUE & app on-screen → in-app AlarmRingView")
            // AlarmKit was already cancelled when we entered the foreground (enterForegroundAlarmMode),
            // so there is no system alarm to stop here — just present the in-app ring. As a belt-and-
            // braces guard against a race (alarm fired the instant we became active), stop it too.
            let alarm = a
            Task { @MainActor in try? await AlarmKitService.shared.stop(id: alarm.id) }
            presentRing(alarm)     // closes any open sheet first, then presents AlarmRingView
            break
        }
    }

    /// Foreground = in-app ring. Cancel every AlarmKit alarm so its system UI can't appear while the
    /// app is on-screen (AlarmKit always presents a banner AND backgrounds the app when it fires —
    /// confirmed via scenePhase logs — which makes the in-app voice-stop impossible). The per-second
    /// `foregroundAlarmTick` presents AlarmRingView when an alarm is due. AlarmKit is re-armed by
    /// `enterBackgroundAlarmMode()` the moment we leave the foreground, so lock-screen / silent-mode
    /// ringing is unaffected. (Trade-off: a force-quit straight from the foreground could leave a brief
    /// window with AlarmKit unarmed; the normal "phone locked overnight" path always re-arms.)
    private func enterForegroundAlarmMode() {
        guard AlarmKitService.shared.isAuthorized else { return }
        let snapshot = alarms
        Task { @MainActor in
            for a in snapshot {
                let stateBefore = AlarmKitService.shared.alarmState(id: a.id)
                print("🏠 enterForegroundAlarmMode: \(a.id.uuidString.prefix(8)) \(a.hour):\(String(format:"%02d",a.minute)) AKState=\(stateBefore) — calling stop()+cancel()")
                // stop() silences a currently-ringing alarm; cancel() removes it from the schedule.
                // cancel() alone does NOT stop the current ring — root cause of "alarm keeps ringing".
                try? await AlarmKitService.shared.stop(id: a.id)
                try? await AlarmKitService.shared.cancel(id: a.id)
                let stateAfter = AlarmKitService.shared.alarmState(id: a.id)
                print("🏠 enterForegroundAlarmMode: \(a.id.uuidString.prefix(8)) AKState after=\(stateAfter)")
            }
            print("🏠 foreground mode: AlarmKit stopped+cancelled — in-app ring active for \(snapshot.count) alarms")
        }
    }

    /// 背景 auto-stop（無人回應）留下的 pending timeout 記錄 → WakeRecord(dismissMethod:"timeout")。
    /// 在 scenePhase → .active（延遲 0.5s）呼叫；checkAndStopOverdue 補停的鬧鐘也會入庫。
    private func drainTimeoutRecords() {
        let pending = AlarmAutoStopService.shared.drainPendingTimeoutRecords()
        guard !pending.isEmpty else { return }
        for p in pending {
            let label = alarms.first(where: { $0.id == p.alarmID })?.label ?? ""
            modelContext.insert(WakeRecord(
                alarmID: p.alarmID,
                alarmLabel: label,
                firedAt: p.firedAt,
                wokeAt: p.stoppedAt,          // timeout 語意：自動停鈴時刻（不是起床時刻）
                dismissMethod: "timeout"      // 無人回應 — 統計用：回應率分母、準時率 miss
            ))
        }
        print("🏠 drainTimeoutRecords: \(pending.count) timeout WakeRecord(s) inserted")
    }

    /// Leaving foreground → re-arm AlarmKit so the lock-screen / silent-mode alarm fires.
    private func enterBackgroundAlarmMode() {
        let enabledCount = alarms.filter { $0.isEnabled }.count
        guard AlarmKitService.shared.isAuthorized else {
            // 🚦 trace：AlarmKit 沒授權 → 背景完全不重排、不啟動 keep-alive。
            //   若「關app關屏鬧鐘響但停不了」且看到這行 → 走的是 UN-fallback，不是 AlarmKit 路徑。
            print("🚦 enterBackgroundAlarmMode SKIPPED — AlarmKit NOT authorized (enabled alarms=\(enabledCount))")
            return
        }
        let snapshot = alarms
        print("🚦 enterBackgroundAlarmMode ENTER — re-arming \(snapshot.count) alarms (enabled=\(enabledCount)) + will eval keep-alive window")
        // ★ 背景轉場保護：syncAllEnabled 走多次 AlarmKit IPC、之後還要啟動 keep-alive 音訊。
        // 沒有 UIApplication background task 的話，app 可能在完成前就被 suspend →
        // AlarmKit 沒排上 / Layer 2 沒啟動。必須在 scenePhase handler 內同步取得。
        AlarmAutoStopService.shared.beginTransitionProtection()
        Task { @MainActor in
            await AlarmKitService.shared.syncAllEnabled(snapshot)
            // After sync, arm()/disarm() calls inside syncAlarm() have updated AlarmAutoStopService.
            // Now start audio keep-alive + DispatchTimers if any armed alarm fires within lookAheadMinutes.
            AlarmAutoStopService.shared.beginBackgroundLifecycle()
            // 🚦 在「正要進背景」這一刻 dump 一次 armed + AlarmKit 狀態當基準。下次開 app 的
            //   🔬 Forensics 對照這份基準，就能判斷 app 是「被 suspend（heartbeat 停在響鈴前）」
            //   還是「被 force-quit（willTerminate 有值）」——這是區分「停不了」根因的關鍵。
            AlarmAutoStopService.shared.logLifecycleForensics(context: "entering-background")
            print("🚦 enterBackgroundAlarmMode DONE — AlarmKit re-armed for lock/silent (keep-alive decision logged above)")
            AlarmAutoStopService.shared.endTransitionProtection()
        }
    }

    /// True if the user just turned this alarm off via the banner ✕ (within a short window).
    /// Consumes the marker so it can never suppress a later, legitimate fire of the same alarm.
    private func wasRecentlyDismissed(_ id: UUID) -> Bool {
        let d = UserDefaults.standard
        guard d.string(forKey: "dismissedAlarmID") == id.uuidString else { return false }
        let elapsed = Date().timeIntervalSince1970 - d.double(forKey: "dismissedAlarmAt")
        d.removeObject(forKey: "dismissedAlarmID")
        d.removeObject(forKey: "dismissedAlarmAt")
        return elapsed < 30   // fresh dismissal → suppress this one route
    }

    /// Non-consuming peek of the ✕-dismiss marker — used by the per-second foreground tick.
    /// (The consuming `wasRecentlyDismissed` would clear it on the first tick and let the next
    /// tick re-open the ring.) 60s window comfortably covers the whole due-minute.
    private func recentlyDismissedPeek(_ id: UUID) -> Bool {
        let d = UserDefaults.standard
        guard d.string(forKey: "dismissedAlarmID") == id.uuidString else { return false }
        return Date().timeIntervalSince1970 - d.double(forKey: "dismissedAlarmAt") < 60
    }

    /// Push the current alarm list to the background-listening manager and start/stop it to match
    /// the setting. Called whenever alarms change or the toggle flips. (Experimental, off by default.)
    private func syncBackgroundListening() {
        // 多人鬧鐘群組閘：被關掉 / 隱藏的群組不納入背景聆聽（keep-alive 麥克風 fallback）。
        let snaps = alarms
            .filter { AppSettings.groupAllowsFiring($0.effectiveGroupIndex) }
            .map {
                AlarmSnapshot(
                    id: $0.id, hour: $0.hour, minute: $0.minute, weekdays: $0.weekdays,
                    isEnabled: $0.isEnabled, recordingName: $0.recordingName, soundFileName: $0.soundFileName,
                    requireAppToStop: $0.effectiveRequireAppToStop
                )
            }
        BackgroundListeningManager.shared.updateAlarms(snaps)
        // The keep-alive mic is ONLY a fallback for when AlarmKit is unauthorized. When AlarmKit
        // owns the alarms (normal state), never run it — the mic must open only during an actual
        // ring (inside AlarmRingView), not sit on all the time (橘點長亮 / App Store reject).
        if settings.backgroundListeningEnabled && !AlarmKitService.shared.isAuthorized {
            if firingAlarm == nil { BackgroundListeningManager.shared.start() }
        } else {
            BackgroundListeningManager.shared.stop()
        }
    }

    // MARK: - Grouped alarm list (multi-person alarms)

    /// iPhone clock + mascot header. When `group` is non-nil a group-name banner is appended so the
    /// current group (e.g. 哥哥) is labelled at the top of each horizontally-swiped page.
    private func iphoneHeader(group: Int?, showBanner: Bool) -> AnyView {
        AnyView(
            VStack(spacing: 0) {
                ClockHeaderView(fontSize: 76, textColor: scene.clockTextColor)
                    .padding(.top, 56)
                    .padding(.bottom, 12)
                MascotView(tappable: true, scene: scene,
                           themeOverride: group.map { settings.groupMascot($0) })
                    .overlay(alignment: .topTrailing) {
                        TodoBadgesView(group: group)
                            .offset(x: 14, y: 6)
                    }
                    .padding(.bottom, 8)
                if showBanner, let g = group {
                    GroupBanner(
                        name: settings.groupDisplayName(g),
                        index: g,
                        total: settings.effectiveGroupCount,
                        active: settings.isGroupActive(g),
                        onTap: { requestToggleGroup(g) }
                    )
                    .padding(.bottom, 10)
                }
            }
            // List row 預設靠左對齊 → 撐滿寬度才會水平置中（時鐘 / 日期 / 小動物 / 群組橫幅）。
            .frame(maxWidth: .infinity)
        )
    }

    /// iPhone alarm list. Single continuous scroll when grouping is off; a horizontal page-per-group
    /// pager (整頁橫向分頁) when the parent has enabled groups with 2+ groups.
    @ViewBuilder
    private func iphoneAlarmList() -> some View {
        if settings.groupEnabled && settings.effectiveGroupCount > 1 {
            TabView(selection: $homeGroupSelection) {
                ForEach(Array(0..<settings.effectiveGroupCount), id: \.self) { g in
                    AlarmListView(
                        alarms: alarms.filter { $0.effectiveGroupIndex == g },
                        header: iphoneHeader(group: g, showBanner: true),
                        dimmed: !settings.isGroupActive(g)
                    )
                    .tag(g)
                }
            }
            // We draw our own banner + dots, so suppress the system page dots (they would sit under
            // the floating FAB row at the bottom).
            .tabViewStyle(.page(indexDisplayMode: .never))
        } else {
            // Grouping off → only group A shows (B–E stay assigned but hidden until re-enabled).
            // Enabled-but-single-group still shows group A's mascot, just without the swipe banner.
            AlarmListView(
                alarms: alarms.filter { $0.effectiveGroupIndex == 0 },
                header: iphoneHeader(group: settings.groupEnabled ? 0 : nil, showBanner: false)
            )
        }
    }

    /// iPad alarm-list column (clock/mascot live in a separate column). Same grouping behaviour:
    /// a horizontal pager with a group banner on top when grouping is enabled.
    @ViewBuilder
    private func alarmColumn() -> some View {
        if settings.groupEnabled && settings.effectiveGroupCount > 1 {
            TabView(selection: $homeGroupSelection) {
                ForEach(Array(0..<settings.effectiveGroupCount), id: \.self) { g in
                    AlarmListView(
                        alarms: alarms.filter { $0.effectiveGroupIndex == g },
                        header: AnyView(
                            GroupBanner(
                                name: settings.groupDisplayName(g),
                                index: g,
                                total: settings.effectiveGroupCount,
                                active: settings.isGroupActive(g),
                                onTap: { requestToggleGroup(g) }
                            )
                            .padding(.top, 24)
                            .padding(.bottom, 6)
                            .frame(maxWidth: .infinity)
                        ),
                        dimmed: !settings.isGroupActive(g)
                    )
                    .tag(g)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        } else {
            AlarmListView(alarms: alarms.filter { $0.effectiveGroupIndex == 0 })
        }
    }

    // MARK: - AlarmKit PoC DEBUG overlay (stripped from Release builds)

    // MARK: - Background

    private var background: some View {
        ZStack {
            LinearGradient(
                stops: zip([0.0, 0.55, 1.0], scene.gradientColors).map {
                    Gradient.Stop(color: $0.1, location: $0.0)
                },
                startPoint: .top,
                endPoint: .bottom
            )
            scene.colorGrade
                .opacity(scene.colorGradeOpacity)
                .blendMode(.softLight)
        }
        .animation(.easeInOut(duration: 1.5), value: scene)
        .ignoresSafeArea()
    }

    // MARK: - FAB buttons (add alarm + IO)

    private var addButton: some View {
        // 預設只露三顆 icon（語言 / 設定 / 新增鬧鐘），畫面保持乾淨；長按任一顆才浮出它的提示字
        // 膠囊（FabHint），1.6s 後自動消失。.bottom 對齊讓 48/48/60 不同大小的圓鈕底線切齊。
        HStack(alignment: .bottom, spacing: 20) {
            // Language switcher — no parental gate, kids can use it too
            Menu {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        localization.language = lang
                    } label: {
                        Text(lang.displayKey)
                    }
                }
            } label: {
                Image(systemName: "globe")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(SunnyColors.sunnyGray.opacity(0.55))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            }
            .accessibilityLabel(Text("language_setting"))
            .modifier(FabHint(key: "language_setting", id: "lang", hinted: $hintedFab, reveal: revealHint))

            // Settings — gated: parental gate fires first, then SettingsView opens
            Button {
                openSettingsFlow()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(SunnyColors.forestDeep)
                    .clipShape(Circle())
                    .shadow(color: SunnyColors.forestDeep.opacity(0.45), radius: 8, y: 4)
            }
            .accessibilityLabel(Text("settings_label"))
            .modifier(FabHint(key: "settings_label", id: "settings", hinted: $hintedFab, reveal: revealHint))

            // Add alarm button — gated behind parental gate
            Button {
                openAddAlarmFlow()
            } label: {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(SunnyColors.lanternOrange)
                    .clipShape(Circle())
                    .shadow(color: SunnyColors.lanternOrange.opacity(0.45), radius: 10, y: 5)
            }
            .accessibilityLabel(Text("新增鬧鐘"))
            .modifier(FabHint(key: "新增鬧鐘", id: "add", hinted: $hintedFab, reveal: revealHint))
        }
        // maxWidth: .infinity 讓三顆 icon 在底部置中；bottom safe area 由系統保留 → 不壓到 home indicator。
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.bottom, 16)
        // Parental gate for "+" → AlarmEditorView
        .sheet(isPresented: $showingParentalGate, onDismiss: {
            if gateDidSucceed {
                gateDidSucceed = false
                showingAddAlarm = true
            }
        }) {
            ParentalGateView(onSuccess: {
                // Passing the gate opens the temporary-unlock window (default 5 min) so the parent
                // isn't re-challenged for every Settings / New Alarm within that window. They can end
                // it early with "立即上鎖" in Settings.
                settings.beginParentalUnlockWindow()
                gateDidSucceed = true
            })
        }
        .sheet(isPresented: $showingAddAlarm) {
            AlarmEditorView()
        }
        // Settings parental gate → SettingsView
        .sheet(isPresented: $showingParentalForSettings, onDismiss: {
            if gateSettingsOK { gateSettingsOK = false; showingSettings = true }
        }) {
            ParentalGateView(onSuccess: {
                // Same as the New Alarm gate: passing it starts the temporary-unlock window.
                settings.beginParentalUnlockWindow()
                gateSettingsOK = true
            })
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        // Group on/off parental gate → toggle the pending group on success.
        .sheet(isPresented: $showingParentalForGroup, onDismiss: {
            if groupGateOK {
                groupGateOK = false
                if let g = pendingGroupToggle { toggleGroup(g) }
            }
            pendingGroupToggle = nil
        }) {
            ParentalGateView(onSuccess: {
                settings.beginParentalUnlockWindow()
                groupGateOK = true
            })
        }
        // Alarm cap reached → tell the parent to delete one first.
        .alert("鬧鐘數量已達上限", isPresented: $showingMaxAlarmsAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text("最多只能設定 \(maxAlarms) 個鬧鐘，請先刪除一個再新增。")
        }
    }

    /// Show the long-pressed FAB's hint capsule, then auto-hide it after a short delay.
    private func revealHint(_ id: String) {
        withAnimation(.easeInOut(duration: 0.15)) { hintedFab = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if hintedFab == id { hintedFab = nil }
            }
        }
    }

    private func openAddAlarmFlow() {
        // Enforce the alarm cap before anything else (even before the parental gate).
        guard alarms.count < maxAlarms else {
            showingMaxAlarmsAlert = true
            return
        }
        settings.clearExpiredParentalUnlockIfNeeded()
        if settings.isParentalGateUnlocked() {
            showingAddAlarm = true
        } else {
            showingParentalGate = true
        }
    }

    private func openSettingsFlow() {
        settings.clearExpiredParentalUnlockIfNeeded()
        if settings.isParentalGateUnlocked() {
            showingSettings = true
        } else {
            showingParentalForSettings = true
        }
    }

    /// 點首頁群組橫幅 → 切換該組開關。先檢查家長權限：已解鎖直接切，否則先過家長閘。
    private func requestToggleGroup(_ g: Int) {
        settings.clearExpiredParentalUnlockIfNeeded()
        if settings.isParentalGateUnlocked() {
            toggleGroup(g)
        } else {
            pendingGroupToggle = g
            showingParentalForGroup = true
        }
    }

    /// 真正切換第 g 組的開關：只翻轉群組旗標（不動每顆鬧鐘的 isEnabled，保留個別開關狀態），
    /// 再對該組鬧鐘重排一次 UN/通知。實際「響不響」交給 AppSettings.groupAllowsFiring 這道群組閘——
    /// off → schedule()/syncAlarm() 會清掉排程；on → 依各鬧鐘自己的 isEnabled 重新排。
    /// AlarmKit 則由前景/背景生命週期（enterBackground/ForegroundAlarmMode）依 model + 群組閘重排。
    private func toggleGroup(_ g: Int) {
        settings.setGroupActive(g, !settings.isGroupActive(g))
        let affected = alarms.filter { $0.effectiveGroupIndex == g }
        Task {
            for a in affected { try? await AlarmScheduler.shared.syncWithModel(alarm: a) }
        }
    }
}


// MARK: - FabHint (long-press tooltip for a FAB icon)

/// Long-press a FAB icon → briefly show its hint capsule above it (auto-hides via `reveal`).
/// Keeps the home screen uncluttered while still surfacing each icon's meaning on demand.
/// Uses `.simultaneousGesture` so the icon's own tap (Button action / Menu open) still works.
private struct FabHint: ViewModifier {
    let key: LocalizedStringKey
    let id: String
    @Binding var hinted: String?
    let reveal: (String) -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if hinted == id {
                    Text(key)
                        .font(SunnyFonts.caption(13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.75))
                        .clipShape(Capsule())
                        .fixedSize()
                        .offset(y: -42)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                        .allowsHitTesting(false)
                }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35).onEnded { _ in reveal(id) }
            )
    }
}

// MARK: - GroupBanner (multi-person alarm — current group label + swipe hint)

/// Shows the current group's name (e.g. 哥哥) as a soft, hand-drawn label with left/right swipe
/// chevrons and a row of page dots. Styled to melt into the watercolor sky (frosted cream capsule,
/// thin jade outline) rather than sit on top of it as a heavy block. Name is verbatim (may be a
/// custom name the parent typed).
private struct GroupBanner: View {
    let name: String
    let index: Int
    let total: Int
    /// 群組開關狀態：true＝開（綠、彩色），false＝關（灰、休眠樣式）。
    var active: Bool = true
    /// 點名稱膠囊 → 切換這個群組的開關（呼叫端會先過家長驗證）。nil＝不可點（例如沒有開關需求時）。
    var onTap: (() -> Void)? = nil

    private var capsuleFill: Color {
        active ? SunnyColors.cloudWhite.opacity(0.78) : SunnyColors.sunnyGray.opacity(0.2)
    }

    var body: some View {
        // 單行：左箭頭 · 名稱膠囊（可點＝開關）· 右箭頭 · 頁點。
        HStack(spacing: 10) {
            Image(systemName: "chevron.left")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(SunnyColors.forestDeep.opacity(index > 0 ? 0.45 : 0.1))

            Button {
                onTap?()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: active ? "person.crop.circle.fill" : "powersleep")
                        .font(.system(size: 14))
                        .foregroundStyle(active ? SunnyColors.leafFresh : SunnyColors.sunnyGray)
                    Text(verbatim: name)
                        .font(SunnyFonts.caption(15))
                        .foregroundStyle(active ? SunnyColors.forestDeep : SunnyColors.sunnyGray)
                        .lineLimit(1)
                    if !active {
                        Text("group_off_badge")
                            .font(SunnyFonts.caption(12))
                            .foregroundStyle(SunnyColors.sunnyGray)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule(style: .continuous).fill(capsuleFill))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder((active ? SunnyColors.leafFresh : SunnyColors.sunnyGray).opacity(0.4),
                                      lineWidth: 1.5)
                )
                .shadow(color: SunnyColors.forestDeep.opacity(active ? 0.1 : 0), radius: 4, y: 1)
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(SunnyColors.forestDeep.opacity(index < total - 1 ? 0.45 : 0.1))

            HStack(spacing: 5) {
                ForEach(Array(0..<total), id: \.self) { d in
                    Circle()
                        .fill(d == index ? SunnyColors.leafFresh : SunnyColors.forestDeep.opacity(0.18))
                        .frame(width: d == index ? 7 : 6, height: d == index ? 7 : 6)
                        .animation(.easeInOut(duration: 0.2), value: index)
                }
            }
            .padding(.leading, 2)
        }
        .animation(.easeInOut(duration: 0.2), value: active)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(active ? "group_on_badge" : "group_off_badge"))
        .accessibilityHint(Text("group_toggle_hint"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Clock header (self-contained per-second redraw)

/// Owns its own 1-second timer so only this small view re-renders each tick —
/// the surrounding screen (background, clouds, mascot, alarm list) is untouched.
private struct ClockHeaderView: View {
    let fontSize: CGFloat
    let textColor: Color

    @State private var now = Date()
    @ObservedObject private var settings = AppSettings.shared
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 6) {
            // Use DateFormatter with explicit format strings so the result is locale-independent.
            // Date.FormatStyle.hour(.twoDigits(amPM:omitted)) respects the device locale's
            // hour cycle — on zh_TW (12h cycle) 15:50 becomes "03:50" instead of "15:50".
            Text(verbatim: formattedTime(now))
                .font(SunnyFonts.clock(fontSize))
                .foregroundStyle(textColor)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: now)

            Text(now, format: .dateTime.weekday(.wide).month().day())
                .font(SunnyFonts.subtitle())
                .foregroundStyle(textColor.opacity(0.7))
        }
        .onReceive(tick) { now = $0 }
    }

    private func formattedTime(_ date: Date) -> String {
        // en_US_POSIX locale forces unambiguous HH:mm / h:mm a output regardless of device locale.
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = settings.use24HourClock ? "HH:mm" : "h:mm a"
        return fmt.string(from: date)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: Alarm.self, inMemory: true)
}

// MARK: - SettingsView
// Defined here (not a separate file) so no new Xcode target membership is needed.

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var bedSide = BedSideManager.shared
    @ObservedObject private var store = StoreService.shared

    // Direct sheet targets (no sub-gates — Settings itself is gated at the button)
    @State private var showingVoiceLib  = false
    @State private var showingHistory   = false
    @State private var showingIO        = false
    @State private var showingPro       = false
    @State private var showingFlowerEditor = false
    @State private var showingTodoHistory = false
    @State private var unlockNow = Date()
    /// 長按某組的「報時」鈴鐺時，在那一列下方顯示使用提示（再長按別組會切換、放開不自動收）。
    @State private var chimeHintGroup: Int? = nil
    /// 長按某組的「待辦」圖示時，在那一列下方顯示使用提示。
    @State private var todoHintGroup: Int? = nil
    private let unlockTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                // 錄音管理 — first row。功能「複製」到新增鬧鐘頁，設定頁同樣保留這個入口
                // （同一個 VoiceLibraryView，不是搬移）。
                Section {
                    Button { showingVoiceLib = true } label: {
                        HStack {
                            Label("錄音管理", systemImage: "mic.circle.fill")
                                .foregroundStyle(SunnyColors.skyBlue)
                                .font(SunnyFonts.caption())
                            Spacer()
                            NavigationChevron()
                        }
                    }
                }

                // Clock format
                Section(header: Text("time_format_section")) {
                    Toggle(isOn: $settings.use24HourClock) {
                        Label {
                            Text(settings.use24HourClock
                                 ? LocalizedStringKey("24 小時制")
                                 : LocalizedStringKey("12 小時制"))
                        } icon: {
                            Image(systemName: settings.use24HourClock ? "clock.fill" : "clock")
                        }
                    }
                    .tint(SunnyColors.leafFresh)
                }

                // Recording gap
                Section(
                    header: Text("recording_gap_section"),
                    footer: Text("recording_gap_footer")
                ) {
                    Stepper(value: $settings.recordingGapSeconds, in: 0...5) {
                        HStack {
                            Label("recording_gap_label", systemImage: "waveform")
                            Spacer()
                            Text("\(settings.recordingGapSeconds) 秒")
                                .foregroundStyle(SunnyColors.sunnyGray)
                                .monospacedDigit()
                        }
                    }
                }

                // Alarm ring duration
                Section(
                    header: Text("響鈴時長"),
                    footer: Text("鬧鐘響這麼久還沒被關掉，就自動停止並讓螢幕休眠，避免小孩不在時一直耗電。")
                ) {
                    Stepper(value: $settings.alarmRingDurationMinutes, in: 1...10) {
                        HStack {
                            Label("自動停止時間", systemImage: "alarm")
                            Spacer()
                            Text("\(settings.alarmRingDurationMinutes) 分")
                                .foregroundStyle(SunnyColors.sunnyGray)
                                .monospacedDigit()
                        }
                    }
                }

                // 「聲控模式」全域開關已移除：聲控關鬧鐘改由每個鬧鐘自己的「啟用口令關閉」(taskType=.voice)
                // 控制，前景響鈴時才開麥克風（AlarmRingView 內）。backgroundListeningEnabled 屬性保留但
                // dormant（預設 false），避免動到 HomeView/BackgroundListeningManager 的既有參照。

                // Mascot theme
                Section(header: Text("主題")) {
                    Picker(selection: $settings.mascotTheme) {
                        ForEach(MascotTheme.allCases) { theme in
                            // Use LocalizedStringKey so xcstrings translates the display name
                            Label {
                                Text(LocalizedStringKey(theme.displayName))
                            } icon: {
                                Image(systemName: theme.icon)
                            }
                            .tag(theme)
                        }
                    } label: {
                        Label("吉祥物", systemImage: "pawprint.fill")
                            .foregroundStyle(SunnyColors.wheatGold)
                    }
                    .pickerStyle(.navigationLink)

                    // 自訂向日葵：選一張照片當花心（全 app 共用）。可在這裡或群組吉祥物選擇器選「向日葵」。
                    Button { showingFlowerEditor = true } label: {
                        HStack {
                            Label("flower_settings_row", systemImage: "camera.macro")
                                .foregroundStyle(SunnyColors.lanternOrange)
                            Spacer()
                            if let img = settings.flowerImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                                    .overlay(Circle().strokeBorder(SunnyColors.wheatGold, lineWidth: 1.5))
                            }
                            NavigationChevron()
                        }
                    }
                }

                // 多人鬧鐘分組 — 啟用後首頁的鬧鐘清單可左右滑動切換不同群組（如哥哥、妹妹）。
                Section(
                    header: Text("group_section"),
                    footer: Text(settings.groupEnabled
                                 ? LocalizedStringKey("group_rename_footer")
                                 : LocalizedStringKey("group_section_footer"))
                ) {
                    Toggle(isOn: $settings.groupEnabled) {
                        Label("group_enable_label", systemImage: "person.2.fill")
                            .foregroundStyle(SunnyColors.forestDeep)
                    }
                    .tint(SunnyColors.leafFresh)

                    if settings.groupEnabled {
                        // 群組數量（1…5）
                        HStack {
                            Label("group_count_label", systemImage: "number.circle.fill")
                                .foregroundStyle(SunnyColors.skyBlue)
                            Spacer()
                            Text("\(settings.groupCount)")
                                .foregroundStyle(SunnyColors.sunnyGray)
                                .monospacedDigit()
                            Stepper("", value: $settings.groupCount, in: 1...AppSettings.maxGroups)
                                .labelsHidden()
                        }

                        // 每組一列：字母徽章 + 命名欄（空白＝沿用「群組 A / Group A」）+ 吉祥物下拉選單
                        // ＋最右側「報時」鈴鐺開關（長按顯示提示）。用 Array 包 range 避免動態 range 的
                        // ForEach 警告（groupCount 會變）。
                        ForEach(Array(0..<settings.groupCount), id: \.self) { i in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    ZStack {
                                        Circle()
                                            .fill(SunnyColors.leafFresh.opacity(0.16))
                                            .frame(width: 30, height: 30)
                                        Text(verbatim: String(Character(UnicodeScalar(UInt8(65 + i)))))
                                            .font(SunnyFonts.caption(15))
                                            .foregroundStyle(SunnyColors.forestDeep)
                                    }

                                    TextField(
                                        "",
                                        text: settings.groupNameBinding(i),
                                        prompt: Text(verbatim: settings.groupDisplayName(i))
                                    )
                                    .font(SunnyFonts.caption())
                                    .foregroundStyle(SunnyColors.nightIndigo)
                                    .tint(SunnyColors.leafFresh)
                                    .submitLabel(.done)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    // 吉祥物下拉選單：點開選一隻；按鈕顯示目前選的吉祥物 + 上下箭頭。
                                    Menu {
                                        Picker("group_mascot_label", selection: Binding(
                                            get: { settings.groupMascot(i) },
                                            set: { settings.setGroupMascot(i, $0) }
                                        )) {
                                            ForEach(MascotTheme.allCases) { theme in
                                                Label {
                                                    Text(LocalizedStringKey(theme.displayName))
                                                } icon: {
                                                    Image(systemName: theme.icon)
                                                }
                                                .tag(theme)
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 5) {
                                            MascotThumb(theme: settings.groupMascot(i), size: 26)
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(SunnyColors.sunnyGray)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule().fill(SunnyColors.sunnyGray.opacity(0.12))
                                        )
                                    }

                                    // 報時開關（鈴鐺）。on＝這組變成報時鬧鐘；長按顯示使用提示。報時 / 待辦互斥。
                                    Button {
                                        settings.setGroupChimeEnabled(i, !settings.isGroupChimeEnabled(i))
                                    } label: {
                                        Image(systemName: settings.isGroupChimeEnabled(i)
                                              ? "bell.badge.fill" : "bell.slash")
                                            .font(.system(size: 20))
                                            .foregroundStyle(settings.isGroupChimeEnabled(i)
                                                             ? SunnyColors.lanternOrange
                                                             : SunnyColors.sunnyGray.opacity(0.6))
                                            .frame(width: 32, height: 32)
                                    }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(
                                        LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                                            withAnimation(.spring(duration: 0.2)) {
                                                chimeHintGroup = (chimeHintGroup == i) ? nil : i
                                                todoHintGroup = nil
                                            }
                                        }
                                    )

                                    // 待辦開關（氣球）。on＝這組變成待辦語音提醒；長按顯示使用提示。
                                    Button {
                                        settings.setGroupTodoEnabled(i, !settings.isGroupTodoEnabled(i))
                                    } label: {
                                        Image(systemName: settings.isGroupTodoEnabled(i)
                                              ? "balloon.fill" : "balloon")
                                            .font(.system(size: 20))
                                            .foregroundStyle(settings.isGroupTodoEnabled(i)
                                                             ? SunnyColors.leafFresh
                                                             : SunnyColors.sunnyGray.opacity(0.6))
                                            .frame(width: 32, height: 32)
                                    }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(
                                        LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                                            withAnimation(.spring(duration: 0.2)) {
                                                todoHintGroup = (todoHintGroup == i) ? nil : i
                                                chimeHintGroup = nil
                                            }
                                        }
                                    )
                                }

                                if chimeHintGroup == i {
                                    Text("chime_toggle_hint")
                                        .font(.system(size: 12))
                                        .foregroundStyle(SunnyColors.lanternOrange.opacity(0.9))
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                                if todoHintGroup == i {
                                    Text("todo_toggle_hint")
                                        .font(.system(size: 12))
                                        .foregroundStyle(SunnyColors.leafFresh.opacity(0.95))
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                    }
                }

                Section(
                    header: Text("temporary_unlock_section"),
                    footer: Text(isTemporarilyUnlocked
                                 ? LocalizedStringKey("temporary_unlock_active_footer")
                                 : LocalizedStringKey("temporary_unlock_footer"))
                ) {
                    HStack {
                        Button {
                            settings.beginParentalUnlockWindow()
                            unlockNow = Date()
                        } label: {
                            Label("temporary_unlock_start", systemImage: "lock.open")
                        }
                        Spacer()
                        Text(L("temporary_unlock_minutes %lld", settings.parentalUnlockDurationMinutes))
                            .foregroundStyle(SunnyColors.sunnyGray)
                            .monospacedDigit()
                        Stepper("", value: $settings.parentalUnlockDurationMinutes, in: 5...60, step: 5)
                            .labelsHidden()
                    }

                    if isTemporarilyUnlocked {
                        // One row: "立即上鎖" (lock now, ends the window early) on the left, remaining
                        // countdown on the right — saves the separate 目前狀態 line.
                        HStack {
                            Button(role: .destructive) {
                                settings.endParentalUnlockWindow()
                                unlockNow = Date()
                            } label: {
                                Label("temporary_unlock_lock_now", systemImage: "lock.fill")
                            }
                            .buttonStyle(.borderless)   // keep the tap target on the button, not the whole row
                            Spacer()
                            Text(remainingUnlockText)
                                .foregroundStyle(SunnyColors.forestDeep)
                                .monospacedDigit()
                        }
                    }
                }

                // Parental tools — moved to the very bottom (家長工具放最下面)
                Section(
                    header: Text("parental_section"),
                    footer: Text("bedside_lock_footer")
                ) {
                    // Bed Side Mode — direct toggle
                    Button {
                        if bedSide.isBedSideActive { bedSide.disable() } else { bedSide.enable() }
                    } label: {
                        HStack {
                            Label("bedside_mode_label", systemImage: bedSide.isBedSideActive ? "moon.fill" : "moon")
                                .foregroundStyle(bedSide.isBedSideActive ? SunnyColors.starGold : .primary)
                            Spacer()
                            Text(bedSide.isBedSideActive ? "bedside_on" : "bedside_off")
                                .font(SunnyFonts.caption(13))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(bedSide.isBedSideActive ? SunnyColors.nightDeep : SunnyColors.sunnyGray)
                                .clipShape(Capsule())
                        }
                    }

                    Button { showingHistory = true } label: {
                        Label("起床紀錄", systemImage: "chart.bar.fill")
                            .foregroundStyle(SunnyColors.forestDeep)
                    }
                    Button { showingTodoHistory = true } label: {
                        Label("todo_history_title", systemImage: "balloon.2.fill")
                            .foregroundStyle(SunnyColors.leafFresh)
                    }
                    Button { showingIO = true } label: {
                        Label("匯入 / 匯出", systemImage: "square.and.arrow.up.on.square")
                            .foregroundStyle(SunnyColors.leafFresh)
                    }
                }

                // SunnyWalker Pro — the very last section. Deliberately quiet: no banner, no promo,
                // no limit-hit nag elsewhere. Lives only here, behind the parental gate (Guideline 1.3).
                Section {
                    if store.isPro {
                        // Already unlocked → static, non-tappable row, NO purchase control (Apple checks).
                        Label("pro_settings_unlocked", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(SunnyColors.forestDeep)
                    } else {
                        Button { showingPro = true } label: {
                            HStack {
                                Label("pro_settings_row", systemImage: "sun.max.fill")
                                    .foregroundStyle(SunnyColors.wheatGold)
                                Spacer()
                                // Price only when loaded; never hardcode / show 0 when offline.
                                if let price = store.product?.displayPrice {
                                    Text(verbatim: price)
                                        .font(SunnyFonts.caption(14))
                                        .foregroundStyle(SunnyColors.sunnyGray)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text("settings_label"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .font(SunnyFonts.caption())
                }
            }
        }
        .onAppear {
            settings.clearExpiredParentalUnlockIfNeeded()
            unlockNow = Date()
        }
        .onReceive(unlockTick) { now in
            unlockNow = now
            settings.clearExpiredParentalUnlockIfNeeded(referenceDate: now)
        }
        .sheet(isPresented: $showingVoiceLib)  { VoiceLibraryView() }
        .sheet(isPresented: $showingHistory)   { WakeHistoryView() }
        .sheet(isPresented: $showingIO)        { AlarmIOView() }
        .sheet(isPresented: $showingPro)       { ProUpgradeView() }
        .sheet(isPresented: $showingFlowerEditor) { FlowerCenterEditorView() }
        .sheet(isPresented: $showingTodoHistory) { TodoHistoryView() }
    }

    private var isTemporarilyUnlocked: Bool {
        settings.remainingParentalUnlockSeconds(referenceDate: unlockNow) > 0
    }

    private var remainingUnlockText: String {
        let seconds = settings.remainingParentalUnlockSeconds(referenceDate: unlockNow)
        return L("temporary_unlock_remaining %lld %lld", seconds / 60, seconds % 60)
    }
}

#Preview("Settings") {
    SettingsView()
}
