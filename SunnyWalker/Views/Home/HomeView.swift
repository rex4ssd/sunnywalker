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

    // "+" (add alarm) gate states
    @State private var showingParentalGate = false
    @State private var gateDidSucceed = false
    @State private var showingAddAlarm = false

    // Notification-driven / long-press alarm ring
    @State private var firingAlarm: Alarm?

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
    private let foregroundAlarmTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var scene: DaytimeScene {
        DaytimeScene.current(hour: Calendar.current.component(.hour, from: currentTime))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            background
            CloudBackground()
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
                                MascotView()
                                    .scaleEffect(0.75)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            AlarmListView(alarms: alarms)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        // iPad portrait: side-by-side clock/avatar | alarm list
                        HStack(spacing: 0) {
                            VStack(spacing: 0) {
                                ClockHeaderView(fontSize: 76, textColor: scene.clockTextColor)
                                    .padding(.top, 56)
                                    .padding(.bottom, 16)
                                MascotView()
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            AlarmListView(alarms: alarms)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                // iPhone: stacked layout
                VStack(spacing: 0) {
                    ClockHeaderView(fontSize: 76, textColor: scene.clockTextColor)
                        .padding(.top, 56)
                        .padding(.bottom, 12)
                    MascotView()
                        .padding(.bottom, 8)
                    AlarmListView(alarms: alarms)
                }
            }
            addButton
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            checkPendingAlarm()
        }
        // Use .task(id:) instead of onAppear so sync re-fires when @Query finishes loading.
        // onAppear fires before SwiftData populates @Query → alarms is [] on first call.
        // Triggering on alarms.count catches the initial load (0 → N) and any add/delete.
        .task(id: alarms.count) {
            guard !alarms.isEmpty else { return }
            if AlarmKitService.shared.isAuthorized {
                await AlarmKitService.shared.syncAllEnabled(alarms)
            } else {
                // AlarmKit entitlement still pending → the UNNotification path is what actually
                // fires. Re-arm it on every launch so (a) alarms stay scheduled and (b) the custom
                // sound self-heal in AlarmScheduler.schedule applies to pre-existing recordings.
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
                checkPendingAlarm()
                // Smart background-listening: only start mic when app is in foreground.
                // If enabled AND no alarm is ringing, restart the session now.
                if settings.backgroundListeningEnabled && firingAlarm == nil {
                    syncBackgroundListening()
                }
            } else {
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
                    BackgroundListeningManager.shared.stop()   // no-op if it wasn't the one that's active
                    try? sess.setActive(false, options: [.notifyOthersOnDeactivation])
                    print("🏠 HomeView.scenePhase → \(newPhase): released mic + audio session so the UN alarm sound isn't ducked (prevCategory=\(prevCat.rawValue), bgListenActive=\(BackgroundListeningManager.shared.isActive))")
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
            // Restore brightness before showing AlarmRingView (bed-side may have dimmed screen)
            bedSide.disable()
            print("🏠 HomeView.onReceive: routing → AlarmRingView for \(uuid.uuidString.prefix(8))")
            firingAlarm = alarm
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
        guard let id = pendingID else { return }
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
        firingAlarm = alarm
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
        guard scenePhase == .active, firingAlarm == nil, AlarmKitService.shared.isAuthorized else { return }
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute, .weekday, .day], from: Date())
        guard let h = c.hour, let m = c.minute, let wd = c.weekday, let day = c.day else { return }
        for a in alarms where a.isEnabled && a.hour == h && a.minute == m {
            let firesToday = a.weekdays.isEmpty || a.weekdays.contains(wd)
            guard firesToday else { continue }
            let key = "\(a.id.uuidString)-\(day)-\(h)-\(m)"
            guard key != lastForegroundFiredKey else { continue }   // fire once per minute
            lastForegroundFiredKey = key
            print("🏠 HomeView.checkForegroundAlarm: \(a.id.uuidString.prefix(8)) DUE & app on-screen → in-app AlarmRingView + stop AlarmKit (free the mic)")
            // Stop the AlarmKit ring (frees the audio session for the in-app mic), then re-arm so the
            // recurring alarm still fires next time the app is backgrounded.
            let alarm = a
            Task { @MainActor in
                try? await AlarmKitService.shared.stop(id: alarm.id)
                try? await AlarmKitService.shared.syncAlarm(alarm)
            }
            bedSide.disable()      // restore brightness if bed-side dimmed the screen
            firingAlarm = alarm    // presents AlarmRingView (.fullScreenCover)
            break
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

    /// Push the current alarm list to the background-listening manager and start/stop it to match
    /// the setting. Called whenever alarms change or the toggle flips. (Experimental, off by default.)
    private func syncBackgroundListening() {
        let snaps = alarms.map {
            AlarmSnapshot(
                id: $0.id, hour: $0.hour, minute: $0.minute, weekdays: $0.weekdays,
                isEnabled: $0.isEnabled, recordingName: $0.recordingName, soundFileName: $0.soundFileName,
                requireAppToStop: $0.effectiveRequireAppToStop
            )
        }
        BackgroundListeningManager.shared.updateAlarms(snaps)
        if settings.backgroundListeningEnabled {
            if firingAlarm == nil { BackgroundListeningManager.shared.start() }
        } else {
            BackgroundListeningManager.shared.stop()
        }
    }

    // MARK: - AlarmKit PoC DEBUG overlay (stripped from Release builds)

    // MARK: - Background

    private var background: some View {
        LinearGradient(
            colors: scene.gradientColors,
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - FAB buttons (add alarm + IO)

    /// Capsule label shown to the left of each FAB button.
    /// Takes LocalizedStringKey so xcstrings translations apply automatically.
    private func fabLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(SunnyFonts.caption(13))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.30))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.20), radius: 3, y: 2)
    }

    private var addButton: some View {
        VStack(alignment: .trailing, spacing: 16) {
            // Language switcher — no parental gate, kids can use it too
            HStack(spacing: 12) {
                fabLabel("language_setting")
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
            }

            // Settings — gated: parental gate fires first, then SettingsView opens
            HStack(spacing: 12) {
                fabLabel("settings_label")
                Button {
                    showingParentalForSettings = true
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
            }

            // Add alarm button — gated behind parental gate
            HStack(spacing: 12) {
                fabLabel("新增鬧鐘")
                Button {
                    showingParentalGate = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(SunnyColors.lanternOrange)
                        .clipShape(Circle())
                        .shadow(color: SunnyColors.lanternOrange.opacity(0.45), radius: 10, y: 5)
                }
            }
        }
        .padding(24)
        // Parental gate for "+" → AlarmEditorView
        .sheet(isPresented: $showingParentalGate, onDismiss: {
            if gateDidSucceed {
                gateDidSucceed = false
                showingAddAlarm = true
            }
        }) {
            ParentalGateView(onSuccess: { gateDidSucceed = true })
        }
        .sheet(isPresented: $showingAddAlarm) {
            AlarmEditorView()
        }
        // Settings parental gate → SettingsView
        .sheet(isPresented: $showingParentalForSettings, onDismiss: {
            if gateSettingsOK { gateSettingsOK = false; showingSettings = true }
        }) {
            ParentalGateView(onSuccess: { gateSettingsOK = true })
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
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

    // Direct sheet targets (no sub-gates — Settings itself is gated at the button)
    @State private var showingVoiceLib  = false
    @State private var showingHistory   = false
    @State private var showingIO        = false

    var body: some View {
        NavigationStack {
            List {
                // Voice Library — first row
                Section {
                    Button { showingVoiceLib = true } label: {
                        HStack {
                            Label("錄音管理", systemImage: "mic.circle.fill")
                                .foregroundStyle(SunnyColors.skyBlue)
                                .font(SunnyFonts.caption())
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SunnyColors.sunnyGray.opacity(0.4))
                        }
                    }
                }

                // Clock format
                Section(header: Text("time_format_section")) {
                    Toggle(isOn: Binding(
                        get: { !settings.use24HourClock },
                        set: { settings.use24HourClock = !$0 }
                    )) {
                        Label("12h_label", systemImage: "clock")
                    }
                    .tint(SunnyColors.leafFresh)
                    Toggle(isOn: $settings.use24HourClock) {
                        Label("24h_label", systemImage: "clock.fill")
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
                            Text("\(settings.recordingGapSeconds) s")
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

                // Background listening (FOREGROUND-only voice-stop; mic released on background)
                Section(
                    header: Text("聲控關鬧鐘（實驗）"),
                    footer: Text("開啟後，App 在前台時保持麥克風（橘點亮），可說「我起床了」關鬧鐘。切到背景或螢幕關閉會自動停止麥克風，不整夜佔用；此時鬧鐘改由系統通知橫幅發出鈴聲。")
                ) {
                    Toggle(isOn: $settings.backgroundListeningEnabled) {
                        Label("聲控模式", systemImage: settings.backgroundListeningEnabled ? "mic.fill" : "mic.slash")
                            .foregroundStyle(settings.backgroundListeningEnabled ? SunnyColors.lanternOrange : .primary)
                    }
                    .tint(SunnyColors.lanternOrange)
                }

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
                }

                // Parental tools (direct — Settings itself already gated)
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
                    Button { showingIO = true } label: {
                        Label("匯入 / 匯出", systemImage: "square.and.arrow.up.on.square")
                            .foregroundStyle(SunnyColors.leafFresh)
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
        .sheet(isPresented: $showingVoiceLib)  { VoiceLibraryView() }
        .sheet(isPresented: $showingHistory)   { WakeHistoryView() }
        .sheet(isPresented: $showingIO)        { AlarmIOView() }
    }
}

#Preview("Settings") {
    SettingsView()
}
