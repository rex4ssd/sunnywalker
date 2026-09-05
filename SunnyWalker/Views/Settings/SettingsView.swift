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
    /// 長按某組的「報時」鈴鐺時，在那一列下方顯示使用提示（再長按別組會切換、放開不自動收）。
    @State private var chimeHintGroup: Int? = nil
    /// 長按某組的「待辦」圖示時，在那一列下方顯示使用提示。
    @State private var todoHintGroup: Int? = nil

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

    /// 首頁清單排列：依時間（單一清單）／依時段（早上・上午・下午・晚上）／依星期。
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
        case .daypart: return "home_layout_daypart_footer"
        case .weekday: return "開啟後，首頁鬧鐘依星期一到星期日分組；同一顆鬧鐘會出現在它的每個響鈴日底下。"
        }
    }

    private var themeSection: some View {
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
    }

    /// 多人鬧鐘分組 — 啟用後首頁的鬧鐘清單可左右滑動切換不同群組（如哥哥、妹妹）。
    private var groupSection: some View {
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
                            .font(.caption2.weight(.semibold))
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
                        .font(.title3)
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
                        .font(.title3)
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
                    .font(.caption)
                    .foregroundStyle(SunnyColors.lanternOrange.opacity(0.9))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if todoHintGroup == i {
                Text("todo_toggle_hint")
                    .font(.caption)
                    .foregroundStyle(SunnyColors.leafFresh.opacity(0.95))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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

#Preview("Settings") {
    SettingsView()
        .environment(ParentalUnlockSession())
}
