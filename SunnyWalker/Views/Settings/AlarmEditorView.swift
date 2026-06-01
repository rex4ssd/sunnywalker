// SunnyWalker — AlarmEditorView.swift  |  Day 17  |  AlarmTaskType picker

import SwiftUI
import SwiftData

struct AlarmEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // tempAlarm carries a stable UUID so RecordingView writes to the right file
    @State private var tempAlarm = Alarm(label: "起床囉", hour: 7, minute: 0)
    @State private var selectedTime = Date()
    @State private var label = "起床囉"
    @State private var selectedWeekdays: Set<Int> = [2, 3, 4, 5, 6]  // Mon–Fri default
    @State private var selectedTaskType: AlarmTaskType = .voice
    @State private var isSaving = false
    @State private var showingRecording = false

    private let weekdayLabels: [(Int, String)] = [
        (1, "日"), (2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                GhibliColors.cloudWhite.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        timePicker
                        labelField
                        weekdayPicker
                        taskTypePicker
                        recordingRow
                        saveButton
                    }
                    .padding(24)
                }
            }
            .navigationTitle("新增鬧鐘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .font(GhibliFonts.caption())
                        .foregroundStyle(GhibliColors.totoroGray)
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
        }
    }

    private var labelField: some View {
        WatercolorCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("鬧鐘名稱")
                    .font(GhibliFonts.caption())
                    .foregroundStyle(GhibliColors.totoroGray)
                TextField("例如：上學囉！", text: $label)
                    .font(GhibliFonts.body())
                    .foregroundStyle(GhibliColors.nightIndigo)
                    .tint(GhibliColors.leafFresh)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var weekdayPicker: some View {
        WatercolorCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("重複日")
                    .font(GhibliFonts.caption())
                    .foregroundStyle(GhibliColors.totoroGray)
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
                    .font(GhibliFonts.caption())
                    .foregroundStyle(GhibliColors.totoroGray)
                Picker("", selection: $selectedTaskType) {
                    Label("說話關 🎤", systemImage: "mic.fill").tag(AlarmTaskType.voice)
                    Label("按鈕關 👆", systemImage: "hand.tap.fill").tag(AlarmTaskType.button)
                }
                .pickerStyle(.segmented)
                Text(selectedTaskType == .voice
                     ? "小朋友說出喚醒語才能關掉鬧鐘"
                     : "小朋友按按鈕就能關掉鬧鐘，適合年幼寶寶")
                    .font(GhibliFonts.caption(13))
                    .foregroundStyle(GhibliColors.totoroGray.opacity(0.8))
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
                                ? GhibliColors.totoroGray.opacity(0.6)
                                : GhibliColors.leafFresh
                        )
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("錄音喚醒語")
                            .font(GhibliFonts.caption())
                            .foregroundStyle(GhibliColors.nightIndigo)
                        Text(tempAlarm.recordingName.isEmpty ? "尚未錄音" : "已錄音 ✅")
                            .font(GhibliFonts.caption(14))
                            .foregroundStyle(
                                tempAlarm.recordingName.isEmpty
                                    ? GhibliColors.totoroGray
                                    : GhibliColors.forestDeep
                            )
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GhibliColors.totoroGray.opacity(0.5))
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

    private var saveButton: some View {
        GhibliButton("儲存鬧鐘", color: GhibliColors.lanternOrange) {
            saveAlarm()
        }
        .disabled(isSaving)
    }

    // MARK: - Save logic

    private func saveAlarm() {
        isSaving = true
        let comps = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        // Reuse tempAlarm so the stable UUID matches any recording already saved to disk
        tempAlarm.label = trimmed.isEmpty ? "起床囉" : trimmed
        tempAlarm.hour = comps.hour ?? 7
        tempAlarm.minute = comps.minute ?? 0
        tempAlarm.weekdays = selectedWeekdays.isEmpty ? [2, 3, 4, 5, 6] : Array(selectedWeekdays).sorted()
        tempAlarm.taskType = selectedTaskType
        modelContext.insert(tempAlarm)
        Task {
            // v1 path (UNUserNotificationCenter) — kept until AlarmKit device test confirms parity
            try? await AlarmScheduler.shared.schedule(alarm: tempAlarm)
            // v2 path (AlarmKit) — upserts; no-ops silently if entitlement not yet approved
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
            Text(symbol)
                .font(GhibliFonts.caption(14))
                .foregroundStyle(isSelected ? .white : GhibliColors.totoroGray)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isSelected ? GhibliColors.leafFresh : GhibliColors.totoroGray.opacity(0.12))
                )
        }
        .ghibliButtonStyle()
    }
}

#Preview {
    AlarmEditorView()
        .modelContainer(for: Alarm.self, inMemory: true)
}
