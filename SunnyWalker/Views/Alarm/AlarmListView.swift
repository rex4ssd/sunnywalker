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
            // List (not ScrollView+LazyVStack) so .swipeActions works natively.
            List {
                ForEach(alarms) { alarm in
                    AlarmCard(alarm: alarm, onDelete: { deleteAlarm(alarm) })
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                }
                // Spacer row so FAB doesn't cover the last card
                Color.clear.frame(height: 80)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init())
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
                        .font(SunnyFonts.title(22))
                        .foregroundStyle(SunnyColors.nightIndigo)
                    Text("點右下角的 + 來新增第一個吧！")
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.sunnyGray)
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
    @State private var showingEditor = false
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        WatercolorCard {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(alarm.formattedTime(use24h: settings.use24HourClock))
                        .font(SunnyFonts.clock(40))
                        .foregroundStyle(
                            alarm.isEnabled ? SunnyColors.nightIndigo : SunnyColors.sunnyGray
                        )
                    HStack(spacing: 4) {
                        // Known default/common names localize; custom parent names show as typed.
                        Text(LocalizedStringKey(alarm.label))
                            .font(SunnyFonts.caption())
                            .foregroundStyle(SunnyColors.sunnyGray)
                        if !alarm.weekdays.isEmpty {
                            Text("·")
                                .foregroundStyle(SunnyColors.sunnyGray.opacity(0.5))
                            Text(alarm.weekdaySymbols.joined(separator: " "))
                                .font(SunnyFonts.caption(14))
                                .foregroundStyle(SunnyColors.sunnyGray.opacity(0.8))
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { showingEditor = true }   // tap time/label → edit alarm
                Spacer()
                Toggle("", isOn: $alarm.isEnabled)
                    .tint(SunnyColors.leafFresh)
                    .labelsHidden()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .opacity(alarm.isEnabled ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.2), value: alarm.isEnabled)
        .onChange(of: alarm.isEnabled) { _, _ in
            Task {
                // UNNotification fallback (no-op while AlarmKit is authorized — it stands down).
                try? await AlarmScheduler.shared.syncWithModel(alarm: alarm)
            }
            // AlarmKit is NOT armed here on purpose: it is managed centrally by HomeView's
            // foreground/background switch (enterForegroundAlarmMode / enterBackgroundAlarmMode),
            // which re-arms from the current model whenever the app leaves the foreground. Arming
            // here would put a system alarm back while the app is on-screen → banner + voice-stop
            // breaks. The toggle just updates the SwiftData model.
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            // Re-sync after editing in case saveAlarm() had a timing issue.
            // This guarantees the UNNotification always reflects the latest time/weekdays.
            Task { try? await AlarmScheduler.shared.syncWithModel(alarm: alarm) }
        }) {
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
            .tint(SunnyColors.forestDeep)
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
                        .font(SunnyFonts.clock(40))
                        .foregroundStyle(SunnyColors.nightIndigo)
                    Text(LocalizedStringKey(data.label))
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.sunnyGray)
                }
                Spacer()
                Toggle("", isOn: .constant(data.isEnabled))
                    .tint(SunnyColors.leafFresh)
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
        .background(SunnyColors.skyBlue)
}

#Preview("Empty state") {
    AlarmListView(alarms: [])
        .modelContainer(for: Alarm.self, inMemory: true)
        .background(SunnyColors.skyBlue)
}
