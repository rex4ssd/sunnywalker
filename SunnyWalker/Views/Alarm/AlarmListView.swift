// SunnyWalker — AlarmListView.swift  |  Day 25  |  swipe-to-delete + edit mode

import SwiftUI
import SwiftData
import UserNotifications

// Lightweight value type for empty-state ghost cards — avoids constructing @Model without a ModelContext
private struct SampleAlarmData: Identifiable {
    let id: Int
    let label: String
    let hour: Int
    let minute: Int
    var isEnabled: Bool = true

    var timeString: String { String(format: "%02d:%02d", hour, minute) }
}

private let sampleAlarmData: [SampleAlarmData] = [
    SampleAlarmData(id: 0, label: "上學囉", hour: 7, minute: 30),
    SampleAlarmData(id: 1, label: "午睡起床", hour: 13, minute: 0, isEnabled: false)
]

// MARK: - AlarmListView

struct AlarmListView: View {
    let alarms: [Alarm]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if alarms.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(alarms) { alarm in
                        AlarmCard(alarm: alarm, onDelete: { deleteAlarm(alarm) })
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
    }

    // MARK: - Delete

    private func deleteAlarm(_ alarm: Alarm) {
        // Cancel from AlarmKit and v1 scheduler
        Task {
            try? await AlarmKitService.shared.removeAlarm(alarm)
            let id = alarm.id
            let staleIDs = (1...7).map { "\(id.uuidString)-\($0)" } + [id.uuidString]
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: staleIDs)
        }
        modelContext.delete(alarm)
    }

    // Empty state: message + ghost sample cards so the layout reads naturally
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("🌿")
                        .font(.system(size: 56))
                    Text("還沒有鬧鐘")
                        .font(GhibliFonts.title(22))
                        .foregroundStyle(GhibliColors.nightIndigo)
                    Text("點右下角的 + 來新增第一個吧！")
                        .font(GhibliFonts.caption())
                        .foregroundStyle(GhibliColors.totoroGray)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)

                LazyVStack(spacing: 12) {
                    ForEach(sampleAlarmData) { data in
                        SampleAlarmCard(data: data)
                    }
                }
                .padding(.horizontal, 20)
                .opacity(0.4)
            }
            .padding(.bottom, 100)
        }
    }
}

// MARK: - AlarmCard (interactive, wrapped in WatercolorCard)

private struct AlarmCard: View {
    @Bindable var alarm: Alarm
    var onDelete: () -> Void = {}
    @State private var showingRecording = false
    @State private var showingEditor = false

    var body: some View {
        WatercolorCard {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(alarm.timeString)
                        .font(GhibliFonts.clock(40))
                        .foregroundStyle(
                            alarm.isEnabled ? GhibliColors.nightIndigo : GhibliColors.totoroGray
                        )
                    HStack(spacing: 4) {
                        Text(alarm.label)
                            .font(GhibliFonts.caption())
                            .foregroundStyle(GhibliColors.totoroGray)
                        if !alarm.weekdays.isEmpty {
                            Text("·")
                                .foregroundStyle(GhibliColors.totoroGray.opacity(0.5))
                            Text(alarm.weekdaySymbols.joined(separator: " "))
                                .font(GhibliFonts.caption(14))
                                .foregroundStyle(GhibliColors.totoroGray.opacity(0.8))
                        }
                    }
                }
                Spacer()
                Button {
                    showingRecording = true
                } label: {
                    Image(systemName: alarm.recordingName.isEmpty ? "mic" : "mic.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(alarm.recordingName.isEmpty
                            ? GhibliColors.totoroGray.opacity(0.6)
                            : GhibliColors.leafFresh)
                }
                .padding(.trailing, 14)
                .accessibilityLabel(alarm.recordingName.isEmpty ? "錄製起床音" : "已錄製起床音")
                Toggle("", isOn: $alarm.isEnabled)
                    .tint(GhibliColors.leafFresh)
                    .labelsHidden()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .opacity(alarm.isEnabled ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.2), value: alarm.isEnabled)
        .onChange(of: alarm.isEnabled) { _, _ in
            Task {
                // v1 path — keep until AlarmKit device-verified
                try? await AlarmScheduler.shared.syncWithModel(alarm: alarm)
                // v2 path — sync or remove from AlarmKit
                try? await AlarmKitService.shared.syncAlarm(alarm)
            }
        }
        .sheet(isPresented: $showingRecording) {
            RecordingView(alarm: alarm)
        }
        .sheet(isPresented: $showingEditor) {
            AlarmEditorView(existingAlarm: alarm)
        }
        .contextMenu {
            Button {
                showingEditor = true
            } label: {
                Label("編輯鬧鐘", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("刪除鬧鐘", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("刪除", systemImage: "trash")
            }
            Button {
                showingEditor = true
            } label: {
                Label("編輯", systemImage: "pencil")
            }
            .tint(GhibliColors.forestDeep)
        }
    }
}

// MARK: - SampleAlarmCard (display-only, struct-based, no @Model)

private struct SampleAlarmCard: View {
    let data: SampleAlarmData

    var body: some View {
        WatercolorCard {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(data.timeString)
                        .font(GhibliFonts.clock(40))
                        .foregroundStyle(GhibliColors.nightIndigo)
                    Text(data.label)
                        .font(GhibliFonts.caption())
                        .foregroundStyle(GhibliColors.totoroGray)
                }
                Spacer()
                Toggle("", isOn: .constant(data.isEnabled))
                    .tint(GhibliColors.leafFresh)
                    .labelsHidden()
                    .disabled(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }
}

#Preview("With alarms") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Alarm.self, configurations: config)
    let sample = Alarm(label: "上學囉", hour: 7, minute: 30)
    let sample2 = Alarm(label: "午睡起床", hour: 13, minute: 0)
    sample2.isEnabled = false
    return AlarmListView(alarms: [sample, sample2])
        .modelContainer(container)
        .background(GhibliColors.skyBlue)
}

#Preview("Empty state") {
    AlarmListView(alarms: [])
        .modelContainer(for: Alarm.self, inMemory: true)
        .background(GhibliColors.skyBlue)
}
