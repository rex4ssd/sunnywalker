// SunnyWalker — TodoBadgesView.swift  |  待辦語音提醒：主頁吉祥物旁的小圖示
//
// 一個待辦（todo）鬧鐘到了設定時間，就在主頁吉祥物旁冒出家長挑的可愛圖示（氣球/星星…）。
// 互動流程（確認小孩真的有聽到當天的注意事項）：
//   1. 兒童「點一下」圖示 → 播放家長錄的提醒語音。
//   2. 語音「播完」後，圖示出現一個小勾勾，提示可以長按確認。
//   3. 兒童「長按」圖示 → 圖示消失，並寫一筆 TodoPlayRecord（家長在「待辦紀錄」頁看到「已接收」）。
// 也就是說：沒點過、或還沒播完，長按不會消失——確保孩子真的聽完才算「已接收」。
// 設了顯示時長（10/30/60 分）的，時間到也會自動收起（沒確認則不記為已接收）；「直到點開」型則
// 一定要走完上面流程才會消失。
//
// 待辦不會響、不發通知（見 AlarmScheduler / AlarmKitService 的 isTodo guard）——這個 overlay 是
// 它唯一的觸發點，所以只在 App 開著、主頁顯示該群組時出現。

import SwiftUI
import SwiftData

struct TodoBadgesView: View {
    /// 顯示哪一組的待辦（nil = 未分組，視為群組 0）。
    var group: Int?

    @Query private var alarms: [Alarm]
    @Environment(\.modelContext) private var modelContext
    @StateObject private var player = AudioPlayer()
    @State private var now = Date()
    @State private var playingTodoID: UUID?
    /// 今天「已播完」的待辦 id（播完才解鎖長按確認）。App 重開會清空（再點播放即可重新解鎖）。
    @State private var playedThroughToday: Set<UUID> = []
    // 15s 一跳：讓圖示在時間到 / 時長過後 ~15s 內出現或消失（提醒型，不需秒級精準）。
    private let tick = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var groupIndex: Int { group ?? 0 }

    private var activeTodos: [Alarm] {
        alarms
            .filter { $0.isTodo && $0.isEnabled
                && $0.effectiveGroupIndex == groupIndex
                && isWithinWindow($0, now: now) }
            .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(activeTodos) { todo in
                TodoBadge(
                    icon: todo.effectiveTodoIcon,
                    isPlaying: playingTodoID == todo.id,
                    canAcknowledge: playedThroughToday.contains(todo.id),
                    onPlay: { play(todo) },
                    onAcknowledge: { acknowledge(todo) }
                )
            }
        }
        .onReceive(tick) { now = $0 }
        .onAppear { now = Date() }
        .onReceive(player.$isPlaying) { playing in
            // 播放結束（isPlaying 轉 false）→ 把剛才那則標記為「已播完」，解鎖長按確認。
            if !playing, let id = playingTodoID {
                playedThroughToday.insert(id)
                playingTodoID = nil
            }
        }
        .onDisappear { player.stop() }
    }

    // MARK: - Window logic

    /// 今天是否還要顯示這則待辦：今天有排 + 已過設定時刻 + 還沒「已接收」 +（限時型）還沒超過時長。
    private func isWithinWindow(_ todo: Alarm, now: Date) -> Bool {
        let cal = Calendar.current
        let wd = cal.component(.weekday, from: now)
        let firesToday = todo.weekdays.isEmpty || todo.weekdays.contains(wd)
        guard firesToday else { return false }

        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = todo.hour; comps.minute = todo.minute; comps.second = 0
        guard let fire = cal.date(from: comps), now >= fire else { return false }

        // 今天已經確認過（已接收）→ 收起來。
        if hasAcknowledgedToday(todo, now: now) { return false }

        let dur = todo.effectiveTodoDurationMinutes
        if dur == 0 { return true }                 // 直到點開／確認
        return now < fire.addingTimeInterval(Double(dur * 60))
    }

    private func hasAcknowledgedToday(_ todo: Alarm, now: Date) -> Bool {
        let startOfDay = Calendar.current.startOfDay(for: now)
        let id = todo.id
        var fd = FetchDescriptor<TodoPlayRecord>(
            predicate: #Predicate { $0.todoID == id && $0.playedAt >= startOfDay }
        )
        fd.fetchLimit = 1
        return ((try? modelContext.fetch(fd))?.isEmpty == false)
    }

    // MARK: - Play / acknowledge

    /// 兒童點一下 → 播放提醒語音（不消失、不記錄；播完才解鎖長按確認）。
    private func play(_ todo: Alarm) {
        guard AppPaths.recordingExists(named: todo.recordingName) else { return }
        let url = AppPaths.recordingURL(named: todo.recordingName)
        // ⚠️ 順序很重要，否則會「沒聽完就解鎖長按確認」：
        //   player.play() 內部一開始會 stop()（isPlaying→false）。若此時 playingTodoID 還指著某則
        //   （首播的上一則、或重複點同一則 / 中途改點別則時的「正在播的那則」），那個 false 事件會被
        //   onReceive 當成「播完」誤記。所以 play 前先把 playingTodoID 清成 nil（讓中斷的播放不算數），
        //   play 之後再設成本則 → 只有「自然播放結束」那次 false 事件才會把本則標記為已播完。
        playingTodoID = nil
        player.play(url: url, loop: false)
        playingTodoID = todo.id
    }

    /// 兒童長按（且已播完）→ 記一筆「已接收」並收起圖示。
    private func acknowledge(_ todo: Alarm) {
        guard playedThroughToday.contains(todo.id) else { return }   // 沒播完不算數
        guard !hasAcknowledgedToday(todo, now: now) else { return }  // 今天已記過就不重複
        let record = TodoPlayRecord(
            todoID: todo.id, todoLabel: todo.label,
            scheduledHour: todo.hour, scheduledMinute: todo.minute
        )
        modelContext.insert(record)
        try? modelContext.save()
        player.stop()
        now = Date()   // 立即重算 → 收起圖示
    }
}

// MARK: - Single badge

private struct TodoBadge: View {
    let icon: TodoIcon
    let isPlaying: Bool
    /// 已播完 → 可長按確認（顯示小勾勾提示）。
    let canAcknowledge: Bool
    let onPlay: () -> Void
    let onAcknowledge: () -> Void
    @State private var bob = false

    var body: some View {
        Text(icon.emoji)
            .font(.title)
            .scaleEffect(isPlaying ? 1.25 : 1.0)
            .offset(y: bob ? -4 : 0)
            .padding(8)
            .background(
                Circle().fill(Color.white.opacity(0.55))
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            )
            .overlay(
                Circle().strokeBorder(
                    canAcknowledge ? SunnyColors.leafFresh : SunnyColors.wheatGold.opacity(0.6),
                    lineWidth: canAcknowledge ? 2.5 : 1.5
                )
            )
            // 播完後右上角冒一個小勾勾，提示「長按可確認收起」。
            .overlay(alignment: .topTrailing) {
                if canAcknowledge {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(SunnyColors.leafFresh)
                        .background(Circle().fill(.white))
                        .offset(x: 4, y: -4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: bob)
            .animation(.spring(duration: 0.25), value: isPlaying)
            .animation(.spring(duration: 0.25), value: canAcknowledge)
            .onAppear { bob = true }
            .contentShape(Circle())
            .onTapGesture { onPlay() }                                  // 點 → 播放
            .onLongPressGesture(minimumDuration: 0.4) { onAcknowledge() } // 長按 → 確認收起（需先播完）
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(canAcknowledge ? "todo_badge_ack_a11y" : "todo_badge_a11y"))
    }
}
