// SunnyWalker — FamilyAlarmRequestSheet.swift  |  其他家族 app 傳來的鬧鐘請求：預覽 → 家長確認 → 加入
//
// 由 HomeView `.onOpenURL`（`rexsunny://alarm?...`）打開。外部 app 只能「提議」，
// 真的建鬧鐘要家長按「加入」——而且走跟「＋」一樣的家長閘（呼叫端負責）。
// 這裡不碰 SwiftData：按「加入」只回呼 onAdd(request)，插入與排程由 HomeView 做。

import SwiftUI

struct FamilyAlarmRequestSheet: View {
    let request: FamilyAlarmRequest
    let onAdd: (FamilyAlarmRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared

    private var kindTitle: LocalizedStringKey {
        switch request.kind {
        case .alarm: return "family_request_kind_alarm"
        case .chime: return "chime_card_title"
        case .todo:  return "todo_card_title"
        }
    }

    private var weekdayText: String {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        return request.weekdays.compactMap { (1...7).contains($0) ? L(symbols[$0 - 1]) : nil }.joined(separator: " ")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SunnyColors.cloudWhite.ignoresSafeArea()
                VStack(spacing: 24) {
                    MascotView()
                        .scaleEffect(0.8)
                        .frame(height: 150)

                    if let from = request.sourceApp {
                        Text(L("family_request_from %@", from))
                            .font(SunnyFonts.caption())
                            .foregroundStyle(SunnyColors.sunnyGray)
                    }

                    WatercolorCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(Alarm.timeString(hour: request.hour, minute: request.minute,
                                                  use24h: settings.use24HourClock))
                                .font(SunnyFonts.clock(44))
                                .foregroundStyle(SunnyColors.nightIndigo)
                            row("標籤", value: Text(verbatim: request.label.isEmpty ? L("起床囉") : request.label))
                            row("重覆", value: Text(verbatim: weekdayText))
                            row("family_request_kind", value: Text(kindTitle))
                        }
                        .padding(20)
                    }

                    Text("family_request_note")
                        .font(SunnyFonts.caption(13))
                        .foregroundStyle(SunnyColors.sunnyGray.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    Spacer()

                    SunnyButton("family_request_add", color: SunnyColors.lanternOrange) {
                        onAdd(request)
                        dismiss()
                    }
                    .padding(.horizontal, 8)
                }
                .padding(24)
            }
            .navigationTitle("family_request_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.sunnyGray)
                }
            }
        }
        .countsAsPresentedSheet()
    }

    private func row(_ title: LocalizedStringKey, value: Text) -> some View {
        HStack {
            Text(title)
                .font(SunnyFonts.caption())
                .foregroundStyle(SunnyColors.sunnyGray)
            Spacer()
            value
                .font(SunnyFonts.caption())
                .foregroundStyle(SunnyColors.nightIndigo)
        }
    }
}

#Preview {
    FamilyAlarmRequestSheet(
        request: FamilyAlarmRequest(hour: 7, minute: 30, label: "上學囉", weekdays: [2, 3, 4, 5, 6],
                                    kind: .alarm, sourceApp: "LetAbacus"),
        onAdd: { _ in }
    )
}
