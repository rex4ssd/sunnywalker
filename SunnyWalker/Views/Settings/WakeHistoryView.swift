// SunnyWalker — WakeHistoryView.swift  |  Day 22  |  P5 parent wake history

import SwiftUI
import SwiftData

struct WakeHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\WakeRecord.wokeAt, order: .reverse)])
    private var records: [WakeRecord]

    var body: some View {
        NavigationStack {
            ZStack {
                SunnyColors.cloudWhite.ignoresSafeArea()
                if records.isEmpty {
                    emptyState
                } else {
                    recordList
                }
            }
            .navigationTitle("起床紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.sunnyGray)
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🌙")
                .font(.system(size: 64))
            Text("還沒有起床紀錄")
                .font(SunnyFonts.title(22))
                .foregroundStyle(SunnyColors.nightIndigo)
            Text("小朋友每次成功起床後\n會在這裡留下記錄")
                .font(SunnyFonts.caption())
                .foregroundStyle(SunnyColors.sunnyGray)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Record list

    private var recordList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(records) { record in
                    WakeRecordCard(record: record)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - WakeRecordCard

private struct WakeRecordCard: View {
    let record: WakeRecord

    private var methodIcon: String {
        switch record.dismissMethod {
        case "voice":    return "mic.fill"
        case "button":   return "hand.tap.fill"
        case "fallback": return "hand.tap"
        case "timeout":  return "bell.slash.fill"   // 無人回應，背景自動停鈴
        default:         return "checkmark.circle"
        }
    }

    private var methodLabel: LocalizedStringKey {
        switch record.dismissMethod {
        case "voice":    return "method_voice"
        case "button":   return "method_button"
        case "fallback": return "method_fallback"
        case "timeout":  return "method_timeout"
        default:         return "method_default"
        }
    }

    var body: some View {
        WatercolorCard {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.alarmLabel)
                        .font(SunnyFonts.caption())
                        .foregroundStyle(SunnyColors.nightIndigo)
                    Text(record.wokeAt.formatted(date: .abbreviated, time: .shortened))
                        .font(SunnyFonts.body(18))
                        .foregroundStyle(SunnyColors.nightIndigo)
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.caption)
                        Text(L("response_label %@", record.responseFormatted))
                            .font(SunnyFonts.caption(14))
                    }
                    .foregroundStyle(SunnyColors.sunnyGray)
                }
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: methodIcon)
                        .font(.system(size: 20))
                        .foregroundStyle(SunnyColors.leafFresh)
                    Text(methodLabel)
                        .font(SunnyFonts.caption(12))
                        .foregroundStyle(SunnyColors.sunnyGray)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}

#Preview {
    WakeHistoryView()
        .modelContainer(for: WakeRecord.self, inMemory: true)
}
