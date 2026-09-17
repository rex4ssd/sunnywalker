// SunnyWalker — SettingsView.swift  |  家長設定頁（在家長閘之後）
//
// 2026-09-03 整理（原本塞在 HomeView.swift 尾巴 500 行，搬出來成獨立檔）：
//   • 順序：錄音管理 → 時間格式 → 首頁清單 → 主題 → 群組 → 進階設定（收起）→ 家長工具 → 開源授權
//     → 家族共用尾段（家長閘 → 評分 → Pro → 更多 rexcode → 版本）。
//   • 「進階設定」把大多數家長一輩子不會動的旋鈕收起來：循環播放間隔、切段響鈴（持續／間隔）、
//     響鈴時長、錄音自動命名加長。用不到的功能不佔版面，要調的人點一下就有。
//   • 尾段改用共用件 KidsParentFooter 的家長閘段（延長解鎖／立即上鎖）——跟 LetAbacus 等
//     14 個 app 長一樣；「請喝咖啡」的位置放 SunnyWalker Pro 購買列（本 app 走買斷，不打賞）。
//     解鎖狀態由 HomeView 把共用 session 鏡射回 AppSettings，首頁的「＋」／設定鈕跟著免驗證。

import AppVersionKit
import KidsParentalUI  // ParentalUnlockSession + KidsReviewPrompt + KidsTheme
import KidsSettingsFooter
import StoreKit        // @Environment(\.requestReview)
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var bedSide = BedSideManager.shared
    @ObservedObject private var store = StoreService.shared

    // Shared-library unlock session（家長閘段 + FamilyShelfView 的內閘）。
    @Environment(ParentalUnlockSession.self) private var parentalSession

    // Review prompt (shared KidsReviewPrompt). Made for Kids 鐵則: only ever triggered HERE,
    // on the parent page behind the parental gate — never in the child/general flow.
    @Environment(\.requestReview) private var requestReview
    @Query private var wakeRecords: [WakeRecord]
    /// "The app has genuinely worked for a while" signal: successful wake-ups the child dismissed
    /// (voice / button / fallback). "timeout" rows are unanswered auto-stops — excluded.
    private var successfulWakeCount: Int {
        wakeRecords.filter { $0.dismissMethod != "timeout" }.count
    }

    // Direct sheet targets (no sub-gates — Settings itself is gated at the button)
    @State private var showingVoiceLib  = false
    @State private var showingHistory   = false
    @State private var showingIO        = false
    @State private var showingPro       = false
    @State private var showingFlowerEditor = false
    @State private var showingTodoHistory = false
    /// 「進階設定」展開狀態（每次進頁預設收起）。
    @State private var showAdvanced = false
    /// 群組段最下面的說明區目前在哪一頁（命名／報時／待辦）。點群組列的圖示會自動切到對應那頁。
    @State private var groupFooterTab: GroupFooterTab = .naming
    /// 最後一次點的是哪一組的哪顆圖示、點完是開還是關——顯示在說明區第一行。
    @State private var groupNote: GroupNote? = nil

    private var theme: KidsTheme {
        KidsTheme(accent: SunnyColors.lanternOrange, background: SunnyColors.cloudWhite, scheme: .light)
    }

    var body: some View {
        NavigationStack {
            List {
                voiceLibrarySection
                timeFormatSection
                homeListSection
                themeSection
                groupSection
                advancedSection
                parentalToolsSection
                licensesSection

                // 家族共用尾段：家長閘（延長解鎖／立即上鎖）→ 評分 → Pro → 更多 rexcode → 版本。
                // 打賞傳 nil：SunnyWalker 走 Pro 買斷，購買列放在打賞的位置（proRow）。
                // 整頁在家長閘後；貨架另有一道閘擋 App Store 連結（解鎖窗內免問）。
                KidsParentFooter(
                    tipProductIDPrefix: nil,
                    freeBlurb: L("pro_footer_blurb"),
                    currentApp: .sunnywalker,
                    theme: theme,
                    gateSession: parentalSession,
                    showsUnlockControls: true,
                    showsGateModeSwitch: true,     // 驗證方式：數學題 ↔ 4 位數密碼（預設 1234）
                    proRow: KidsProRow(
                        title: L("pro_settings_row"),
                        isUnlocked: store.isPro,
                        priceText: store.product?.displayPrice,
                        unlockedText: L("pro_settings_unlocked"),
                        footer: L("pro_row_footer"),
                        onTap: { showingPro = true }
                    )
                )
            }
            .parentInfoAccent(SunnyColors.lanternOrange)
            .navigationTitle(Text("settings_label"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .font(SunnyFonts.caption())
                }
            }
        }
        .countsAsPresentedSheet()
        .onAppear {
            settings.clearExpiredParentalUnlockIfNeeded()
            // 評分請求（共用 KidsReviewPrompt）：家長頁 onAppear、孩子已有 ≥3 次成功起床紀錄
            // 才記正向時刻。per-version 只真正請求一次，Apple 再自行限流（365 天最多 3 次）。
            // Made for Kids 鐵則：只能在 parental gate 之後的家長頁觸發，絕不進兒童流程。
            if successfulWakeCount >= 3 {
                KidsReviewPrompt.recordPositiveMoment(kind: "parentPageAfterWakes", threshold: 1) {
                    requestReview()
                }
            }
        }
        .sheet(isPresented: $showingVoiceLib)  { VoiceLibraryView() }
        .sheet(isPresented: $showingHistory)   { WakeHistoryView() }
        .sheet(isPresented: $showingIO)        { AlarmIOView() }
        .sheet(isPresented: $showingPro)       { ProUpgradeView() }
        .sheet(isPresented: $showingFlowerEditor) { FlowerCenterEditorView() }
        .sheet(isPresented: $showingTodoHistory) { TodoHistoryView() }
    }

    // MARK: - Sections

    /// 錄音管理 — first row。功能「複製」到新增鬧鐘頁，設定頁同樣保留這個入口
    /// （同一個 VoiceLibraryView，不是搬移）。
    private var voiceLibrarySection: some View {
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
    }

    private var timeFormatSection: some View {
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
    }

    /// 首頁清單排列：依時間（單一清單）／重複週期合併／依時段（早上・上午・下午・晚上）／依星期（可收合）。
    /// 首頁點吉祥物也會輪流切換這個值，這裡是家長直接選的入口。
    private var homeListSection: some View {
        Section(
            header: Text("首頁清單"),
            footer: Text(homeLayoutFooter)
        ) {
            Picker(selection: $settings.homeListLayout) {
                ForEach(HomeListLayout.allCases) { layout in
                    Label {
                        Text(LocalizedStringKey(layout.labelKey))
                    } icon: {
                        Image(systemName: layout.systemImage)
                    }
                    .tag(layout)
                }
            } label: {
                Label("home_layout_label", systemImage: "rectangle.grid.1x2")
            }
            .pickerStyle(.menu)
        }
    }

    private var homeLayoutFooter: LocalizedStringKey {
        switch settings.homeListLayout {
        case .time:    return "home_layout_time_footer"
        case .merged:  return "home_layout_merged_footer"
        case .daypart: return "home_layout_daypart_footer"
        case .weekday: return "home_layout_weekday_footer"
        }
    }

    private var themeSection: some View {
        Section(header: Text("主題")) {
            Picker(selection: $settings.mascotTheme) {
                ForEach(MascotTheme.allCases) { theme in
                    // Use LocalizedStringKey so xcstrings translates the display name
                    Label {
                        Text(theme.displayName)
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
    }

    /// 多人鬧鐘分組 — 啟用後首頁的鬧鐘清單可左右滑動切換不同群組（如哥哥、妹妹）。
    private var groupSection: some View {
        Section(
            header: Text("group_section"),
            footer: groupFooter
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
                    groupRow(i)
                }
            }
        }
    }

    private func groupRow(_ i: Int) -> some View {
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
                                Text(theme.displayName)
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
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(SunnyColors.sunnyGray)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(SunnyColors.sunnyGray.opacity(0.12))
                    )
                }

                // 報時開關（鈴鐺）／待辦開關（氣球）。兩者互斥。
                // 點一下＝切換，**同時**把群組段最下面的說明區切到對應那頁（見 groupFooter）。
                // 說明不放在這一列下面：點了才冒字會把下面整排往下推，畫面跳動。長按＝只看說明、不切換。
                groupModeButton(i, mode: .chime)
                groupModeButton(i, mode: .todo)
            }

        }
    }

    /// 群組列右側的功能鈕（報時／待辦）。
    private func groupModeButton(_ i: Int, mode: GroupMode) -> some View {
        let isOn = mode.isOn(settings, i)
        return Button {
            mode.set(settings, i, !isOn)
            showGroupNote(i, mode)
        } label: {
            Image(systemName: isOn ? mode.onImage : mode.offImage)
                .font(.title3)
                .foregroundStyle(isOn ? mode.tint : SunnyColors.sunnyGray.opacity(0.6))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in showGroupNote(i, mode) }
        )
        .accessibilityLabel(Text(LocalizedStringKey(mode.titleKey)))
        .accessibilityValue(Text(isOn ? "group_on_badge" : "group_off_badge"))
        .accessibilityHint(Text(LocalizedStringKey(mode.descKey)))
    }

    /// 把最下面的說明區切到這顆圖示的那一頁，並記下「哪一組、現在是開還是關」。
    /// 狀態取「現在」的值，所以點完切換後顯示的是新狀態。開待辦會連動關掉報時（互斥）。
    private func showGroupNote(_ i: Int, _ mode: GroupMode) {
        groupNote = GroupNote(group: i, mode: mode, isOn: mode.isOn(settings, i))
        withAnimation(.easeInOut(duration: 0.15)) { groupFooterTab = mode.footerTab }
    }

    /// 群組段最下面的說明區：命名／報時／待辦三頁，**高度固定**（三頁疊在同一個 ZStack，
    /// 只顯示選中的那頁）——點圖示或切頁都不會讓畫面上下跳。分組沒開時只有一句總說明。
    @ViewBuilder
    private var groupFooter: some View {
        if !settings.groupEnabled {
            Text("group_section_footer")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(GroupFooterTab.allCases) { tab in
                        let selected = groupFooterTab == tab
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { groupFooterTab = tab }
                        } label: {
                            Label {
                                Text(LocalizedStringKey(tab.titleKey))
                            } icon: {
                                Image(systemName: tab.systemImage)
                            }
                            // 字重固定：選中才加粗會讓膠囊高度差 1pt，整段跟著抖一下。
                            .font(.caption.weight(.medium))
                            .foregroundStyle(selected ? Color.white : SunnyColors.sunnyGray)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(selected ? tab.tint : SunnyColors.sunnyGray.opacity(0.12)))
                        }
                        // .plain：在 List 的 footer 裡不加會整列一起吃點擊。
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                }

                ZStack(alignment: .topLeading) {
                    ForEach(GroupFooterTab.allCases) { tab in
                        groupFooterPage(tab)
                            .opacity(groupFooterTab == tab ? 1 : 0)
                            .accessibilityHidden(groupFooterTab != tab)
                    }
                }
            }
            .textCase(nil)
        }
    }

    /// 一頁說明。報時／待辦頁第一行是「剛剛點了哪一組、現在開或關」——沒點過就留一行空白佔位，
    /// 這樣點了之後高度也不變。
    @ViewBuilder
    private func groupFooterPage(_ tab: GroupFooterTab) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            switch tab {
            case .naming:
                Text("group_rename_footer")
                // 這頁字最少——補一句「右邊兩顆圖示是什麼」，順便把固定高度留下的空白用掉。
                Text("group_naming_tip")
                    .padding(.top, 4)
            case .chime, .todo:
                let mode: GroupMode = tab == .chime ? .chime : .todo
                if let note = groupNote, note.mode == mode {
                    (Text(verbatim: settings.groupDisplayName(note.group) + "  ")
                     + Text(note.isOn ? "group_mode_now_on" : "group_mode_now_off"))
                        .fontWeight(.semibold)
                        .foregroundStyle(note.isOn ? mode.noteColor : SunnyColors.sunnyGray)
                } else {
                    Text(verbatim: " ")
                }
                Text(LocalizedStringKey(mode.descKey))
                Text("group_mode_existing_note")
                    .font(.caption2)
                    .foregroundStyle(SunnyColors.sunnyGray.opacity(0.8))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 進階設定（預設收起）：循環播放間隔、切段響鈴、響鈴時長、錄音自動命名加長。
    /// 這些旋鈕都有合理預設，絕大多數家長不需要動；收起來讓設定頁只剩「會用到的」。
    private var advancedSection: some View {
        Section(footer: Text("settings_advanced_footer")) {
            DisclosureGroup(isExpanded: $showAdvanced.animation(.easeInOut(duration: 0.2))) {
                // 循環播放間隔
                VStack(alignment: .leading, spacing: 4) {
                    Stepper(value: $settings.recordingGapSeconds, in: 0...5) {
                        HStack {
                            Label("recording_gap_label", systemImage: "waveform")
                            Spacer()
                            // String(...) → "%@ 秒"（catalog 已有 en）；Int 插值會變沒翻譯的 "%lld 秒"。
                            Text("\(String(settings.recordingGapSeconds)) 秒")
                                .foregroundStyle(SunnyColors.sunnyGray)
                                .monospacedDigit()
                        }
                    }
                    Text("recording_gap_footer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // 切段響鈴——只影響「溫和提醒＋切段」的鬧鐘：響多久（總長）＋每段之間隔多久。
                VStack(alignment: .leading, spacing: 4) {
                    Picker(selection: $settings.burstSpanSeconds) {
                        // 秒數用 String(...) 插值 → 查表 "%@ 秒"；插 Int 會變沒翻譯的 "%lld 秒"。
                        ForEach(AppSettings.burstSpanOptions, id: \.self) { secs in
                            Text("\(String(secs)) 秒").tag(secs)
                        }
                    } label: {
                        Label("切段響鈴", systemImage: "clock.badge.checkmark")
                    }
                    .pickerStyle(.menu)

                    Picker(selection: $settings.burstGapSeconds) {
                        Text("\(String(1)) 秒").tag(1)
                        Text("\(String(2)) 秒").tag(2)
                    } label: {
                        Label("切段間隔", systemImage: "waveform.badge.plus")
                    }
                    .pickerStyle(.menu)
                    Text("只影響開啟「切段」的溫和提醒鬧鐘；所有切段鬧鐘共用。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // 響鈴時長
                VStack(alignment: .leading, spacing: 4) {
                    Stepper(value: $settings.alarmRingDurationMinutes, in: 1...10) {
                        HStack {
                            Label("自動停止時間", systemImage: "alarm")
                            Spacer()
                            Text("\(settings.alarmRingDurationMinutes) 分")
                                .foregroundStyle(SunnyColors.sunnyGray)
                                .monospacedDigit()
                        }
                    }
                    Text("鬧鐘響這麼久還沒被關掉，就自動停止並讓螢幕休眠，避免小孩不在時一直耗電。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // 錄音自動命名長度（語音辨識/匯入檔名的截斷上限）。
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $settings.longAutoNames) {
                        Label("錄音自動命名加長", systemImage: "character.cursor.ibeam")
                    }
                    .tint(SunnyColors.leafFresh)
                    Text("開啟後自動命名最長中文 16 字、英文 32 字母；關閉為 8／16。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Label("settings_advanced_section", systemImage: "slider.horizontal.3")
                    .foregroundStyle(SunnyColors.forestDeep)
            }
            .tint(SunnyColors.lanternOrange)
        }
    }

    /// 家長工具：床邊模式、起床紀錄、待辦紀錄、匯入／匯出。
    private var parentalToolsSection: some View {
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
    }

    /// 開源授權 — fulfils the MIT notice obligation for bundled third-party code (ConfettiSwiftUI).
    private var licensesSection: some View {
        Section {
            NavigationLink {
                AcknowledgementsView()
            } label: {
                Label("third_party_licenses_row", systemImage: "doc.text.fill")
                    .foregroundStyle(SunnyColors.skyBlue)
            }
        }
    }
}

// MARK: - 群組功能鈕（報時／待辦）

/// 群組列右側兩顆功能鈕的共同描述：圖示、顏色、讀寫 AppSettings、說明文字 key。
private enum GroupMode {
    case chime, todo

    var onImage: String  { self == .chime ? "bell.badge.fill" : "balloon.fill" }
    var offImage: String { self == .chime ? "bell.slash" : "balloon" }
    var tint: Color      { self == .chime ? SunnyColors.lanternOrange : SunnyColors.leafFresh }
    var titleKey: String { self == .chime ? "chime_card_title" : "todo_card_title" }
    /// 說明文字的顏色：圖示的嫩綠（leafFresh）在白底上當內文太淡，待辦改用深綠。
    var noteColor: Color { self == .chime ? SunnyColors.lanternOrange : SunnyColors.forestDeep }

    @MainActor func isOn(_ s: AppSettings, _ i: Int) -> Bool {
        self == .chime ? s.isGroupChimeEnabled(i) : s.isGroupTodoEnabled(i)
    }

    @MainActor func set(_ s: AppSettings, _ i: Int, _ on: Bool) {
        if self == .chime { s.setGroupChimeEnabled(i, on) } else { s.setGroupTodoEnabled(i, on) }
    }

    /// Localizable.xcstrings key：這個功能開了會怎樣、關了會怎樣（一段話講完）。
    var descKey: String { self == .chime ? "group_chime_desc" : "group_todo_desc" }

    var footerTab: GroupFooterTab { self == .chime ? .chime : .todo }
}

/// 群組段最下面說明區的三頁。
private enum GroupFooterTab: String, CaseIterable, Identifiable {
    case naming, chime, todo

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .naming: return "group_tab_naming"
        case .chime:  return "chime_card_title"
        case .todo:   return "todo_card_title"
        }
    }

    var systemImage: String {
        switch self {
        case .naming: return "pencil"
        case .chime:  return "bell.badge.fill"
        case .todo:   return "balloon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .naming: return SunnyColors.forestDeep
        case .chime:  return SunnyColors.lanternOrange
        case .todo:   return SunnyColors.forestDeep
        }
    }
}

private struct GroupNote: Equatable {
    let group: Int
    let mode: GroupMode
    let isOn: Bool
}

#Preview("Settings") {
    SettingsView()
        .environment(ParentalUnlockSession())
}
