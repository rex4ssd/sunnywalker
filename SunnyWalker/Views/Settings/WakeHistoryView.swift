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
                GhibliColors.cloudWhite.ignoresSafeArea()
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
                        .font(GhibliFonts.caption())
                        .foregroundStyle(GhibliColors.totoroGray)
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
                .font(GhibliFonts.title(22))
                .foregroundStyle(GhibliColors.nightIndigo)
            Text("小朋友每次成功起床後\n會在這裡留下記錄")
                .font(GhibliFonts.caption())
                .foregroundStyle(GhibliColors.totoroGray)
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
        default:         return "checkmark.circle"
        }
    }

    private var methodLabel: LocalizedStringKey {
        switch record.dismissMethod {
        case "voice":    return "method_voice"
        case "button":   return "method_button"
        case "fallback": return "method_fallback"
        default:         return "method_default"
        }
    }

    var body: some View {
        WatercolorCard {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.alarmLabel)
                        .font(GhibliFonts.caption())
                        .foregroundStyle(GhibliColors.nightIndigo)
                    Text(record.wokeAt.formatted(date: .abbreviated, time: .shortened))
                        .font(GhibliFonts.body(18))
                        .foregroundStyle(GhibliColors.nightIndigo)
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.caption)
                        Text(L("response_label %@", record.responseFormatted))
                            .font(GhibliFonts.caption(14))
                    }
                    .foregroundStyle(GhibliColors.totoroGray)
                }
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: methodIcon)
                        .font(.system(size: 20))
                        .foregroundStyle(GhibliColors.leafFresh)
                    Text(methodLabel)
                        .font(GhibliFonts.caption(12))
                        .foregroundStyle(GhibliColors.totoroGray)
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
