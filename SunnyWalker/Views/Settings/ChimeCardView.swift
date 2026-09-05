// SunnyWalker — ChimeCardView.swift  |  報時卡（新增／編輯鬧鐘頁，取代鈴聲卡）
//
// 報時群組的鬧鐘不選鈴聲，改設：
//   • 區間報時：從鬧鐘時間（起）開始，每隔 N 分報一次，直到「迄」時刻（迄本身不報）。
//     Rex 的情境：早上 7:00–7:30 用餐出門常拖延，「7:00 囉、7:05 囉 … 7:25 囉」催小孩。
//   • 人聲：iOS 內建語音，女聲／男聲（該語言沒裝男聲就只給女聲並說明怎麼下載）。
//   • 報時次數：每個時刻連報幾次（原本就有）。
//   • 試聽：用目前的起時刻 + 人聲合成一句播放。
//
// 這張卡只管畫面與綁定，不碰 SwiftData：真正寫回鬧鐘與合成語音檔在 AlarmEditorView.saveAlarm。

import SwiftUI

struct ChimeCardView: View {
    /// 起時刻（＝編輯器最上面的時間輪）。
    let startTime: Date
    @Binding var chimeCount: Int
    @Binding var intervalOn: Bool
    @Binding var endTime: Date
    @Binding var intervalMinutes: Int
    @Binding var voice: ChimeVoiceGender
    let isPreviewing: Bool
    let onPreview: () -> Void
    /// 時間輪的 12/24h locale（跟編輯器的時間輪同一份）。
    let pickerLocale: Locale

    @ObservedObject private var settings = AppSettings.shared
    /// 這個語言在裝置上有哪些性別的語音（進卡片時查一次；查 speechVoices 不便宜，不要放 body 裡）。
    @State private var availableGenders: Set<ChimeVoiceGender> = [.female]

    private var startHM: (Int, Int) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        return (c.hour ?? 7, c.minute ?? 0)
    }

    private var endHM: (Int, Int) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: endTime)
        return (c.hour ?? 7, c.minute ?? 30)
    }

    /// 目前設定會報的每個時刻（跟儲存後 AlarmScheduler 排的完全一樣——同一個純函式）。
    private var slots: [(hour: Int, minute: Int)] {
        let (sh, sm) = startHM
        let (eh, em) = endHM
        return Alarm.chimeSlotTimes(
            startHour: sh, startMinute: sm,
            endHour: intervalOn ? eh : nil, endMinute: intervalOn ? em : nil,
            intervalMinutes: intervalOn ? intervalMinutes : nil
        )
    }

    private var endIsBeforeStart: Bool {
        let (sh, sm) = startHM
        let (eh, em) = endHM
        return eh * 60 + em <= sh * 60 + sm
    }

    /// 「07:00、07:05 … 07:25」——最多列前 3 個 + 最後 1 個，中間用 …。
    private var scheduleSummary: String {
        let use24 = settings.use24HourClock
        let strs = slots.map { Alarm.timeString(hour: $0.hour, minute: $0.minute, use24h: use24) }
        let sep = L("、")
        if strs.count <= 4 { return strs.joined(separator: sep) }
        return strs.prefix(3).joined(separator: sep) + " … " + strs.last!
    }

    var body: some View {
        WatercolorCard {
            VStack(alignment: .leading, spacing: 14) {
                header

                Divider()

                // 區間報時開關
                Toggle(isOn: $intervalOn.animation(.easeInOut(duration: 0.2))) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("chime_interval_toggle", systemImage: "repeat.circle.fill")
                            .font(SunnyFonts.caption())
                            .foregroundStyle(SunnyColors.nightIndigo)
                        Text("chime_interval_footer")
                            .font(SunnyFonts.caption(13))
                            .foregroundStyle(SunnyColors.sunnyGray.opacity(0.82))
                    }
                }
                .tint(SunnyColors.lanternOrange)

                if intervalOn {
                    intervalRows
                }

                Divider()

                voiceRow

                Divider()

                // 報時次數（每個時刻連報幾次）
                HStack {
                    Label("chime_count_label", systemImage: "repeat")
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.nightIndigo)
                    Spacer()
                    Text(L("chime_times_value %lld", chimeCount))
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.lanternOrange)
                        .monospacedDigit()
                    Stepper("", value: $chimeCount, in: 1...Alarm.maxChimeCount)
                        .labelsHidden()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .onAppear {
            // 只用來決定要不要顯示「沒有男聲」的提示；**不改 voice**——進頁就改狀態會讓
            // 「取消」誤跳「尚未儲存的變更」。選了沒裝的性別由 ChimeSoundComposer 退回預設語音。
            availableGenders = ChimeSoundComposer.availableGenders(for: SunnyLocalization.locale)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.bubble.fill")
                .font(.title2)
                .foregroundStyle(SunnyColors.lanternOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text("chime_card_title")
                    .font(SunnyFonts.caption())
                    .foregroundStyle(SunnyColors.nightIndigo)
                Text("chime_card_subtitle")
                    .font(SunnyFonts.caption(13))
                    .foregroundStyle(SunnyColors.sunnyGray.opacity(0.82))
            }
            Spacer()
            // 試聽：合成「起」時刻 + 目前人聲的報時音並播放。合成需約 1 秒，期間圖示先進入播放態。
            Button(action: onPreview) {
                Image(systemName: isPreviewing ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(isPreviewing ? SunnyColors.lanternOrange : SunnyColors.skyBlue)
                    .symbolEffect(.pulse, isActive: isPreviewing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("試聽聲音"))
        }
    }

    @ViewBuilder
    private var intervalRows: some View {
        // 迄時刻
        HStack {
            Label("chime_end_label", systemImage: "flag.checkered")
                .font(SunnyFonts.caption())
                .foregroundStyle(SunnyColors.nightIndigo)
            Spacer()
            DatePicker("", selection: $endTime, displayedComponents: [.hourAndMinute])
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(SunnyColors.lanternOrange)
                // iOS 26 Liquid Glass：淺色卡片上 picker 文字會變白——強制 light（同時間輪的修法）。
                .colorScheme(.light)
                .environment(\.locale, pickerLocale)
        }

        // 間隔
        HStack {
            Label("chime_interval_label", systemImage: "timer")
                .font(SunnyFonts.caption())
                .foregroundStyle(SunnyColors.nightIndigo)
            Spacer()
            Menu {
                Picker("chime_interval_label", selection: $intervalMinutes) {
                    ForEach(Alarm.chimeIntervalOptions, id: \.self) { m in
                        Text(L("todo_duration_minutes %lld", m)).tag(m)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(L("todo_duration_minutes %lld", intervalMinutes))
                        .foregroundStyle(SunnyColors.lanternOrange)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SunnyColors.sunnyGray)
                }
                .font(SunnyFonts.caption())
            }
        }

        // 會報哪些時刻——所見即所得，家長不用猜「迄」有沒有算進去。
        if endIsBeforeStart {
            Label("chime_end_before_start", systemImage: "exclamationmark.triangle.fill")
                .font(SunnyFonts.caption(12))
                .foregroundStyle(SunnyColors.lanternOrange.opacity(0.95))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("chime_schedule_summary %@ %lld", scheduleSummary, slots.count))
                    .font(SunnyFonts.caption(13).monospacedDigit())
                    .foregroundStyle(SunnyColors.forestDeep)
                if slots.count >= Alarm.maxChimeSlots {
                    Text(L("chime_schedule_capped %lld", Alarm.maxChimeSlots))
                        .font(SunnyFonts.caption(12))
                        .foregroundStyle(SunnyColors.lanternOrange.opacity(0.95))
                }
            }
        }
    }

    private var voiceRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("chime_voice_label", systemImage: "person.wave.2.fill")
                    .font(SunnyFonts.caption())
                    .foregroundStyle(SunnyColors.nightIndigo)
                Spacer()
                Picker("chime_voice_label", selection: $voice) {
                    ForEach(ChimeVoiceGender.allCases) { g in
                        Text(LocalizedStringKey(g.labelKey)).tag(g)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                .colorScheme(.light)
            }
            if !availableGenders.contains(.male) {
                Text("chime_voice_male_unavailable")
                    .font(SunnyFonts.caption(12))
                    .foregroundStyle(SunnyColors.sunnyGray.opacity(0.8))
            }
        }
    }
}

#Preview {
    ZStack {
        SunnyColors.cloudWhite.ignoresSafeArea()
        ChimeCardView(
            startTime: Date(),
            chimeCount: .constant(2),
            intervalOn: .constant(true),
            endTime: .constant(Date().addingTimeInterval(1800)),
            intervalMinutes: .constant(5),
            voice: .constant(.female),
            isPreviewing: false,
            onPreview: {},
            pickerLocale: .current
        )
        .padding(24)
    }
}
