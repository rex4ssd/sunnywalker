// SunnyWalker — AlarmEditorView.swift  |  Day 24  |  edit mode support

import SwiftUI
import SwiftData

struct AlarmEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Pass an existing alarm to enter edit mode; nil = create mode.
    var existingAlarm: Alarm? = nil

    private var isEditing: Bool { existingAlarm != nil }

    // tempAlarm: stable UUID in create mode so RecordingView writes to correct path.
    // In edit mode we work directly on existingAlarm via state copies below.
    @State private var tempAlarm: Alarm

    @State private var selectedTime = Date()
    @State private var label = "起床囉"
    @State private var selectedWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var selectedTaskType: AlarmTaskType = .voice
    @State private var requireAppToStop = false
    @State private var isSaving = false
    @State private var showingRecording = false

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
            _selectedTaskType = State(initialValue: a.effectiveTaskType)
            _requireAppToStop = State(initialValue: a.effectiveRequireAppToStop)
        } else {
            // Create mode
            _tempAlarm = State(initialValue: Alarm(label: "起床囉", hour: 7, minute: 0))
            _selectedTime     = State(initialValue: Date())
            _label            = State(initialValue: "起床囉")
            _selectedWeekdays = State(initialValue: [2, 3, 4, 5, 6])
            _selectedTaskType = State(initialValue: .voice)
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
                        taskTypePicker
                        if selectedTaskType == .voice {
                            recordingRow
                        }
                        strictModeRow
                        saveButton
                    }
                    .padding(24)
                }
            }
            .navigationTitle(isEditing ? "編輯鬧鐘" : "新增鬧鐘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.sunnyGray)
                }
            }
        }
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
        }
    }

    private var labelField: some View {
        WatercolorCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("鬧鐘名稱")
                    .font(SunnyFonts.caption())
                    .foregroundStyle(SunnyColors.sunnyGray)
                TextField("例如：上學囉！", text: $label)
                    .font(SunnyFonts.body())
                    .foregroundStyle(SunnyColors.nightIndigo)
                    .tint(SunnyColors.leafFresh)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var weekdayPicker: some View {
        WatercolorCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("重複日")
                    .font(SunnyFonts.caption())
                    .foregroundStyle(SunnyColors.sunnyGray)
                HStack(spacing: 8) {
                    ForEach(weekdayLabels, id: \.0) { num, sym in
                        WeekdayChip(symbol: sym, isSelected: selectedWeekdays.contains(num)) {
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
            .padding(.vertical, 16)
        }
    }

    private var taskTypePicker: some View {
        WatercolorCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("關鬧鐘方式")
                    .font(SunnyFonts.caption())
                    .foregroundStyle(SunnyColors.sunnyGray)
                Picker("", selection: $selectedTaskType) {
                    Label("說話關 🎤", systemImage: "mic.fill").tag(AlarmTaskType.voice)
                    Label("按鈕關 👆", systemImage: "hand.tap.fill").tag(AlarmTaskType.button)
                }
                .pickerStyle(.segmented)
                Text(selectedTaskType == .voice
                     ? LocalizedStringKey("小朋友說出喚醒語才能關掉鬧鐘")
                     : LocalizedStringKey("小朋友按按鈕就能關掉鬧鐘，適合年幼寶寶"))
                    .font(SunnyFonts.caption(13))
                    .foregroundStyle(SunnyColors.sunnyGray.opacity(0.8))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var recordingRow: some View {
        WatercolorCard {
            Button { showingRecording = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: tempAlarm.recordingName.isEmpty ? "mic" : "mic.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(
                            tempAlarm.recordingName.isEmpty
                                ? SunnyColors.sunnyGray.opacity(0.6)
                                : SunnyColors.leafFresh
                        )
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("錄音喚醒語")
                            .font(SunnyFonts.caption())
                            .foregroundStyle(SunnyColors.nightIndigo)
                        Text(tempAlarm.recordingName.isEmpty ? LocalizedStringKey("尚未錄音") : LocalizedStringKey("已錄音 ✅"))
                            .font(SunnyFonts.caption(14))
                            .foregroundStyle(
                                tempAlarm.recordingName.isEmpty
                                    ? SunnyColors.sunnyGray
                                    : SunnyColors.forestDeep
                            )
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SunnyColors.sunnyGray.opacity(0.5))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showingRecording) {
            RecordingView(alarm: tempAlarm)
        }
    }

    private var strictModeRow: some View {
        WatercolorCard {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $requireAppToStop) {
                    Label("貪睡模式", systemImage: requireAppToStop ? "bed.double.fill" : "bed.double")
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.nightIndigo)
                }
                .tint(SunnyColors.lanternOrange)
                Text(requireAppToStop
                     ? LocalizedStringKey("打勾：一定要打開 App 完成起床任務才能關，關掉通知也會一直響回來")
                     : LocalizedStringKey("不打勾：在通知上按 ✕ 就能關掉鬧鐘"))
                    .font(SunnyFonts.caption(13))
                    .foregroundStyle(SunnyColors.sunnyGray.opacity(0.8))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var saveButton: some View {
        SunnyButton(isEditing ? "儲存修改" : "儲存鬧鐘", color: SunnyColors.lanternOrange) {
            saveAlarm()
        }
        .disabled(isSaving)
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
        tempAlarm.taskType = selectedTaskType
        tempAlarm.requireAppToStop = requireAppToStop

        if !isEditing {
            modelContext.insert(tempAlarm)
        }
        // (Edit mode: tempAlarm IS the existing @Model object — SwiftData tracks changes automatically)

        Task {
            try? await AlarmScheduler.shared.schedule(alarm: tempAlarm)
            try? await AlarmKitService.shared.syncAlarm(tempAlarm)
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
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(LocalizedStringKey(symbol))
                .font(SunnyFonts.caption(14))
                .foregroundStyle(isSelected ? .white : SunnyColors.sunnyGray)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isSelected ? SunnyColors.leafFresh : SunnyColors.sunnyGray.opacity(0.12))
                )
        }
        .ghibliButtonStyle()
    }
}

#Preview("Create") {
    AlarmEditorView()
        .modelContainer(for: Alarm.self, inMemory: true)
}
