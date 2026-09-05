// SunnyWalker — AlarmEditorView.swift  |  Day 24  |  edit mode support

import SwiftUI
import SwiftData

struct AlarmEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var localization = LocalizationManager.shared

    /// Pass an existing alarm to enter edit mode; nil = create mode.
    var existingAlarm: Alarm? = nil

    private var isEditing: Bool { existingAlarm != nil }

    // tempAlarm: stable UUID in create mode so RecordingView writes to correct path.
    // In edit mode we work directly on existingAlarm via state copies below.
    @State private var tempAlarm: Alarm

    @State private var selectedTime = Date()
    @State private var label = "起床囉"
    @State private var selectedWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var selectedTaskType: AlarmTaskType = .button
    @State private var isSaving = false
    @State private var showingBuiltinPicker = false
    @State private var showingCustomPicker = false
    @State private var customPhrase = ""
    /// 背景響鈴模式：false = AlarmKit（預設，強力叫醒）；true = Time-Sensitive 通知（溫和、自動停）。
    @State private var useNotificationMode = false
    /// 切段：溫和提醒模式下，是否把語音堆成 ~30s（gentle-repeat burst）。預設 off，只響一次。
    @State private var segmentedBurst = false
    /// 多人鬧鐘群組索引（0 = 群組 A，預設）。只有在 settings.groupEnabled 時才顯示選擇器、存回鬧鐘。
    @State private var selectedGroupIndex = 0
    /// 報時次數（報時鬧鐘專用）：時間到要連報幾次。
    @State private var chimeCount = 1
    /// 區間報時：開＝從鬧鐘時間起每隔 chimeIntervalMinutes 報一次直到 chimeEndTime（迄本身不報）。
    @State private var chimeIntervalOn = false
    @State private var chimeEndTime = Date()
    @State private var chimeIntervalMinutes = 5
    /// 報時人聲（女／男）。
    @State private var chimeVoice: ChimeVoiceGender = .female
    /// 儲存時正在背景合成報時語音（區間報時最多 12 句、每句約 1 秒）→ 顯示進度、擋重複儲存。
    @State private var isComposingChime = false
    /// 「進階選項」（溫和提醒模式、口令關閉）預設收起；任一個不是預設值時進頁就展開。
    @State private var showAdvanced = false
    /// 待辦提醒：主頁顯示的圖示、顯示時長（分鐘，0＝直到點開）。
    @State private var todoIcon: TodoIcon = .balloon
    @State private var todoDuration = 10
    @State private var showingTodoRecorder = false
    @State private var showingTodoPicker = false
    @State private var showingTodoNeedsRecording = false
    /// 待辦顯示時長可選項（分鐘）。0 = 直到兒童點開才消失。
    private let todoDurationOptions = [10, 30, 60, 0]
    @StateObject private var previewPlayer = AudioPlayer()
    @State private var previewingRow: String? = nil
    /// 「用時間當標籤」：打勾＝標籤自動跟著上面的時間（改時間就跟著變）；取消勾選才能自行輸入。
    @State private var labelFollowsTime = false
    // Label tap/long-press
    @State private var showLabelHint = false
    @State private var labelLongPressed = false
    // Days tap/long-press
    @State private var showDaysHint = false
    @State private var daysLongPressed = false

    // MARK: - 未儲存變更防護
    /// 進頁當下的欄位快照。與現值比對＝`hasUnsavedChanges`，用來擋掉「改了時間卻按到取消」。
    private let baseline: EditorSnapshot
    /// 按下取消且確實有改動 → 跳確認框（預設儲存）。
    @State private var showingUnsavedPrompt = false

    /// 編輯器所有「會被儲存」的欄位的值快照（純值型別，方便整組比較）。
    private struct EditorSnapshot: Equatable {
        var hour: Int
        var minute: Int
        var label: String
        var weekdays: Set<Int>
        var taskType: AlarmTaskType
        var customPhrase: String
        var notificationMode: Bool
        var segmentedBurst: Bool
        var groupIndex: Int
        var chimeCount: Int
        var chimeIntervalOn: Bool
        var chimeEndHour: Int
        var chimeEndMinute: Int
        var chimeInterval: Int
        var chimeVoice: ChimeVoiceGender
        var todoIcon: TodoIcon
        var todoDuration: Int
        // 鈴聲相關：選鈴聲/錄音的 sheet 是直接寫進 tempAlarm 的，也要納入比對。
        var recordingName: String
        var recordingDisplayName: String
        var soundFileName: String
    }

    /// 現在畫面上的值（跟 baseline 同構）。
    private var currentSnapshot: EditorSnapshot {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        return EditorSnapshot(
            hour: comps.hour ?? 0,
            minute: comps.minute ?? 0,
            label: label,
            weekdays: selectedWeekdays,
            // 存「實際會寫進鬧鐘的值」而不是 selectedTaskType 本身：口令開關的 setter 會無條件
            // 改 selectedTaskType，但沒有錄音時 saveAlarm 還是寫 .button。比 raw state 會在
            // 「沒錄音卻撥了開關」時誤判成有改動、白跳確認框。
            taskType: isVoiceDismissEnabled ? .voice : .button,
            customPhrase: customPhrase,
            notificationMode: useNotificationMode,
            segmentedBurst: segmentedBurst,
            groupIndex: selectedGroupIndex,
            chimeCount: chimeCount,
            chimeIntervalOn: chimeIntervalOn,
            chimeEndHour: endComps.hour ?? 0,
            chimeEndMinute: endComps.minute ?? 0,
            chimeInterval: chimeIntervalMinutes,
            chimeVoice: chimeVoice,
            todoIcon: todoIcon,
            todoDuration: todoDuration,
            recordingName: tempAlarm.recordingName,
            recordingDisplayName: tempAlarm.recordingDisplayName ?? "",
            soundFileName: tempAlarm.soundFileName
        )
    }

    private var endComps: DateComponents {
        Calendar.current.dateComponents([.hour, .minute], from: chimeEndTime)
    }

    private var hasUnsavedChanges: Bool { currentSnapshot != baseline }

    /// 取消鍵：有改動就先問，沒改動直接關（不打擾）。
    private func requestDismiss() {
        if hasUnsavedChanges {
            showingUnsavedPrompt = true
        } else {
            dismiss()
        }
    }

    /// 放棄變更：編輯模式要把「已經直接寫進鬧鐘」的鈴聲欄位還原
    /// （選鈴聲／錄音的 sheet 是就地寫 tempAlarm，而編輯模式的 tempAlarm 就是那顆真鬧鐘）。
    private func discardAndDismiss() {
        if isEditing {
            tempAlarm.recordingName = baseline.recordingName
            tempAlarm.recordingDisplayName = baseline.recordingDisplayName.isEmpty ? nil : baseline.recordingDisplayName
            tempAlarm.soundFileName = baseline.soundFileName
        }
        dismiss()
    }

    /// 目前時間輪的值格式化成標籤字串（跟著 12/24h 偏好）。
    private var timeAsLabel: String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        return Alarm.timeString(hour: c.hour ?? 0, minute: c.minute ?? 0,
                                use24h: settings.use24HourClock)
    }

    private let weekdayLabels: [(Int, String)] = [
        (1, "日"), (2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六")
    ]

    init(existingAlarm: Alarm? = nil) {
        self.existingAlarm = existingAlarm
        if let a = existingAlarm {
            // Edit mode: initialise state from the existing alarm
            _tempAlarm = State(initialValue: a)
            var comps = DateComponents()
            comps.hour = a.hour; comps.minute = a.minute
            let t = Calendar.current.date(from: comps) ?? Date()
            _selectedTime    = State(initialValue: t)
            _label           = State(initialValue: a.label)
            _selectedWeekdays = State(initialValue: Set(a.weekdays))
            _selectedTaskType = State(initialValue: a.recordingName.isEmpty ? .button : a.effectiveTaskType)
            _customPhrase     = State(initialValue: a.customDismissPhrase ?? "")
            _useNotificationMode = State(initialValue: a.effectiveBackgroundMode == .notification)
            _segmentedBurst = State(initialValue: a.effectiveSegmentedBurst)
            _selectedGroupIndex = State(initialValue: a.effectiveGroupIndex)
            _chimeCount = State(initialValue: a.effectiveChimeCount)
            // 區間報時：有迄時刻 + 間隔 → 開；否則迄預設＝起 + 30 分（家長一打開開關就有合理值）。
            let intervalOn = (a.chimeIntervalMinutes ?? 0) > 0 && a.chimeEndHour != nil
            let endH = a.chimeEndHour ?? ((a.hour * 60 + a.minute + 30) / 60 % 24)
            let endM = a.chimeEndMinute ?? ((a.minute + 30) % 60)
            var endComps = DateComponents(); endComps.hour = endH; endComps.minute = endM
            _chimeIntervalOn = State(initialValue: intervalOn)
            _chimeEndTime = State(initialValue: Calendar.current.date(from: endComps) ?? t)
            _chimeIntervalMinutes = State(initialValue: max(1, a.chimeIntervalMinutes ?? 5))
            _chimeVoice = State(initialValue: a.effectiveChimeVoice)
            _showAdvanced = State(initialValue: a.effectiveBackgroundMode == .notification
                                  || (!a.recordingName.isEmpty && a.effectiveTaskType == .voice))
            _todoIcon = State(initialValue: a.effectiveTodoIcon)
            _todoDuration = State(initialValue: a.effectiveTodoDurationMinutes)
            // 標籤剛好等於自己的時間字串（12h 或 24h 任一格式）→ 視為上次勾了「用時間當標籤」。
            _labelFollowsTime = State(initialValue:
                a.label == Alarm.timeString(hour: a.hour, minute: a.minute, use24h: true)
                || a.label == Alarm.timeString(hour: a.hour, minute: a.minute, use24h: false))
            // 未儲存變更防護的比對基準：必須跟上面每個 State 的初值一致，
            // 否則一進頁就會被誤判成「已改動」，每次取消都跳確認框。
            baseline = EditorSnapshot(
                hour: a.hour,
                minute: a.minute,
                label: a.label,
                weekdays: Set(a.weekdays),
                taskType: a.recordingName.isEmpty ? .button : a.effectiveTaskType,
                customPhrase: a.customDismissPhrase ?? "",
                notificationMode: a.effectiveBackgroundMode == .notification,
                segmentedBurst: a.effectiveSegmentedBurst,
                groupIndex: a.effectiveGroupIndex,
                chimeCount: a.effectiveChimeCount,
                chimeIntervalOn: intervalOn,
                chimeEndHour: endH,
                chimeEndMinute: endM,
                chimeInterval: max(1, a.chimeIntervalMinutes ?? 5),
                chimeVoice: a.effectiveChimeVoice,
                todoIcon: a.effectiveTodoIcon,
                todoDuration: a.effectiveTodoDurationMinutes,
                recordingName: a.recordingName,
                recordingDisplayName: a.recordingDisplayName ?? "",
                soundFileName: a.soundFileName
            )
        } else {
            // Create mode
            let fresh = Alarm(label: "起床囉", hour: 7, minute: 0, taskType: .button)
            let now = Date()
            _tempAlarm = State(initialValue: fresh)
            _selectedTime     = State(initialValue: now)
            _label            = State(initialValue: "起床囉")
            _selectedWeekdays = State(initialValue: [2, 3, 4, 5, 6])
            _selectedTaskType = State(initialValue: .button)
            // 區間報時的迄預設＝現在 + 30 分。
            let end = now.addingTimeInterval(30 * 60)
            _chimeEndTime = State(initialValue: end)
            let endParts = Calendar.current.dateComponents([.hour, .minute], from: end)
            // 同上：其餘欄位沿用 @State 的宣告預設值（notificationMode false / burst false /
            // group 0 / chime 1 / balloon / 10 分），這裡照抄一份當基準。
            let nowParts = Calendar.current.dateComponents([.hour, .minute], from: now)
            baseline = EditorSnapshot(
                hour: nowParts.hour ?? 0,
                minute: nowParts.minute ?? 0,
                label: "起床囉",
                weekdays: [2, 3, 4, 5, 6],
                taskType: .button,
                customPhrase: "",
                notificationMode: false,
                segmentedBurst: false,
                groupIndex: 0,
                chimeCount: 1,
                chimeIntervalOn: false,
                chimeEndHour: endParts.hour ?? 0,
                chimeEndMinute: endParts.minute ?? 0,
                chimeInterval: 5,
                chimeVoice: .female,
                todoIcon: .balloon,
                todoDuration: 10,
                recordingName: fresh.recordingName,
                recordingDisplayName: fresh.recordingDisplayName ?? "",
                soundFileName: fresh.soundFileName
            )
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SunnyColors.cloudWhite.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        timePicker
                        labelField
                        weekdayPicker
                        if settings.groupEnabled {
                            groupCard
                        }
                        // 報時群組：鈴聲欄換成「報時次數」（通知模式、響一次自動停）。
                        // 待辦群組：鈴聲欄換成「待辦語音 + 圖示 + 顯示時長」（不會響，只在主頁冒圖示）。
                        // 一般群組維持原本的鈴聲與背景模式選擇。
                        if chimeActive {
                            ChimeCardView(
                                startTime: selectedTime,
                                chimeCount: $chimeCount,
                                intervalOn: $chimeIntervalOn,
                                endTime: $chimeEndTime,
                                intervalMinutes: $chimeIntervalMinutes,
                                voice: $chimeVoice,
                                isPreviewing: previewingRow == "chime",
                                onPreview: { previewChime() },
                                pickerLocale: pickerLocale
                            )
                        } else if todoActive {
                            todoCard
                        } else {
                            ringtoneCard
                            // 溫和提醒模式、口令關閉：多數鬧鐘用不到 → 收進「進階選項」，
                            // 新增鬧鐘頁只剩 時間／標籤／重覆／鈴聲 四張卡。改過的鬧鐘進頁自動展開。
                            advancedToggleRow
                            if showAdvanced {
                                backgroundModeCard
                                // 口令關閉（Enable phrase dismiss）放最後：實際很少用，
                                // 不該卡在「鈴聲」與「背景響鈴方式」這兩個常改的欄位中間。
                                dismissMethodCard
                            }
                        }
                    }
                    .padding(24)
                }
                if isComposingChime {
                    composingOverlay
                }
            }
            .onChange(of: selectedTime) { _, _ in
                if labelFollowsTime { label = timeAsLabel }
            }
            .onChange(of: tempAlarm.recordingName) { _, newValue in
                if newValue.isEmpty, selectedTaskType == .voice {
                    selectedTaskType = .button
                }
            }
            .onReceive(previewPlayer.$isPlaying) { playing in
                if !playing { previewingRow = nil }
            }
            .alert("todo_needs_recording_title", isPresented: $showingTodoNeedsRecording) {
                Button("好", role: .cancel) {}
            } message: {
                Text("todo_needs_recording_msg")
            }
            .onDisappear { previewPlayer.stop() }
            .navigationTitle(isEditing ? String(localized: "編輯鬧鐘") : String(localized: "新增鬧鐘"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { requestDismiss() }
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.sunnyGray)
                        .disabled(isComposingChime)
                }
                // Save lives in the top-right corner (opposite Cancel), iOS-standard sheet layout.
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? String(localized: "儲存修改") : String(localized: "儲存鬧鐘")) { saveAlarm() }
                        .font(SunnyFonts.caption())
                        .fontWeight(.semibold)
                        .foregroundStyle(SunnyColors.lanternOrange)
                        .disabled(isSaving)
                }
            }
            // 有未儲存的變更時，擋掉「往下滑關閉」——那條路沒有攔截點，滑掉就沒了。
            // 使用者仍可按「取消」，那會走下面的確認框。
            .interactiveDismissDisabled(hasUnsavedChanges || isComposingChime)
            // 編輯器蓋在首頁上 → 首頁動畫暫停（見 SheetPresenceTracker）。
            .countsAsPresentedSheet()
            // 取消 + 有改動 → 先問。預設（第一個、非破壞性）＝儲存，避免手滑丟掉剛設好的資料。
            .confirmationDialog(
                "尚未儲存的變更",
                isPresented: $showingUnsavedPrompt,
                titleVisibility: .visible
            ) {
                Button(isEditing ? String(localized: "儲存修改") : String(localized: "儲存鬧鐘")) {
                    saveAlarm()
                }
                Button("放棄變更", role: .destructive) { discardAndDismiss() }
                Button("繼續編輯", role: .cancel) {}
            } message: {
                Text("這顆鬧鐘有還沒儲存的變更。")
            }
        }
    }

    /// Locale handed to the time wheel so it shows 12h/24h matching the app's clock setting,
    /// not just whatever the UI-language locale defaults to. (use24HourClock lives in AppSettings
    /// and is the same toggle HomeView / AlarmListView already obey.)
    private var pickerLocale: Locale {
        var components = Locale.Components(locale: localization.locale)
        components.hourCycle = settings.use24HourClock ? .zeroToTwentyThree : .oneToTwelve
        return Locale(components: components)
    }

    // MARK: - Subviews

    private var timePicker: some View {
        WatercolorCard {
            DatePicker("", selection: $selectedTime, displayedComponents: [.hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                // iOS 26 Liquid Glass adaptive color makes wheel text invisible on
                // the light WatercolorCard background — force light scheme for dark text.
                .colorScheme(.light)
                // Force the wheel's hour cycle to follow the app's 12h/24h setting.
                .environment(\.locale, pickerLocale)
        }
    }

    private var labelField: some View {
        WatercolorCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("標籤")
                        .font(SunnyFonts.caption())
                        .foregroundStyle(showLabelHint ? SunnyColors.leafFresh : SunnyColors.sunnyGray)
                        .contentShape(Rectangle())
                        .onLongPressGesture(
                            minimumDuration: 0.5,
                            pressing: { isPressing in
                                if !isPressing {
                                    withAnimation(.easeOut(duration: 0.2)) { showLabelHint = false }
                                }
                            },
                            perform: {
                                labelLongPressed = true
                                withAnimation(.spring(duration: 0.2)) { showLabelHint = true }
                            }
                        )
                        .simultaneousGesture(TapGesture().onEnded {
                            defer { labelLongPressed = false }
                            guard !labelLongPressed else { return }
                            handleLabelTap()
                        })
                    TextField("例如：上學囉！", text: $label)
                        .font(SunnyFonts.body())
                        .foregroundStyle(SunnyColors.nightIndigo.opacity(labelFollowsTime ? 0.55 : 1))
                        .multilineTextAlignment(.trailing)
                        .tint(SunnyColors.leafFresh)
                        .colorScheme(.light)
                        .disabled(labelFollowsTime)   // 勾選中標籤由時間接管，擋掉手動輸入
                }
                .padding(.horizontal, 20)
                .frame(height: 56)

                // 用時間當標籤：勾選＝標籤永遠是上面時間輪的值（改時間就跟著變）。
                Divider().padding(.leading, 20)
                Button {
                    labelFollowsTime.toggle()
                    if labelFollowsTime { label = timeAsLabel }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: labelFollowsTime ? "checkmark.square.fill" : "square")
                            .foregroundStyle(labelFollowsTime ? SunnyColors.leafFresh : SunnyColors.sunnyGray)
                        Text("用時間當標籤")
                            .font(SunnyFonts.caption(14))
                            .foregroundStyle(SunnyColors.sunnyGray)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                if showLabelHint {
                    Text(LocalizedStringKey("alarm_label_hint"))
                        .font(.caption)
                        .foregroundStyle(SunnyColors.leafFresh.opacity(0.85))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    /// 多人鬧鐘：選這個鬧鐘屬於哪一個群組（哥哥 / 妹妹…）。只有家長在設定頁開啟分組時才出現。
    /// 群組名稱由設定頁集中管理，這裡只負責「選哪一組」（水平捲動的膠囊按鈕）。
    private var groupCard: some View {
        WatercolorCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("group_select_label", systemImage: "person.2.fill")
                    .font(SunnyFonts.caption())
                    .foregroundStyle(SunnyColors.sunnyGray)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(0..<settings.effectiveGroupCount), id: \.self) { i in
                            GroupChip(
                                letter: String(Character(UnicodeScalar(UInt8(65 + i)))),
                                title: settings.groupDisplayName(i),
                                isSelected: selectedGroupIndex == i
                            ) {
                                selectedGroupIndex = i
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    /// 這顆鬧鐘是否屬於「報時群組」（要啟用分組 + 該組開了報時）。決定顯示「鈴聲」還是「報時」卡。
    private var chimeActive: Bool {
        settings.groupEnabled && settings.isGroupChimeEnabled(selectedGroupIndex)
    }

    /// 「進階選項」開關列：展開才顯示溫和提醒模式與口令關閉兩張卡。
    private var advancedToggleRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                Text("editor_advanced_options")
                    .font(SunnyFonts.caption(15))
                // 收起時提示裡面有哪些東西；展開時不重複。
                if !showAdvanced {
                    Text(verbatim: "·")
                    Text(useNotificationMode
                         ? LocalizedStringKey("溫和提醒模式（自動停、省電）")
                         : LocalizedStringKey("啟用口令關閉"))
                        .font(SunnyFonts.caption(13))
                        .lineLimit(1)
                }
                Spacer()
            }
            .foregroundStyle(SunnyColors.sunnyGray)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("editor_advanced_options"))
        .accessibilityValue(Text(showAdvanced ? "group_on_badge" : "group_off_badge"))
    }

    /// 儲存時合成報時語音的遮罩（區間報時最多 12 句，每句約 1 秒；期間不能再按儲存／取消）。
    private var composingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(SunnyColors.lanternOrange)
                Text("chime_composing")
                    .font(SunnyFonts.caption())
                    .foregroundStyle(SunnyColors.nightIndigo)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 18).fill(SunnyColors.cloudWhite))
        }
        .transition(.opacity)
    }

    /// 這顆是否屬於「待辦群組」（啟用分組 + 該組開了待辦）。決定顯示「鈴聲」還是「待辦語音」卡。
    private var todoActive: Bool {
        settings.groupEnabled && settings.isGroupTodoEnabled(selectedGroupIndex)
    }

    private var todoRecordingSubtitle: Text {
        guard !tempAlarm.recordingName.isEmpty else { return Text(LocalizedStringKey("尚未錄音")) }
        return Text("🎤 \(tempAlarm.effectiveRecordingDisplayName)")
    }

    /// 顯示時長文字：0 → 直到點開；其餘 → N 分鐘。
    private func todoDurationText(_ minutes: Int) -> String {
        minutes == 0 ? L("todo_duration_until_tapped") : L("todo_duration_minutes %lld", minutes)
    }

    /// 待辦卡：取代鈴聲卡。家長錄/選一段提醒語音、挑主頁圖示、設顯示時長。待辦不會響，
    /// 時間到時在主頁吉祥物旁冒出圖示，兒童長按播放。
    private var todoCard: some View {
        WatercolorCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Text(todoIcon.emoji).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("todo_card_title")
                            .font(SunnyFonts.caption())
                            .foregroundStyle(SunnyColors.nightIndigo)
                        Text("todo_card_subtitle")
                            .font(SunnyFonts.caption(13))
                            .foregroundStyle(SunnyColors.sunnyGray.opacity(0.82))
                    }
                    Spacer()
                }

                Divider()

                // 提醒語音：試聽 + 名稱
                HStack(spacing: 14) {
                    Button { togglePreview("custom") } label: {
                        Image(systemName: previewingRow == "custom" ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title)
                            .foregroundStyle(previewingRow == "custom"
                                             ? SunnyColors.lanternOrange
                                             : (tempAlarm.recordingName.isEmpty
                                                ? SunnyColors.sunnyGray.opacity(0.4)
                                                : SunnyColors.leafFresh))
                            .symbolEffect(.pulse, isActive: previewingRow == "custom")
                    }
                    .buttonStyle(.plain)
                    .disabled(tempAlarm.recordingName.isEmpty)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("todo_voice_label")
                            .font(SunnyFonts.caption())
                            .foregroundStyle(SunnyColors.nightIndigo)
                        todoRecordingSubtitle
                            .font(SunnyFonts.caption(14))
                            .foregroundStyle(tempAlarm.recordingName.isEmpty
                                             ? SunnyColors.sunnyGray : SunnyColors.lanternOrange)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button { showingTodoRecorder = true } label: {
                        Label("todo_record", systemImage: "mic.fill")
                            .font(SunnyFonts.caption(14))
                            .foregroundStyle(SunnyColors.leafFresh)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { showingTodoPicker = true } label: {
                        Label("todo_pick", systemImage: "square.and.arrow.down")
                            .font(SunnyFonts.caption(14))
                            .foregroundStyle(SunnyColors.skyBlue)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                // 主頁圖示挑選
                VStack(alignment: .leading, spacing: 8) {
                    Text("todo_icon_label")
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.sunnyGray)
                    HStack(spacing: 10) {
                        ForEach(TodoIcon.allCases) { icon in
                            Button { todoIcon = icon } label: {
                                Text(icon.emoji)
                                    .font(.title2)
                                    .frame(width: 42, height: 42)
                                    .background(
                                        Circle().fill(todoIcon == icon
                                                      ? SunnyColors.lanternOrange.opacity(0.18)
                                                      : SunnyColors.sunnyGray.opacity(0.1))
                                    )
                                    .overlay(
                                        Circle().strokeBorder(todoIcon == icon
                                                              ? SunnyColors.lanternOrange
                                                              : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider()

                // 顯示時長
                HStack {
                    Label("todo_duration_label", systemImage: "timer")
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.nightIndigo)
                    Spacer()
                    Menu {
                        Picker("todo_duration_label", selection: $todoDuration) {
                            ForEach(todoDurationOptions, id: \.self) { opt in
                                Text(verbatim: todoDurationText(opt)).tag(opt)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(verbatim: todoDurationText(todoDuration))
                                .foregroundStyle(SunnyColors.lanternOrange)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(SunnyColors.sunnyGray)
                        }
                        .font(SunnyFonts.caption())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .sheet(isPresented: $showingTodoRecorder) {
            // 完整對齊「錄音管理」的錄音體驗（倒數秒環 + 辨識錄音內容自動命名）：直接重用
            // VoiceClipRecorderSheet，錄好的 clip 收進音檔庫，並設成這則待辦的提醒語音。
            VoiceClipRecorderSheet { clip in
                modelContext.insert(clip)
                let base = String(clip.fileName.dropLast(4))   // 去掉 ".m4a"
                tempAlarm.recordingName = base
                tempAlarm.recordingDisplayName = clip.name
            }
        }
        .sheet(isPresented: $showingTodoPicker) {
            VoiceLibraryView(currentFileName: tempAlarm.soundFileName) { _, chosenRecording in
                tempAlarm.recordingName = chosenRecording?.baseName ?? ""
                tempAlarm.recordingDisplayName = chosenRecording?.displayName
            }
        }
    }

    private var weekdayPicker: some View {
        WatercolorCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("重覆")
                        .font(SunnyFonts.caption())
                        .foregroundStyle(showDaysHint ? SunnyColors.leafFresh : SunnyColors.sunnyGray)
                        .contentShape(Rectangle())
                        .onLongPressGesture(
                            minimumDuration: 0.5,
                            pressing: { isPressing in
                                if !isPressing {
                                    withAnimation(.easeOut(duration: 0.2)) { showDaysHint = false }
                                }
                            },
                            perform: {
                                daysLongPressed = true
                                withAnimation(.spring(duration: 0.2)) { showDaysHint = true }
                            }
                        )
                        .simultaneousGesture(TapGesture().onEnded {
                            defer { daysLongPressed = false }
                            guard !daysLongPressed else { return }
                            handleDaysTap()
                        })
                    Spacer(minLength: 8)
                    HStack(spacing: 5) {
                        ForEach(weekdayLabels, id: \.0) { num, sym in
                            WeekdayChip(
                                symbol: sym,
                                isWeekend: num == 1 || num == 7,
                                isSelected: selectedWeekdays.contains(num)
                            ) {
                                if selectedWeekdays.contains(num) {
                                    selectedWeekdays.remove(num)
                                } else {
                                    selectedWeekdays.insert(num)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: 56)

                if showDaysHint {
                    Text(LocalizedStringKey("alarm_days_hint"))
                        .font(.caption)
                        .foregroundStyle(SunnyColors.leafFresh.opacity(0.85))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var voiceDismissAvailable: Bool {
        !tempAlarm.recordingName.isEmpty
    }

    private var isVoiceDismissEnabled: Bool {
        voiceDismissAvailable && selectedTaskType == .voice
    }

    private var voiceDismissBinding: Binding<Bool> {
        Binding(
            get: { isVoiceDismissEnabled },
            set: { selectedTaskType = $0 ? .voice : .button }
        )
    }

    private var dismissMethodCard: some View {
        WatercolorCard {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: voiceDismissBinding) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("啟用口令關閉", systemImage: "mic.fill")
                            .font(SunnyFonts.caption())
                            .foregroundStyle(voiceDismissAvailable ? SunnyColors.nightIndigo : SunnyColors.sunnyGray)
                        Text(voiceDismissAvailable
                             ? LocalizedStringKey("已選自錄鈴聲，說出關鍵字即可關閉。")
                             : LocalizedStringKey("先在「自定錄音」選一個鈴聲，才能開啟口令關閉。"))
                            .font(SunnyFonts.caption(13))
                            .foregroundStyle(SunnyColors.sunnyGray.opacity(0.82))
                    }
                }
                .tint(SunnyColors.lanternOrange)
                .disabled(!voiceDismissAvailable)

                // 口令關閉只在前景/亮屏（App 沒被殺、螢幕沒關）時有效——靠麥克風即時辨識關鍵字。
                // 關屏或關閉 App 走的是自動停的提醒模式，沒有麥克風可聽口令。必須對 user 講清楚。
                // 中英獨立字串：en/zh-Hant 都在 Localizable.xcstrings 明確給值，避免英文版掉回中文。
                Label(LocalizedStringKey("口令關閉需保持螢幕開啟，不可關屏。"), systemImage: "exclamationmark.triangle.fill")
                    .font(SunnyFonts.caption(12))
                    .foregroundStyle(SunnyColors.lanternOrange.opacity(0.95))

                // 自定口令輸入 — 只在口令關閉開啟時顯示。自定 + 預設詞都認。
                if isVoiceDismissEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("自定口令（選填，例如：太陽公公起床了）", text: $customPhrase)
                            .font(SunnyFonts.caption(15))
                            .foregroundStyle(SunnyColors.nightIndigo)
                            .tint(SunnyColors.leafFresh)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.82))
                            )
                            // iOS 26 Liquid Glass adaptive color 會把輸入文字染成跟背景同色（深色模式下看不到字）。
                            // 強制 light scheme，輸入文字才會是深色可見。同 VoiceClipRecorderSheet 的修法。
                            .colorScheme(.light)
                        Text("除了預設的「我起床了」等，也會認你設定的口令。多個用逗號分隔。")
                            .font(SunnyFonts.caption(12))
                            .foregroundStyle(SunnyColors.sunnyGray.opacity(0.82))
                    }
                    .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    /// 背景/鎖屏/被殺時的響鈴策略。預設關（AlarmKit 強力叫醒）；開啟＝溫和的 Time-Sensitive 通知，
    /// 響一次自動停、不耗電——適合「提醒型、就算沒人理也不會一直響到沒電」。UI 對齊「啟用口令關閉」。
    private var backgroundModeCard: some View {
        WatercolorCard {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $useNotificationMode) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("溫和提醒模式（自動停、省電）",
                              systemImage: useNotificationMode ? "bell.badge" : "alarm.fill")
                            .font(SunnyFonts.caption())
                            .foregroundStyle(SunnyColors.nightIndigo)
                        Text(useNotificationMode
                             ? LocalizedStringKey("用通知響一下就自動停、不會一直響到沒電；可突破專注模式，但破不了實體靜音，較不會吵醒熟睡的孩子。")
                             : LocalizedStringKey("預設：系統鬧鐘，破靜音、持續響直到關掉（最會叫醒人）。但 app 被滑掉殺掉後會一直響、較耗電。"))
                            .font(SunnyFonts.caption(13))
                            .foregroundStyle(SunnyColors.sunnyGray.opacity(0.82))
                    }
                }
                .tint(SunnyColors.lanternOrange)

                // 切段子開關：只在溫和提醒開啟時出現，預設 off。off = 只響一下（單通知、不堆疊，避免圖1的整排通知）；
                // on = 用秒級錯開的多顆通知把語音堆到 ~30s。中英字串都明確進 Localizable.xcstrings。
                if useNotificationMode {
                    Divider()
                    Toggle(isOn: $segmentedBurst) {
                        VStack(alignment: .leading, spacing: 3) {
                            // 秒數跟著設定走（10/20/30），不再寫死 30——否則家長把持續時間調成
                            // 10 秒後，這裡還寫「響滿 30 秒」就是騙人的。
                            Label(L("切段響滿 %@ 秒", String(settings.effectiveBurstSpanSeconds)),
                                  systemImage: segmentedBurst ? "waveform.badge.plus" : "waveform")
                                .font(SunnyFonts.caption())
                                .foregroundStyle(SunnyColors.nightIndigo)
                            Text(L("把語音切成多段、用堆疊通知重複響到約 %@ 秒；關閉時只響一下（較短）。",
                                   String(settings.effectiveBurstSpanSeconds)))
                                .font(SunnyFonts.caption(13))
                                .foregroundStyle(SunnyColors.sunnyGray.opacity(0.82))
                        }
                    }
                    .tint(SunnyColors.lanternOrange)

                    // 警告只在切段「開啟」時出現——關閉時是單通知、可靠響一下，沒什麼好警告的。
                    if segmentedBurst {
                        Label(L("切段可能被 iPhone 在幾秒內關掉，不保證響滿 %@ 秒。",
                                String(settings.effectiveBurstSpanSeconds)),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(SunnyFonts.caption(12))
                            .foregroundStyle(SunnyColors.lanternOrange.opacity(0.95))

                        // 段間隔（1/2 秒）是全域設定，住在 設定 >「切段間隔」——不放這裡，
                        // 因為本編輯器的欄位都是暫存、按「儲存」才生效，全域設定立即寫入會
                        // 讓「按取消卻改到了東西」。這行只指路。
                        Text(LocalizedStringKey("持續時間與段間隔可在「設定」調整。"))
                            .font(SunnyFonts.caption(12))
                            .foregroundStyle(SunnyColors.sunnyGray.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Label / Days tap actions

    /// 點 "標籤" 文字：填入目前設定的時間 / 再點清空
    private func handleLabelTap() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        let timeStr: String
        if settings.use24HourClock {
            timeStr = String(format: "%02d:%02d", h, m)
        } else {
            let h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
            timeStr = String(format: "%d:%02d %@", h12, m, h < 12 ? "AM" : "PM")
        }
        label = (label == timeStr) ? "" : timeStr
    }

    /// 點 "重覆" 文字：全選 / 全清除（交替）
    private func handleDaysTap() {
        let all: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
        selectedWeekdays = (selectedWeekdays == all) ? [] : all
    }

    // MARK: - Preview

    /// 試聽報時：用目前選的時間 + 次數合成報時音（背景執行緒）後播放一次。
    /// ⚠️ 用 previewingRow=="chime" 當狀態（不要另立會被 onReceive 歸零的旗標）：previewPlayer.stop()
    ///    會同步觸發 $isPlaying→false 的 onReceive 把 previewingRow 清掉，所以要在 stop() 之後才設
    ///    previewingRow，合成期間 isPlaying 不變動、previewingRow 維持 "chime"，播完才被 onReceive 清掉。
    private func previewChime() {
        if previewingRow == "chime" {
            previewPlayer.stop()
            previewingRow = nil
            return
        }
        previewPlayer.stop()
        previewingRow = "chime"
        let comps = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        let h = comps.hour ?? 7
        let m = comps.minute ?? 0
        let loc = SunnyLocalization.locale
        let voice = chimeVoice
        Task {
            // 試聽寫到 tmp（以前每按一次就在 Library/Sounds 留一個孤兒檔）。
            let url = await Task.detached(priority: .userInitiated) {
                ChimeSoundComposer.composePreview(hour: h, minute: m, locale: loc, voice: voice)
            }.value
            await MainActor.run {
                guard previewingRow == "chime", let url else {
                    if previewingRow == "chime" { previewingRow = nil }
                    return
                }
                previewPlayer.play(url: url, loop: false)
            }
        }
    }

    private func togglePreview(_ row: String) {
        if previewingRow == row {
            previewPlayer.stop()
            previewingRow = nil
            return
        }
        previewPlayer.stop()
        let url: URL?
        if row == "builtin" {
            url = Bundle.main.url(forResource: tempAlarm.soundFileName, withExtension: nil)
        } else {
            guard AppPaths.recordingExists(named: tempAlarm.recordingName) else { return }
            url = AppPaths.recordingURL(named: tempAlarm.recordingName)
        }
        guard let url else { return }
        previewingRow = row
        previewPlayer.play(url: url, loop: false)
    }

    // Whether the current soundFileName is a built-in bundled sound.
    private var isBuiltinSelected: Bool {
        !tempAlarm.soundFileName.hasPrefix("alarm_")
    }

    // Display subtitle for the built-in row.
    // 回傳 Text（非 String）：鈴聲名走 LocalizedStringKey 才能在英文版翻譯；
    // emoji 與檔名/錄音名是 verbatim 不翻譯。
    private var builtinSubtitle: Text {
        switch tempAlarm.soundFileName {
        case "sunny_wake.caf":  return Text("☀️ \(Text(LocalizedStringKey("陽光起床")))")
        case "leaf_rustle.caf": return Text("🍃 \(Text(LocalizedStringKey("樹葉沙沙")))")
        default:                return isBuiltinSelected ? Text(tempAlarm.soundFileName) : Text(LocalizedStringKey("未選擇"))
        }
    }

    // Display subtitle for the custom recording row.
    private var customSubtitle: Text {
        guard !tempAlarm.recordingName.isEmpty else { return Text(LocalizedStringKey("未選擇")) }
        return Text("🎤 \(tempAlarm.effectiveRecordingDisplayName)")  // 錄音名是用戶資料，不翻譯（插值值不會被在地化查表）
    }

    private var ringtoneCard: some View {
        WatercolorCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("鈴聲")
                    .font(SunnyFonts.caption())
                    .foregroundStyle(SunnyColors.sunnyGray)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                // Row 1: built-in sounds
                ringtoneRow(
                    icon: "music.note",
                    iconColor: SunnyColors.wheatGold,
                    title: "內建鈴聲",
                    subtitle: builtinSubtitle,
                    isSelected: isBuiltinSelected,
                    isPreviewing: previewingRow == "builtin",
                    onIconTap: { togglePreview("builtin") },
                    onChevronTap: { showingBuiltinPicker = true }
                )

                Divider().padding(.leading, 62)

                // Row 2: self-recorded clips
                ringtoneRow(
                    icon: "mic.fill",
                    iconColor: SunnyColors.leafFresh,
                    title: "自定鈴聲(錄音)",
                    subtitle: customSubtitle,
                    isSelected: !isBuiltinSelected,
                    isPreviewing: previewingRow == "custom",
                    onIconTap: { togglePreview("custom") },
                    onChevronTap: { showingCustomPicker = true }
                )
                .padding(.bottom, 4)
            }
        }
        .sheet(isPresented: $showingBuiltinPicker) {
            RingtonePickerSheet(currentFileName: tempAlarm.soundFileName, mode: .bundled) { chosenSoundFile, _ in
                tempAlarm.soundFileName = chosenSoundFile
                tempAlarm.recordingName = ""
                tempAlarm.recordingDisplayName = nil
            }
        }
        .sheet(isPresented: $showingCustomPicker) {
            VoiceLibraryView(currentFileName: tempAlarm.soundFileName) { chosenSoundFile, chosenRecording in
                tempAlarm.soundFileName = chosenSoundFile
                tempAlarm.recordingName = chosenRecording?.baseName ?? ""
                tempAlarm.recordingDisplayName = chosenRecording?.displayName
            }
        }
    }

    @ViewBuilder
    private func ringtoneRow(
        icon: String,
        iconColor: Color,
        title: LocalizedStringKey,
        subtitle: Text,
        isSelected: Bool,
        isPreviewing: Bool,
        onIconTap: @escaping () -> Void,
        onChevronTap: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            // Left icon: tap to preview current sound
            Button(action: onIconTap) {
                Image(systemName: isPreviewing ? "stop.circle.fill" : icon)
                    .font(.title)
                    .foregroundStyle(isPreviewing ? SunnyColors.lanternOrange : iconColor)
                    .symbolEffect(.pulse, isActive: isPreviewing)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SunnyFonts.caption())
                    .foregroundStyle(SunnyColors.nightIndigo)
                subtitle
                    .font(SunnyFonts.caption(14))
                    .foregroundStyle(isSelected ? SunnyColors.lanternOrange : SunnyColors.sunnyGray)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(SunnyColors.leafFresh)
            }
            // Right chevron: tap to navigate to picker
            Button(action: onChevronTap) {
                NavigationChevron()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Save logic

    private func saveAlarm() {
        // 待辦：存檔前先驗證必須有錄音。數量不在這裡擋——免費版總量(鬧鐘+待辦合計)由首頁「＋」鈕
        // 統一以 alarms.count < FeatureLimits.maxAlarms 把關（待辦本身就是 Alarm，已計入總數）。
        if todoActive {
            guard !tempAlarm.recordingName.isEmpty else {
                showingTodoNeedsRecording = true
                return
            }
        }

        isSaving = true
        let comps = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        let trimmed = label.trimmingCharacters(in: .whitespaces)

        // Apply changes to the alarm object (create or edit)
        tempAlarm.label    = trimmed.isEmpty ? "起床囉" : trimmed
        tempAlarm.hour     = comps.hour ?? 7
        tempAlarm.minute   = comps.minute ?? 0
        tempAlarm.weekdays = selectedWeekdays.isEmpty ? [2, 3, 4, 5, 6] : Array(selectedWeekdays).sorted()
        tempAlarm.taskType = isVoiceDismissEnabled ? .voice : .button
        // 自定口令：trim 後空字串存 nil（effectiveCustomPhrases 回空陣列）。
        let phrase = customPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        tempAlarm.customDismissPhrase = phrase.isEmpty ? nil : phrase
        tempAlarm.backgroundRingMode = useNotificationMode ? .notification : .alarmKit
        // 切段只在溫和提醒模式下有意義；非通知模式一律存 false。
        tempAlarm.segmentedBurst = useNotificationMode ? segmentedBurst : false
        // 群組：只有啟用分組時才寫回（未啟用時保留鬧鐘原本的 groupIndex，不強制歸 0）。
        if settings.groupEnabled {
            tempAlarm.groupIndex = selectedGroupIndex
        }

        // 三種模式：報時 / 待辦 / 一般。報時的實際語音檔在下面的 Task 裡（背景執行緒）合成。
        let chimeOn = chimeActive
        let todoOn = todoActive
        let previousSound = tempAlarm.soundFileName
        // 這顆鬧鐘之前留下的所有報時檔（單一時刻＝soundFileName；區間＝slot 陣列）。換模式／改時刻後清掉。
        let previousChimeFiles = Set((tempAlarm.chimeSlotSoundFiles ?? []) + [previousSound])
            .filter { $0.hasPrefix(Alarm.chimeFilePrefix) }
        // 統一先把「另外兩種模式」的殘留欄位清掉，避免切換模式後留下舊狀態。
        func clearChimeIfNeeded() {
            if previousSound.hasPrefix(Alarm.chimeFilePrefix) {
                tempAlarm.soundFileName = "sunny_wake.caf"
            }
            for f in previousChimeFiles { ChimeSoundComposer.removeChimeFile(named: f) }
            tempAlarm.chimeSlotSoundFiles = nil
            tempAlarm.chimeEndHour = nil
            tempAlarm.chimeEndMinute = nil
            tempAlarm.chimeIntervalMinutes = nil
            tempAlarm.chimeVoice = nil
        }
        if chimeOn {
            tempAlarm.chimeCount = chimeCount
            if chimeIntervalOn {
                tempAlarm.chimeEndHour = endComps.hour ?? 0
                tempAlarm.chimeEndMinute = endComps.minute ?? 0
                tempAlarm.chimeIntervalMinutes = chimeIntervalMinutes
            } else {
                tempAlarm.chimeEndHour = nil
                tempAlarm.chimeEndMinute = nil
                tempAlarm.chimeIntervalMinutes = nil
            }
            tempAlarm.chimeVoice = chimeVoice.rawValue
            tempAlarm.todoIcon = nil
            tempAlarm.todoDurationMinutes = nil
            tempAlarm.recordingName = ""          // 報時沒有錄音；清掉才不會誤判成口令關閉
            tempAlarm.recordingDisplayName = nil
            tempAlarm.taskType = .button          // 報時用按鈕關（沒有錄音可做口令辨識）
            // 報時一律走「通知模式」：響一次（把報時音檔放完）就自動停。若走 AlarmKit 會無限 loop
            // → 報完還一直響（使用者回報「響不停」）。連報次數由 AlarmScheduler 排多顆通知達成。
            tempAlarm.backgroundRingMode = .notification
            tempAlarm.segmentedBurst = false
        } else if todoOn {
            // 待辦：不會響（schedule/syncAlarm 會因 isTodo 跳過）。只存圖示 + 顯示時長 + 錄音。
            tempAlarm.todoIcon = todoIcon.rawValue
            tempAlarm.todoDurationMinutes = todoDuration
            tempAlarm.chimeCount = nil
            tempAlarm.taskType = .button
            clearChimeIfNeeded()
        } else {
            tempAlarm.chimeCount = nil
            tempAlarm.todoIcon = nil
            tempAlarm.todoDurationMinutes = nil
            clearChimeIfNeeded()
        }

        if !isEditing {
            modelContext.insert(tempAlarm)
        }
        // (Edit mode: tempAlarm IS the existing @Model object — SwiftData tracks changes automatically)

        let chimeSlots = tempAlarm.chimeSlotTimes
        let chimeLocale = SunnyLocalization.locale
        let chimeVoiceChoice = chimeVoice
        Task {
            // 報時：每個時刻各合成「一句」語音 CAF（保持短、通知音不被截；區間報時每句內容不同）。
            // 連報次數由 AlarmScheduler 排多顆秒級錯開的通知達成，所以這裡不把 N 次塞進同一個檔。
            if chimeOn {
                withAnimation { isComposingChime = true }
                let files = await Task.detached(priority: .userInitiated) {
                    ChimeSoundComposer.composeSlots(chimeSlots, locale: chimeLocale, voice: chimeVoiceChoice)
                }.value
                await MainActor.run {
                    if let files, let first = files.first {
                        tempAlarm.chimeSlotSoundFiles = files
                        tempAlarm.soundFileName = first
                        for f in previousChimeFiles where !files.contains(f) {
                            ChimeSoundComposer.removeChimeFile(named: f)
                        }
                    } else {
                        // 合成失敗（極少數）→ 保留原 soundFileName，AlarmScheduler 會用它排每個時刻，不會無聲。
                        tempAlarm.chimeSlotSoundFiles = nil
                    }
                    withAnimation { isComposingChime = false }
                }
            }
            // UNNotification fallback (no-op while AlarmKit is authorized — it stands down).
            try? await AlarmScheduler.shared.schedule(alarm: tempAlarm)
            // AlarmKit is NOT armed here: it's managed by HomeView's foreground/background switch,
            // which re-arms from the current model when the app leaves the foreground. Arming a
            // system alarm while the editor (foreground) is open would make AlarmKit fire a banner
            // and background the app at the alarm time instead of the in-app ring.
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        }
    }
}

// MARK: - WeekdayChip

private struct WeekdayChip: View {
    let symbol: String
    let isWeekend: Bool
    let isSelected: Bool
    let onTap: () -> Void

    // Weekend selected = lighter jade; weekday = full jade
    private var selectedFill: Color {
        isWeekend ? SunnyColors.leafFresh.opacity(0.6) : SunnyColors.leafFresh
    }

    var body: some View {
        Button(action: onTap) {
            Text(LocalizedStringKey(symbol))
                .font(.caption2.weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(isSelected ? .white : SunnyColors.sunnyGray)
                // 30pt（原 34）：7 顆 × 34 + 間距剛好吃光 iPhone 直向卡片內寬，英文的「Days」被擠成「D…」。
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(isSelected ? selectedFill : SunnyColors.sunnyGray.opacity(0.12))
                )
        }
        .sunnyButtonStyle()
    }
}

// MARK: - GroupChip (multi-person alarm group selector)

private struct GroupChip: View {
    let letter: String
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                Text(verbatim: letter)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? .white : SunnyColors.forestDeep)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(isSelected
                                      ? Color.white.opacity(0.28)
                                      : SunnyColors.leafFresh.opacity(0.18))
                    )
                Text(verbatim: title)
                    .font(SunnyFonts.caption(15))
                    .foregroundStyle(isSelected ? .white : SunnyColors.nightIndigo)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(isSelected
                               ? SunnyColors.leafFresh
                               : SunnyColors.sunnyGray.opacity(0.12))
            )
        }
        .sunnyButtonStyle()
    }
}

#Preview("Create") {
    AlarmEditorView()
        .modelContainer(for: Alarm.self, inMemory: true)
}
