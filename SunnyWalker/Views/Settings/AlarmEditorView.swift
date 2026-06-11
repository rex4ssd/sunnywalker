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
    @StateObject private var previewPlayer = AudioPlayer()
    @State private var previewingRow: String? = nil
    // Label tap/long-press
    @State private var showLabelHint = false
    @State private var labelLongPressed = false
    // Days tap/long-press
    @State private var showDaysHint = false
    @State private var daysLongPressed = false

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
        } else {
            // Create mode
            _tempAlarm = State(initialValue: Alarm(label: "起床囉", hour: 7, minute: 0, taskType: .button))
            _selectedTime     = State(initialValue: Date())
            _label            = State(initialValue: "起床囉")
            _selectedWeekdays = State(initialValue: [2, 3, 4, 5, 6])
            _selectedTaskType = State(initialValue: .button)
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
                        ringtoneCard
                        dismissMethodCard
                    }
                    .padding(24)
                }
            }
            .onChange(of: tempAlarm.recordingName) { _, newValue in
                if newValue.isEmpty, selectedTaskType == .voice {
                    selectedTaskType = .button
                }
            }
            .onReceive(previewPlayer.$isPlaying) { playing in
                if !playing { previewingRow = nil }
            }
            .onDisappear { previewPlayer.stop() }
            .navigationTitle(isEditing ? "編輯鬧鐘" : "新增鬧鐘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.sunnyGray)
                }
                // Save lives in the top-right corner (opposite Cancel), iOS-standard sheet layout.
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "儲存修改" : "儲存鬧鐘") { saveAlarm() }
                        .font(SunnyFonts.caption())
                        .fontWeight(.semibold)
                        .foregroundStyle(SunnyColors.lanternOrange)
                        .disabled(isSaving)
                }
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
                        .foregroundStyle(SunnyColors.nightIndigo)
                        .multilineTextAlignment(.trailing)
                        .tint(SunnyColors.leafFresh)
                        .colorScheme(.light)
                }
                .padding(.horizontal, 20)
                .frame(height: 56)

                if showLabelHint {
                    Text(LocalizedStringKey("alarm_label_hint"))
                        .font(.system(size: 12))
                        .foregroundStyle(SunnyColors.leafFresh.opacity(0.85))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
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
                    Spacer()
                    HStack(spacing: 6) {
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
                        .font(.system(size: 12))
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
                        Label("啟用口令關閉", systemImage: "mic.badge.checkmark")
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
            guard !tempAlarm.recordingName.isEmpty else { return }
            let u = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Recordings")
                .appendingPathComponent(tempAlarm.recordingName + ".m4a")
            url = FileManager.default.fileExists(atPath: u.path) ? u : nil
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
            RingtonePickerSheet(currentFileName: tempAlarm.soundFileName, mode: .custom) { chosenSoundFile, chosenRecording in
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
                    .font(.system(size: 26))
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
                    .font(.system(size: 18))
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

        if !isEditing {
            modelContext.insert(tempAlarm)
        }
        // (Edit mode: tempAlarm IS the existing @Model object — SwiftData tracks changes automatically)

        Task {
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
                .font(.system(size: 11, weight: .semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(isSelected ? .white : SunnyColors.sunnyGray)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(isSelected ? selectedFill : SunnyColors.sunnyGray.opacity(0.12))
                )
        }
        .ghibliButtonStyle()
    }
}

#Preview("Create") {
    AlarmEditorView()
        .modelContainer(for: Alarm.self, inMemory: true)
}
