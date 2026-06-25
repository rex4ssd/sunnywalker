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
    /// Optional scrolling header. iPhone passes clock + mascot so the whole home page scrolls as
    /// ONE continuous strip (like the built-in Clock app) instead of clock/mascot being pinned and
    /// only the list scrolling. nil on iPad's side-by-side layout (clock/mascot live in their own column).
    var header: AnyView? = nil
    /// 多人鬧鐘：該群組被首頁橫幅關閉時為 true → 把鬧鐘卡片變灰、不可點（header 不受影響，仍可點橫幅開回）。
    var dimmed: Bool = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if alarms.isEmpty {
            // Empty state still scrolls, with the header (clock+mascot) on top.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    if let header { header }
                    emptyStateContent
                        .grayscale(dimmed ? 1 : 0)
                        .opacity(dimmed ? 0.5 : 1)
                }
            }
        } else {
            // Single List: header row (clock+mascot) + alarm cards scroll together as one long strip.
            // List (not ScrollView+LazyVStack) so .swipeActions works natively.
            List {
                if let header {
                    header
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
                ForEach(alarms) { alarm in
                    AlarmCard(alarm: alarm, onDelete: { deleteAlarm(alarm) })
                        .grayscale(dimmed ? 1 : 0)
                        .opacity(dimmed ? 0.5 : 1)
                        .allowsHitTesting(!dimmed)   // 關閉的群組：卡片不可點/不可滑（要先點橫幅開回）
                        .animation(.easeInOut(duration: 0.2), value: dimmed)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)   // 像 iPhone 內建鬧鐘：一條長清單、不顯示 scroll bar
            // 底部 FAB（語言/設定/新增）浮在清單之上（是 ZStack 的 sibling，不在 List 內）。
            // 用 safeAreaInset 在清單底保留空間，捲到底時最後一張卡落在 FAB 上方。
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 120)
            }
        }
    }

    // MARK: - Delete

    private func deleteAlarm(_ alarm: Alarm) {
        // Cancel from AlarmKit and v1 scheduler
        Task {
            try? AlarmKitService.shared.removeAlarm(alarm)
            let id = alarm.id
            let staleIDs = (1...7).map { "\(id.uuidString)-\($0)" } + [id.uuidString]
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: staleIDs)
        }
        modelContext.delete(alarm)
    }

    // Empty state: message + ghost sample cards so the layout reads naturally.
    // No own ScrollView — body wraps it (with the header) in a single ScrollView.
    private var emptyStateContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("🌿")
                    .font(.system(size: 56))
                Text("還沒有鬧鐘")
                    .font(SunnyFonts.title(22))
                    .foregroundStyle(SunnyColors.nightIndigo)
                Text("點下方的 ＋ 來新增第一個吧！")
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

// MARK: - AlarmCard (interactive, wrapped in WatercolorCard)

private struct AlarmCard: View {
    @Bindable var alarm: Alarm
    var onDelete: () -> Void = {}
    @State private var showingEditor = false
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        WatercolorCard {
            HStack(alignment: .center, spacing: 0) {
                Button {
                    showingEditor = true
                } label: {
                    HStack(spacing: 12) {
                        DaytimeAlarmIcon(scene: DaytimeScene.current(hour: alarm.hour))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(alarm.formattedTime(use24h: settings.use24HourClock))
                                .font(SunnyFonts.clock(30))
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
                        Spacer()
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("編輯鬧鐘"))   // Text(LocalizedStringKey) → VoiceOver 跟著語言；純 String 是 verbatim

                Toggle("", isOn: $alarm.isEnabled)
                    .tint(SunnyColors.leafFresh)
                    .labelsHidden()
                    .accessibilityLabel(Text(alarm.isEnabled ? "關閉鬧鐘" : "開啟鬧鐘"))
                    .padding(.trailing, 20)
                    .padding(.vertical, 10)
            }
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

// MARK: - Time-of-day story icon

private struct DaytimeAlarmIcon: View {
    let scene: DaytimeScene

    var body: some View {
        ZStack {
            Circle()
                .fill(iconColor.opacity(0.14))
                .frame(width: 40, height: 40)

            switch scene {
            case .dawn, .morning:
                Image(systemName: "sunrise.fill")
                    .foregroundStyle(SunnyColors.lanternOrange, SunnyColors.wheatGold)
            case .noon:
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(SunnyColors.wheatGold)
            case .dusk:
                Image(systemName: "lamp.desk.fill")
                    .foregroundStyle(SunnyColors.lanternOrange)
            case .night:
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(SunnyColors.nightIndigo, SunnyColors.starGold)
            }
        }
        .font(.title3.weight(.medium))
        .accessibilityHidden(true)
    }

    private var iconColor: Color {
        scene == .night ? SunnyColors.nightIndigo : SunnyColors.lanternOrange
    }
}

// MARK: - SampleAlarmCard (display-only, struct-based, no @Model)

private struct SampleAlarmCard: View {
    let data: SampleAlarmData

    var body: some View {
        WatercolorCard {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(data.timeString)
                        .font(SunnyFonts.clock(30))
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
            .padding(.vertical, 10)
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
