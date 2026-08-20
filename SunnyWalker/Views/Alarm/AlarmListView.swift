// SunnyWalker — AlarmListView.swift  |  Day 25  |  swipe-to-delete + edit mode

import SwiftUI
import SwiftData
import UserNotifications
import Combine

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

// MARK: - 長按試聽（整份清單共用一個播放器）

/// 首頁長按鬧鐘左側圖示＝試聽這顆鬧鐘的聲音。整份清單共用一個播放器，
/// 所以同時只會有一顆在響（再長按別顆＝換播那顆）。
@MainActor
final class AlarmPreviewPlayer: ObservableObject {
    /// 正在試聽的鬧鐘 id；nil = 沒有在播。
    @Published private(set) var playingID: UUID?

    private let player = AudioPlayer()
    private var cancellable: AnyCancellable?

    init() {
        // 播完（非 loop）→ 自己把高亮收掉。
        cancellable = player.$isPlaying
            .sink { [weak self] playing in
                if !playing { self?.playingID = nil }
            }
    }

    /// 長按同一顆＝停止；長按別顆＝改播那顆。找不到音檔就不做事（不留半亮狀態）。
    func toggle(_ alarm: Alarm) {
        if playingID == alarm.id {
            stop()
            return
        }
        guard let url = alarm.ringtoneURL else {
            stop()
            return
        }
        // ⚠️ 順序不能反：AudioPlayer.play() 內部第一件事就是 stop()，那會同步把 $isPlaying 打成
        //    false、觸發上面的 sink 把 playingID 清掉。先標記再播 → 播放中圖示不會亮
        //    （模擬器實測過：聲音有出來、圖示卻沒變）。所以「先播、再依實際結果標記」。
        //    編輯器的 previewChime 也踩過同一個雷，那邊的註解寫的是同一件事。
        // loop: false —— 試聽只播一次；要聽循環請進鬧鐘編輯器。
        player.play(url: url, loop: false)
        playingID = player.isPlaying ? alarm.id : nil
    }

    func stop() {
        player.stop()
        playingID = nil
    }
}

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
    /// 長按左側圖示試聽——整份清單共用一個播放器（見 AlarmPreviewPlayer）。
    @StateObject private var previewPlayer = AlarmPreviewPlayer()

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
                    AlarmCard(alarm: alarm, onDelete: { deleteAlarm(alarm) }, preview: previewPlayer)
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
            // 切群組／離開首頁時別讓試聽在背景繼續響。
            .onDisappear { previewPlayer.stop() }
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
    /// 整份清單共用的試聽播放器（長按左側圖示）。
    @ObservedObject var preview: AlarmPreviewPlayer
    @State private var showingEditor = false
    @ObservedObject private var settings = AppSettings.shared

    private var isPreviewing: Bool { preview.playingID == alarm.id }

    var body: some View {
        WatercolorCard {
            HStack(alignment: .center, spacing: 0) {
                // 左側圖示自成一個熱區：點＝編輯（與卡片其他地方一致），長按＝試聽這顆鬧鐘的聲音。
                // 它刻意【不】包在下面那顆編輯 Button 裡——Button 會把長按吃掉；
                // 卡片的 contextMenu 也改掛在編輯 Button 上，免得長按圖示同時彈出選單。
                DaytimeAlarmIcon(
                    scene: DaytimeScene.current(hour: alarm.hour),
                    isPlaying: isPreviewing
                )
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture { showingEditor = true }
                // highPriority：List 會把 cell 內的 contextMenu 提升成「整列長按」，
                // 普通的 onLongPressGesture 會被它吃掉（實機驗證過：長按圖示只會彈選單）。
                // 高優先權手勢先辨識成功，長按圖示才會是「試聽」而不是彈選單。
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.4)
                        .onEnded { _ in
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            preview.toggle(alarm)
                        }
                )
                .accessibilityElement()
                .accessibilityLabel(Text(alarm.hasCustomVoice
                                         ? LocalizedStringKey("試聽這顆鬧鐘的錄音")
                                         : LocalizedStringKey("試聽這顆鬧鐘的鈴聲")))
                .accessibilityHint(Text(LocalizedStringKey("點兩下編輯鬧鐘，長按試聽")))
                .accessibilityAddTraits(isPreviewing ? [.isButton, .startsMediaSession] : .isButton)

                Button {
                    showingEditor = true
                } label: {
                    HStack(spacing: 12) {
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
                    .padding(.trailing, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("編輯鬧鐘"))   // Text(LocalizedStringKey) → VoiceOver 跟著語言；純 String 是 verbatim
                // 這裡刻意【沒有】contextMenu。List 會把 cell 內任何 contextMenu 提升成「整列長按」，
                // 跟圖示的長按試聽搶同一個手勢——模擬器實測：第一次長按試聽成功、第二次卻彈出選單，
                // 時好時壞（UIKit 的 context-menu interaction 與 SwiftUI 手勢的競態）。
                // 編輯／刪除已經有右滑（swipeActions）與點按卡片兩條路，所以拿掉選單換一個穩定的長按。

                Toggle("", isOn: $alarm.isEnabled)
                    .tint(SunnyColors.leafFresh)
                    .labelsHidden()
                    // 明確標 LocalizedStringKey：兩個字面值的三元運算可能被推成 Text(String)（verbatim、
                    // 不在地化）——那會悄悄讓這條 VoiceOver 修正失效。寫死 LocalizedStringKey 保證在地化。
                    .accessibilityLabel(Text(alarm.isEnabled
                                             ? LocalizedStringKey("關閉鬧鐘")
                                             : LocalizedStringKey("開啟鬧鐘")))
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
    /// true = 這顆鬧鐘正在被長按試聽 → 圖示換成喇叭並脈動，讓家長知道聲音來自哪一顆。
    var isPlaying: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill((isPlaying ? SunnyColors.lanternOrange : iconColor).opacity(isPlaying ? 0.24 : 0.14))
                .frame(width: 40, height: 40)

            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(SunnyColors.lanternOrange)
                    .symbolEffect(.pulse, isActive: true)
            } else {
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
        }
        .font(.title3.weight(.medium))
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
        // 卡片自己標了 accessibilityLabel／hint（長按試聽），圖示不再另外發聲。
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
