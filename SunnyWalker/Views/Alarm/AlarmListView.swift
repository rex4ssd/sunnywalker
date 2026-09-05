// SunnyWalker — AlarmListView.swift  |  首頁鬧鐘清單（一般 / 報時 / 待辦三種卡片，三種排列）
//
// 2026-09-03 整理（Rex：「大人會設一堆鬧鐘，怎麼整理比較美、清楚不會亂」）：
//   • 卡片左側圖示改成「種類」：鬧鐘（時段太陽／月亮）、報時（喇叭泡泡，橘）、待辦（家長挑的 emoji）——
//     以前三種長得一模一樣，十顆排下來分不出哪顆會響、哪顆只是主頁冒圖示。
//   • 區間報時顯示「07:00–07:30 · 每 5 分」，不是只有起時刻。
//   • 星期改成「每天／平日／週末」縮寫，其餘才用 7 顆小圓點（選中亮、沒選淡）——一眼看得出哪天響。
//   • 「下一個」：今天接下來最先響的那顆加一條橘色標籤，孩子睡前家長掃一眼就知道明早哪顆先響。
//   • 排列三選一（設定 › 首頁清單）：依時間（原本）／依時段（早上・上午・下午・晚上）／依星期。
//     「依時段」是給設很多鬧鐘的家庭的：起床、出門、放學、睡前天然各一區，不會像依星期那樣一顆重複七次。

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

// MARK: - 時段（依時段排列用）

/// 首頁「依時段」分節：早上 05–08、上午 09–11、下午 12–17、晚上 18–04。
/// 跟 DaytimeScene（畫面天色）刻意分開：天色是給孩子看氣氛的，這裡是給大人整理鬧鐘的。
enum AlarmDaypart: Int, CaseIterable {
    case morning, forenoon, afternoon, evening

    static func of(hour: Int) -> AlarmDaypart {
        switch hour {
        case 5...8:   return .morning
        case 9...11:  return .forenoon
        case 12...17: return .afternoon
        default:      return .evening
        }
    }

    var titleKey: String {
        switch self {
        case .morning:   return "daypart_morning"
        case .forenoon:  return "daypart_forenoon"
        case .afternoon: return "daypart_afternoon"
        case .evening:   return "daypart_evening"
        }
    }

    var systemImage: String {
        switch self {
        case .morning:   return "sunrise.fill"
        case .forenoon:  return "sun.max.fill"
        case .afternoon: return "sun.haze.fill"
        case .evening:   return "moon.stars.fill"
        }
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
    /// 排列方式（設定 › 首頁清單）。
    var layout: HomeListLayout = .time
    @Environment(\.modelContext) private var modelContext
    /// 長按左側圖示試聽——整份清單共用一個播放器（見 AlarmPreviewPlayer）。
    @StateObject private var previewPlayer = AlarmPreviewPlayer()

    /// 已被 modelContext.delete 但 @Query 還沒刷新的物件不能再碰（SwiftData 對已刪物件取值會炸）。
    private var liveAlarms: [Alarm] { alarms.filter { !$0.isDeleted } }

    var body: some View {
        if liveAlarms.isEmpty {
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
            let nextID = Self.nextUpcomingAlarmID(in: liveAlarms, now: Date())
            // Single List: header row (clock+mascot) + alarm cards scroll together as one long strip.
            // List (not ScrollView+LazyVStack) so .swipeActions works natively.
            List {
                if let header {
                    header
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
                switch layout {
                case .time:
                    ForEach(liveAlarms) { alarm in alarmRow(alarm, isNext: alarm.id == nextID) }
                case .daypart:
                    ForEach(daypartSections, id: \.part) { section in
                        Section {
                            ForEach(section.alarms) { alarm in alarmRow(alarm, isNext: alarm.id == nextID) }
                        } header: {
                            sectionHeader(Text(LocalizedStringKey(section.part.titleKey)),
                                          systemImage: section.part.systemImage)
                        }
                    }
                case .weekday:
                    ForEach(weekdaySections, id: \.title) { section in
                        Section {
                            ForEach(section.alarms) { alarm in alarmRow(alarm, isNext: alarm.id == nextID) }
                        } header: {
                            sectionHeader(Text(LocalizedStringKey(section.title)), systemImage: nil)
                        }
                    }
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

    /// 一列鬧鐘卡（三種排列共用同一組 row modifiers）。
    private func alarmRow(_ alarm: Alarm, isNext: Bool) -> some View {
        AlarmCard(alarm: alarm, isNext: isNext, onDelete: { deleteAlarm(alarm) }, preview: previewPlayer)
            .grayscale(dimmed ? 1 : 0)
            .opacity(dimmed ? 0.5 : 1)
            .allowsHitTesting(!dimmed)   // 關閉的群組：卡片不可點/不可滑（要先點橫幅開回）
            .animation(.easeInOut(duration: 0.2), value: dimmed)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
    }

    private func sectionHeader(_ title: Text, systemImage: String?) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption)
            }
            title.font(SunnyFonts.caption(15))
        }
        .foregroundStyle(SunnyColors.cloudWhite.opacity(0.92))
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .listRowInsets(EdgeInsets(top: 10, leading: 28, bottom: 2, trailing: 20))
    }

    // MARK: - 「下一個」

    /// 今天接下來最先響的那顆（只算會響的：一般鬧鐘與報時；待辦不響不算）。
    /// 今天沒有剩下的 → nil（不硬標明天的，避免「下一個」跟畫面上的星期矛盾）。
    static func nextUpcomingAlarmID(in alarms: [Alarm], now: Date) -> UUID? {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute, .weekday], from: now)
        guard let h = c.hour, let m = c.minute, let wd = c.weekday else { return nil }
        let nowMin = h * 60 + m
        return alarms
            .filter { $0.isEnabled && !$0.isTodo
                && ($0.weekdays.isEmpty || $0.weekdays.contains(wd))
                && ($0.hour * 60 + $0.minute) > nowMin }
            .min { ($0.hour * 60 + $0.minute) < ($1.hour * 60 + $1.minute) }?
            .id
    }

    // MARK: - 依時段分組

    private struct DaypartSection {
        let part: AlarmDaypart
        let alarms: [Alarm]
    }

    /// 早上 → 上午 → 下午 → 晚上；沒有鬧鐘的節直接不出現。alarms 已依 (hour, minute) 排序。
    private var daypartSections: [DaypartSection] {
        AlarmDaypart.allCases.compactMap { part in
            let a = liveAlarms.filter { AlarmDaypart.of(hour: $0.hour) == part }
            return a.isEmpty ? nil : DaypartSection(part: part, alarms: a)
        }
    }

    // MARK: - 依星期分組

    private struct WeekdaySection {
        let title: String        // Localizable key（星期一…／單次鬧鐘）
        let alarms: [Alarm]
    }

    /// 週一…週日（台灣習慣週一開頭）＋「單次鬧鐘」殿後；沒有鬧鐘的節直接不出現。
    /// alarms 已由 @Query 依 (hour, minute) 排序，各節內順序自然正確。
    private var weekdaySections: [WeekdaySection] {
        let titles = [1: "星期日", 2: "星期一", 3: "星期二", 4: "星期三",
                      5: "星期四", 6: "星期五", 7: "星期六"]
        var sections: [WeekdaySection] = [2, 3, 4, 5, 6, 7, 1].compactMap { day in
            let dayAlarms = liveAlarms.filter { $0.weekdays.contains(day) }
            return dayAlarms.isEmpty ? nil : WeekdaySection(title: titles[day]!, alarms: dayAlarms)
        }
        let oneShots = liveAlarms.filter { $0.weekdays.isEmpty }
        if !oneShots.isEmpty {
            sections.append(WeekdaySection(title: "單次鬧鐘", alarms: oneShots))
        }
        return sections
    }

    // MARK: - Delete

    private func deleteAlarm(_ alarm: Alarm) {
        let id = alarm.id
        let chimeFiles = (alarm.chimeSlotSoundFiles ?? []) + [alarm.soundFileName]
        // Cancel from AlarmKit and the UNNotification path. 以前只清 baseline 7 顆——
        // 切段堆疊 / 報時連報的一次性通知會留在系統裡照響（鬧鐘已不在清單上卻還在響）。
        Task {
            try? AlarmKitService.shared.removeAlarm(alarm)
            AlarmScheduler.shared.cancel(id)
            for f in chimeFiles { ChimeSoundComposer.removeChimeFile(named: f) }
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
    /// 今天接下來最先響的那顆 → 加「下一個」標籤與橘框。
    var isNext: Bool = false
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
                // 它刻意【不】包在下面那顆編輯 Button 裡——Button 會把長按整個吃掉。
                AlarmKindIcon(alarm: alarm, isPlaying: isPreviewing)
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture { showingEditor = true }
                // highPriority：確保這個長按贏過 List cell 自己的手勢處理。
                // （這張卡片刻意沒有 contextMenu——原因見下方編輯按鈕處的註解。）
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
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(isPreviewing ? Text(LocalizedStringKey("播放中")) : Text(""))
                // VoiceOver 打不出「長按」——它的雙擊會被當成一般點按（＝開編輯頁），
                // 所以試聽一定要另外掛成自訂動作，否則旁白使用者根本用不到這個功能。
                .accessibilityAction(named: Text(LocalizedStringKey("試聽聲音"))) {
                    preview.toggle(alarm)
                }

                Button {
                    showingEditor = true
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            timeLine
                            HStack(spacing: 6) {
                                // Known default/common names localize; custom parent names show as typed.
                                Text(LocalizedStringKey(alarm.label))
                                    .font(SunnyFonts.caption())
                                    .foregroundStyle(SunnyColors.sunnyGray)
                                    .lineLimit(1)
                                WeekdayDots(weekdays: alarm.weekdays)
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
        // 「下一個」：橘色細框 + 右上角小標籤。只是提示，不改變卡片其他排版。
        .overlay {
            if isNext && alarm.isEnabled {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(SunnyColors.lanternOrange.opacity(0.75), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isNext && alarm.isEnabled {
                Text("alarm_next_badge")
                    .font(SunnyFonts.caption(11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(SunnyColors.lanternOrange))
                    .offset(x: -14, y: -7)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .opacity(alarm.isEnabled ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.2), value: alarm.isEnabled)
        .animation(.easeInOut(duration: 0.2), value: isNext)
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

    /// 時間那一行：一般＝大字時刻；區間報時＝「07:00–07:30」+「每 5 分」小標；待辦＝時刻 + 圖示 emoji。
    @ViewBuilder
    private var timeLine: some View {
        let color = alarm.isEnabled ? SunnyColors.nightIndigo : SunnyColors.sunnyGray
        if alarm.kind == .chime, alarm.isIntervalChime {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(alarm.formattedChimeRange(use24h: settings.use24HourClock))
                    .font(SunnyFonts.clock(24))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(L("chime_every_minutes %lld", alarm.chimeIntervalMinutes ?? 0))
                    .font(SunnyFonts.caption(12))
                    .foregroundStyle(SunnyColors.lanternOrange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(SunnyColors.lanternOrange.opacity(0.14)))
            }
        } else {
            Text(alarm.formattedTime(use24h: settings.use24HourClock))
                .font(SunnyFonts.clock(30))
                .foregroundStyle(color)
        }
    }
}

// MARK: - 種類圖示（一般：時段太陽／月亮；報時：喇叭泡泡；待辦：家長挑的 emoji）

private struct AlarmKindIcon: View {
    let alarm: Alarm
    /// true = 這顆鬧鐘正在被長按試聽 → 圖示換成喇叭並脈動，讓家長知道聲音來自哪一顆。
    var isPlaying: Bool = false

    private var scene: DaytimeScene { DaytimeScene.current(hour: alarm.hour) }

    var body: some View {
        ZStack {
            Circle()
                .fill((isPlaying ? SunnyColors.lanternOrange : tint).opacity(isPlaying ? 0.24 : 0.14))
                .frame(width: 40, height: 40)

            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(SunnyColors.lanternOrange)
                    .symbolEffect(.pulse, isActive: true)
            } else {
                switch alarm.kind {
                case .todo:
                    Text(alarm.effectiveTodoIcon.emoji)
                        .font(.title3)
                case .chime:
                    Image(systemName: AlarmKind.chime.systemImage)
                        .foregroundStyle(SunnyColors.lanternOrange)
                case .alarm:
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
        }
        .font(.title3.weight(.medium))
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
        // 卡片自己標了 accessibilityLabel／hint（長按試聽），圖示不再另外發聲。
        .accessibilityHidden(true)
    }

    private var tint: Color {
        switch alarm.kind {
        case .todo:  return SunnyColors.leafFresh
        case .chime: return SunnyColors.lanternOrange
        case .alarm: return scene == .night ? SunnyColors.nightIndigo : SunnyColors.lanternOrange
        }
    }
}

// MARK: - 星期（每天／平日／週末縮寫，其餘 7 顆小圓點）

private struct WeekdayDots: View {
    let weekdays: [Int]   // 1=日 … 7=六

    private static let all: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    private static let workdays: Set<Int> = [2, 3, 4, 5, 6]
    private static let weekend: Set<Int> = [1, 7]
    private static let symbols = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        let set = Set(weekdays)
        if set.isEmpty {
            EmptyView()
        } else if set == Self.all {
            shorthand("days_every")
        } else if set == Self.workdays {
            shorthand("days_weekdays")
        } else if set == Self.weekend {
            shorthand("days_weekend")
        } else {
            HStack(spacing: 3) {
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in
                    let on = set.contains(d)
                    Text(LocalizedStringKey(Self.symbols[d - 1]))
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 15, height: 15)
                        .foregroundStyle(on ? .white : SunnyColors.sunnyGray.opacity(0.55))
                        .background(Circle().fill(on ? SunnyColors.leafFresh : SunnyColors.sunnyGray.opacity(0.12)))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: weekdays.sorted().compactMap { d in
                (1...7).contains(d) ? L(Self.symbols[d - 1]) : nil
            }.joined(separator: " ")))
        }
    }

    private func shorthand(_ key: String) -> some View {
        Text(LocalizedStringKey(key))
            .font(SunnyFonts.caption(12))
            .foregroundStyle(SunnyColors.forestDeep)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(SunnyColors.leafFresh.opacity(0.18)))
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
    return AlarmListView(alarms: [sample, sample2], layout: .daypart)
        .modelContainer(container)
        .background(SunnyColors.skyBlue)
}

#Preview("Empty state") {
    AlarmListView(alarms: [])
        .modelContainer(for: Alarm.self, inMemory: true)
        .background(SunnyColors.skyBlue)
}
